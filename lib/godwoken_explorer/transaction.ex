defmodule GodwokenExplorer.Transaction do
  use GodwokenExplorer, :schema

  alias GodwokenExplorer.Chain.Cache.Transactions

  @primary_key {:hash, :binary, autogenerate: false}
  schema "transactions" do
    field :args, :binary
    field :from_account_id, :integer
    field :nonce, :integer
    field :status, Ecto.Enum, values: [:committed, :finalized], default: :committed
    field :to_account_id, :integer
    field :type, Ecto.Enum, values: [:sudt, :polyjuice_creator, :polyjuice]
    field :block_number, :integer
    field :block_hash, :binary

    belongs_to(:block, Block, foreign_key: :block_hash, references: :hash, define_field: false)

    timestamps()
  end

  def changeset(transaction, attrs) do
    transaction
    |> cast(attrs, [
      :hash,
      :block_hash,
      :type,
      :from_account_id,
      :to_account_id,
      :nonce,
      :args,
      :status,
      :block_number
    ])
    |> validate_required([
      :hash,
      :from_account_id,
      :to_account_id,
      :nonce,
      :args,
      :status,
      :block_number
    ])
  end

  def create_transaction(%{type: :sudt} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Ecto.Changeset.put_change(:block_hash, attrs[:block_hash])
      |> Repo.insert()

    UDTTransfer.create_udt_transfer(attrs)
    transaction
  end

  def create_transaction(%{type: :polyjuice_creator} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Ecto.Changeset.put_change(:block_hash, attrs[:block_hash])
      |> Repo.insert()

    PolyjuiceCreator.create_polyjuice_creator(attrs)
    transaction
  end

  def create_transaction(%{type: :polyjuice} = attrs) do
    transaction =
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> Repo.insert()

    Polyjuice.create_polyjuice(attrs)
    transaction
  end

  # TODO: from and to may can refactor to be a single method
  def latest_10_records do
    case Transactions.all() do
      txs when is_list(txs) and length(txs) == 10 ->
        txs
        |> Enum.map(fn t ->
          t
          |> Map.take([:hash, :from_account_id, :to_account_id, :type])
          |> Map.merge(%{timestamp: t.block.inserted_at, success: true})
        end)

      _ ->
        from(t in Transaction,
          join: b in Block,
          on: b.hash == t.block_hash,
          join: a2 in Account,
          on: a2.id == t.from_account_id,
          join: a3 in Account,
          on: a3.id == t.to_account_id,
          select: %{
            hash: t.hash,
            timestamp: b.inserted_at,
            from: a2.eth_address,
            to: fragment("
              CASE WHEN a3.type = 'user' THEN encode(a3.eth_address, 'escape')
                 WHEN a3.type = 'polyjuice_contract' THEN encode(a3.short_address, 'escape')
                 ELSE a3.id::text END"),
            type: t.type,
            success: true
          },
          order_by: [desc: t.block_number, desc: t.inserted_at],
          limit: 10
        )
        |> Repo.all()
    end
  end

  def find_by_hash(hash) do
    tx =
      from(t in Transaction,
        join: b in Block,
        on: b.hash == t.block_hash,
        join: a2 in Account,
        on: a2.id == t.from_account_id,
        join: a3 in Account,
        on: a3.id == t.to_account_id,
        left_join: p in Polyjuice,
        on: p.tx_hash == t.hash,
        where: t.hash == ^hash,
        select: %{
          hash: t.hash,
          l2_block_number: t.block_number,
          timestamp: b.timestamp,
          l1_block_number: b.layer1_block_number,
          from: a2.eth_address,
          to: fragment("
              CASE WHEN a3.type = 'user' THEN encode(a3.eth_address, 'escape')
                 WHEN a3.type = 'polyjuice_contract' THEN encode(a3.short_address, 'escape')
                 ELSE a3.id::text END"),
          type: t.type,
          status: t.status,
          nonce: t.nonce,
          args: t.args,
          gas_price: p.gas_price,
          gas_used: p.gas_used,
          gas_limit: p.gas_limit,
          receive_address: p.receive_address,
          transfer_count: p.transfer_count,
          value: p.value,
          input: p.input
        }
      ) |> Repo.one()

    if is_nil(tx) do
      %{}
    else
      tx
    end
  end

  def list_by_account(%{type: type, account_id: account_id, eth_address: eth_address, contract_id: contract_id}) when type == :user do
    from(t in Transaction,
      join: b in Block,
      on: [hash: t.block_hash],
      join: a2 in Account,
      on: a2.id == t.from_account_id,
      join: a3 in Account,
      on: a3.id == t.to_account_id,
      left_join: p in Polyjuice,
      on: p.tx_hash == t.hash,
      where: (t.from_account_id == ^account_id or p.receive_address == ^eth_address) and t.to_address_id == ^contract_id,
      select: %{
        hash: t.hash,
        block_number: b.number,
        timestamp: b.timestamp,
        from: a2.eth_address,
        to: fragment("
              CASE WHEN a3.type = 'user' THEN encode(a3.eth_address, 'escape')
                 WHEN a3.type = 'polyjuice_contract' THEN encode(a3.short_address, 'escape')
                 ELSE a3.id::text END"),
        type: t.type,
        nonce: t.nonce,
        args: t.args,
        gas_price: p.gas_price,
        gas_used: p.gas_used,
        gas_limit: p.gas_limit,
        value: p.value,
        receive_address: p.receive_address,
        transfer_count: p.transfer_count,
        input: p.input
    },
      order_by: [desc: t.inserted_at]
    )
  end

  def list_by_account(%{type: type, account_id: account_id, eth_address: eth_address}) when type == :user do
    from(t in Transaction,
      join: b in Block,
      on: [hash: t.block_hash],
      join: a2 in Account,
      on: a2.id == t.from_account_id,
      join: a3 in Account,
      on: a3.id == t.to_account_id,
      left_join: p in Polyjuice,
      on: p.tx_hash == t.hash,
      where: t.from_account_id == ^account_id or p.receive_address == ^eth_address,
      select: %{
        hash: t.hash,
        block_number: b.number,
        timestamp: b.timestamp,
        from: a2.eth_address,
        to: fragment("
              CASE WHEN a3.type = 'user' THEN encode(a3.eth_address, 'escape')
                 WHEN a3.type = 'polyjuice_contract' THEN encode(a3.short_address, 'escape')
                 ELSE a3.id::text END"),
        type: t.type,
        nonce: t.nonce,
        args: t.args,
        gas_price: p.gas_price,
        gas_used: p.gas_used,
        gas_limit: p.gas_limit,
        value: p.value,
        receive_address: p.receive_address,
        transfer_count: p.transfer_count,
        input: p.input,
    },
      order_by: [desc: t.inserted_at]
    )
  end

  def list_by_account(%{type: type, account_id: account_id, eth_address: _eth_address}) when type in [:meta_contract, :udt, :polyjuice_root, :polyjuice_contract] do
    from(t in Transaction,
      join: b in Block,
      on: [hash: t.block_hash],
      join: a2 in Account,
      on: a2.id == t.from_account_id,
      join: a3 in Account,
      on: a3.id == t.to_account_id,
      left_join: p in Polyjuice,
      on: p.tx_hash == t.hash,
      where: t.to_account_id == ^account_id,
      select: %{
        hash: t.hash,
        block_number: b.number,
        timestamp: b.timestamp,
        from: a2.eth_address,
        to: fragment("
              CASE WHEN a3.type = 'user' THEN encode(a3.eth_address, 'escape')
                 WHEN a3.type = 'polyjuice_contract' THEN encode(a3.short_address, 'escape')
                 ELSE a3.id::text END"),
        type: t.type,
        gas_price: p.gas_price,
        gas_used: p.gas_used,
        gas_limit: p.gas_limit,
        receive_address: p.receive_address,
        transfer_count: p.transfer_count,
        value: p.value,
        input: p.input
    },
      order_by: [desc: t.inserted_at]
    )
  end

  def account_transactions_data(%{type: type, account_id: account_id, eth_address: eth_address}, page) do
    txs = list_by_account(%{type: type, account_id: account_id, eth_address: eth_address})
    original_struct = Repo.paginate(txs, page: page)

    parsed_result =
      Enum.map(original_struct.entries, fn record ->
        stringify_and_unix_maps(record)
      end)

    %{
      page: Integer.to_string(original_struct.page_number),
      total_count: Integer.to_string(original_struct.total_entries),
      txs: parsed_result
    }
  end

  def account_transactions_data(%{type: type, account_id: account_id, eth_address: eth_address, contract_id: contract_id}, page) do
    txs = list_by_account(%{type: type, account_id: account_id, eth_address: eth_address, contract_id: contract_id})
    original_struct = Repo.paginate(txs, page: page)

    parsed_result =
      Enum.map(original_struct.entries, fn record ->
        stringify_and_unix_maps(record)
      end)

    %{
      page: Integer.to_string(original_struct.page_number),
      total_count: Integer.to_string(original_struct.total_entries),
      txs: parsed_result
    }
  end

end
