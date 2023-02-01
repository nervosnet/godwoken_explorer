defmodule GodwokenExplorer.SmartContract do
  @moduledoc """
  The representation of a verified Smart Contract.

  "A contract in the sense of Solidity is a collection of code (its functions)
  and data (its state) that resides at a specific address on the Ethereum
  blockchain."
  http://solidity.readthedocs.io/en/v0.4.24/introduction-to-smart-contracts.html
  """
  use GodwokenExplorer, :schema

  alias GodwokenExplorer.Chain
  alias GodwokenExplorer.Chain.Hash
  alias GodwokenExplorer.Counters.AverageBlockTime
  alias GodwokenExplorer.ETS.SmartContracts, as: ETSSmartContracts
  alias GodwokenExplorer.SmartContract.Reader
  alias Timex.Duration

  @typedoc """
  * `abi` - Contract abi.
  * `contract_source_code` - Contract code.
  * `name` - Contract name.
  * `constructor_arguments` - Contract constructor arguments.
  * `deployment_tx_hash` - Contract deployment at which transaction.
  * `compiler_version` - Contract compiler version.
  * `compiler_file_format` - Solidity or other.
  * `other_info` - Some info.
  * `ckb_balance` - SmartContract ckb balance.
  * `account_id` - The account foreign key.
  * `address_hash` - The account's eth address.
  * `implementation_name` - name of the proxy implementation
  * `implementation_fetched_at` - timestamp of the last fetching contract's implementation info
  * `implementation_address_hash` - address hash of the proxy's implementation if any
  """
  @type t :: %__MODULE__{
          abi: list(map()),
          contract_source_code: String.t(),
          name: non_neg_integer() | nil,
          constructor_arguments: Hash.Address.t(),
          deployment_tx_hash: Hash.Address.t(),
          compiler_version: Hash.Address.t(),
          compiler_file_format: String.t(),
          other_info: String.t(),
          ckb_balance: Decimal.t(),
          account_id: Integer.t(),
          account: %Ecto.Association.NotLoaded{} | Account.t(),
          address_hash: Hash.Address.t(),
          implementation_name: String.t() | nil,
          implementation_fetched_at: DateTime.t(),
          implementation_address_hash: Hash.Address.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }
  @derive {Jason.Encoder, except: [:__meta__]}
  schema "smart_contracts" do
    field(:abi, {:array, :map})
    field(:contract_source_code, :string)
    field(:name, :string)

    belongs_to(
      :account,
      Account,
      foreign_key: :account_id,
      references: :id,
      type: :integer
    )

    field(:constructor_arguments, :binary)
    field(:deployment_tx_hash, Hash.Full)
    field(:compiler_version, :string)
    field(:compiler_file_format, :string)
    field(:other_info, :string)
    field(:ckb_balance, :decimal)
    field(:eth_address, :binary, virtual: true)
    field(:address_hash, Hash.Address)
    field(:implementation_name, :string)
    field(:implementation_fetched_at, :utc_datetime_usec, default: nil)
    field(:implementation_address_hash, Hash.Address, default: nil)

    timestamps()
  end

  defp base_fields() do
    GodwokenExplorer.SchemeUtils.base_fields_without_id(__MODULE__)
  end

  @doc false
  def changeset(smart_contract, attrs) do
    smart_contract
    |> cast(attrs, base_fields())
    |> validate_required([:account_id])
    |> unique_constraint(:account_id)
  end

  def reformat_abi(abi) do
    abi
    |> Enum.map(&map_abi/1)
    |> Map.new()
  end

  def account_ids do
    if ETSSmartContracts.get(:contract_account_ids) do
      ETSSmartContracts.get(:contract_account_ids)
    else
      account_ids = SmartContract |> select([sc], sc.account_id) |> Repo.all()
      ETSSmartContracts.put(:contract_account_ids, account_ids)
      account_ids
    end
  end

  def cache_abis() do
    from(sc in SmartContract)
    |> Repo.all()
    |> Enum.chunk_every(10)
    |> Enum.map(fn sm_cs ->
      sm_cs
      |> Task.async_stream(fn sm_c ->
        ETSSmartContracts.put("contract_abi_#{sm_c.account_id}", sm_c.abi)
        {"contract_abi_#{sm_c.account_id}", sm_c.abi}
      end)
      |> Enum.to_list()
    end)
    |> List.flatten()
    |> Enum.into(%{})
  end

  def cache_abi(account_id) do
    if ETSSmartContracts.get("contract_abi_#{account_id}") do
      ETSSmartContracts.get("contract_abi_#{account_id}")
    else
      abi =
        from(sc in SmartContract, where: sc.account_id == ^account_id, select: sc.abi)
        |> Repo.one()

      ETSSmartContracts.put("contract_abi_#{account_id}", abi)
      abi
    end
  end

  def creator_address(smart_contract) do
    if smart_contract.deployment_tx_hash != nil do
      from(t in Transaction,
        join: a in Account,
        on: a.id == t.from_account_id,
        where: t.hash == ^smart_contract.deployment_tx_hash,
        select: a.eth_address
      )
      |> limit(1)
      |> Repo.one()
    else
      nil
    end
  end

  def get_implementation_address_hash(%__MODULE__{abi: nil}), do: {nil, nil}

  def get_implementation_address_hash(%__MODULE__{
        implementation_address_hash: implementation_address_hash_from_db,
        implementation_name: implementation_name_from_db
      })
      when not is_nil(implementation_address_hash_from_db),
      do: {to_string(implementation_address_hash_from_db), implementation_name_from_db}

  def get_implementation_address_hash(%__MODULE__{
        address_hash: proxy_address_hash,
        abi: abi,
        implementation_fetched_at: implementation_fetched_at
      }) do
    if check_implementation_refetch_neccessity(implementation_fetched_at) do
      get_implementation_address_hash(proxy_address_hash, abi)
    end
  end

  def get_implementation_address_hash(_), do: {nil, nil}

  @spec get_implementation_address_hash(Hash.Address.t(), list()) ::
          {String.t() | nil, String.t() | nil}
  defp get_implementation_address_hash(proxy_address_hash, abi)
       when not is_nil(proxy_address_hash) and not is_nil(abi) do
    implementation_method_abi =
      abi
      |> Enum.find(fn method ->
        Map.get(method, "name") == "implementation" &&
          Map.get(method, "stateMutability") == "view"
      end)

    if implementation_method_abi do
      implementation_address =
        get_implementation_address_hash_basic(to_string(proxy_address_hash), abi)

      save_implementation_data(
        implementation_address,
        proxy_address_hash
      )
    end
  end

  defp save_implementation_data(implementation_address_hash_string, proxy_address_hash)
       when is_binary(implementation_address_hash_string) do
    with {:ok, address_hash} <- Chain.string_to_address_hash(implementation_address_hash_string),
         proxy_contract <- Chain.address_hash_to_smart_contract(proxy_address_hash),
         false <- is_nil(proxy_contract),
         %{implementation: %__MODULE__{name: name}, proxy: proxy_contract} <- %{
           implementation: Chain.address_hash_to_smart_contract(address_hash),
           proxy: proxy_contract
         } do
      proxy_contract
      |> changeset(%{
        implementation_name: name,
        implementation_address_hash: implementation_address_hash_string,
        implementation_fetched_at: DateTime.utc_now()
      })
      |> Repo.update()

      {implementation_address_hash_string, name}
    else
      %{implementation: _, proxy: proxy_contract} ->
        proxy_contract
        |> changeset(%{
          implementation_name: nil,
          implementation_address_hash: implementation_address_hash_string,
          implementation_fetched_at: DateTime.utc_now()
        })
        |> Repo.update()

        {implementation_address_hash_string, nil}

      true ->
        {:ok, address_hash} = Chain.string_to_address_hash(implementation_address_hash_string)
        smart_contract = Chain.address_hash_to_smart_contract(address_hash)

        {implementation_address_hash_string, smart_contract && smart_contract.name}

      _ ->
        {implementation_address_hash_string, nil}
    end
  end

  defp check_implementation_refetch_neccessity(nil), do: true

  defp check_implementation_refetch_neccessity(timestamp) do
    if Application.get_env(:explorer, :enable_caching_implementation_data_of_proxy) do
      now = DateTime.utc_now()

      average_block_time =
        if Application.get_env(
             :explorer,
             :avg_block_time_as_ttl_cached_implementation_data_of_proxy
           ) do
          case AverageBlockTime.average_block_time() do
            {:error, :disabled} ->
              0

            duration ->
              duration
              |> Duration.to_milliseconds()
          end
        else
          0
        end

      fresh_time_distance =
        case average_block_time do
          0 ->
            Application.get_env(:explorer, :fallback_ttl_cached_implementation_data_of_proxy)

          time ->
            round(time)
        end

      timestamp
      |> DateTime.add(fresh_time_distance, :millisecond)
      |> DateTime.compare(now) != :gt
    else
      true
    end
  end

  defp address_to_hex(address) do
    if address do
      if String.starts_with?(address, "0x") do
        address
      else
        "0x" <> Base.encode16(address, case: :lower)
      end
    end
  end

  defp get_implementation_address_hash_basic(proxy_address_hash, abi) do
    # 5c60da1b = keccak256(implementation())
    implementation_address =
      case Reader.query_contract(
             proxy_address_hash,
             abi,
             %{
               "5c60da1b" => []
             },
             false
           ) do
        %{"5c60da1b" => {:ok, [result]}} -> result
        _ -> nil
      end

    address_to_hex(implementation_address)
  end

  defp map_abi(x) do
    case {x["name"], x["type"]} do
      {nil, "constructor"} -> {:constructor, x}
      {nil, "fallback"} -> {:fallback, x}
      {name, _} -> {name, x}
    end
  end
end
