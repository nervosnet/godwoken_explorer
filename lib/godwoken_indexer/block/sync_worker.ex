defmodule GodwokenIndexer.Block.SyncWorker do
  use GenServer

  import GodwokenRPC.Util, only: [hex_to_number: 1, timestamps: 0]
  import Ecto.Query, only: [from: 2]

  require Logger

  alias GodwokenExplorer.Token.BalanceReader
  alias GodwokenIndexer.Transform.{TokenTransfers, TokenBalances}
  alias GodwokenRPC.Block.{FetchedTipBlockHash, ByHash}
  alias GodwokenRPC.{Blocks, HTTP, Receipts}

  alias GodwokenExplorer.{
    AccountUDT,
    Block,
    Transaction,
    Chain,
    Repo,
    Account,
    WithdrawalRequest,
    Log,
    TokenTransfer,
    Polyjuice,
    PolyjuiceCreator
  }

  alias GodwokenExplorer.Chain.Events.Publisher
  alias GodwokenExplorer.Chain.Cache.Blocks, as: BlocksCache
  alias GodwokenExplorer.Chain.Cache.Transactions

  @default_worker_interval 20

  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state)
  end

  @impl true
  def init(state) do
    next_number = get_next_number()
    schedule_work(next_number)

    {:ok, state}
  end

  @impl true
  def handle_info({:work, next_number}, state) do
    {:ok, block_number} = fetch_and_import(next_number)

    Logger.info("=====================SYNC NUMBER:#{block_number}")
    # Reschedule once more
    schedule_work(block_number)

    {:noreply, state}
  end

  def fetch_and_import(next_number) do
    with {:ok, tip_number} <- fetch_tip_number(),
         true <- next_number <= tip_number do
      Logger.info("=====================TIP NUMBER:#{tip_number}")
      Logger.info("=====================NEXT NUMBER:#{next_number}")

      range = next_number..next_number

      {:ok,
       %Blocks{
         blocks_params: blocks_params,
         transactions_params: transactions_params_without_receipts,
         withdrawal_params: withdrawal_params,
         errors: _
       }} = GodwokenRPC.fetch_blocks_by_range(range)

      Logger.info("=====================FETCHED DATA")

      parent_hash =
        blocks_params
        |> List.first()
        |> Map.get(:parent_hash)

      if forked?(parent_hash, next_number - 1) do
        Logger.error("!!!!!!Layer2 forked!!!!!!#{next_number - 1}")
        Block.rollback!(parent_hash)
        throw(:rollback)
      end

      inserted_blocks =
        blocks_params
        |> Enum.map(fn block_params ->
          {:ok, %Block{} = block_struct} = Block.create_block(block_params)
          block_struct
        end)

      update_block_cache(inserted_blocks)
      Logger.info("=====================UPDATED BLOCKS")

      {polyjuice_without_receipts, polyjuice_creator_params} =
        transactions_params_without_receipts
        |> Enum.split_with(fn %{type: type} -> type == :polyjuice end)

      {:ok, %{logs: logs, receipts: receipts}} =
        GodwokenRPC.fetch_transaction_receipts(polyjuice_without_receipts)

      polyjuice_with_receipts = Receipts.put(polyjuice_without_receipts, receipts)
      %{token_transfers: token_transfers, tokens: _tokens} = TokenTransfers.parse(logs)

      address_token_balances =
        TokenBalances.params_set(%{token_transfers_params: token_transfers})

      balances = BalanceReader.get_balances_of(address_token_balances)

      import_account_udts =
        address_token_balances
        |> Enum.with_index()
        |> Enum.map(fn {%{
                          address_hash: address_hash,
                          token_contract_address_hash: token_contract_address_hash
                        }, index} ->
          {:ok, balance} = balances |> Enum.at(index)

          %{
            address_hash: address_hash,
            token_contract_address_hash: token_contract_address_hash,
            balance: balance
          }
          |> Map.merge(timestamps())
        end)

      Repo.insert_all(AccountUDT, import_account_udts,
        on_conflict: {:replace, [:balance, :updated_at]},
        conflict_target: [:address_hash, :token_contract_address_hash]
      )

      inserted_transaction_params =
        filter_transaction_columns(polyjuice_with_receipts ++ polyjuice_creator_params)

      {_count, returned_values} =
        Repo.insert_all(Transaction, inserted_transaction_params,
          on_conflict: :nothing,
          returning: [:from_account_id, :to_account_id, :hash, :type, :block_hash]
        )

      inserted_polyjuice_params = filter_polyjuice_columns(polyjuice_with_receipts)
      Repo.insert_all(Polyjuice, inserted_polyjuice_params, on_conflict: :nothing)

      inserted_polyjuice_creator_params =
        filter_polyjuice_creator_columns(polyjuice_creator_params)

      Repo.insert_all(PolyjuiceCreator, inserted_polyjuice_creator_params, on_conflict: :nothing)

      display_ids =
        (polyjuice_with_receipts ++ polyjuice_creator_params)
        |> extract_account_ids()
        |> Account.display_ids()

      inserted_transactions =
        returned_values
        |> Enum.map(fn tx ->
          tx
          |> Map.merge(%{
            from: display_ids |> Map.get(tx.from_account_id, {tx.from_account_id}) |> elem(0),
            to: display_ids |> Map.get(tx.to_account_id, {tx.to_account_id}) |> elem(0),
            to_alias:
              display_ids
              |> Map.get(tx.to_account_id, {tx.to_account_id, tx.to_account_id})
              |> elem(1)
          })
        end)

      update_transactions_cache(inserted_transactions)

      Logger.info("=====================UPDATED TRANSACTIONS")

      Repo.insert_all(Log, logs |> Enum.map(fn log -> Map.merge(log, timestamps()) end),
        on_conflict: :nothing
      )

      Logger.info("=====================UPDATED LOG")

      Repo.insert_all(
        TokenTransfer,
        token_transfers |> Enum.map(fn log -> Map.merge(log, timestamps()) end),
        on_conflict: :nothing
      )

      Logger.info("=====================UPDATED TOKENTRANSFER")
      Repo.insert_all(WithdrawalRequest, withdrawal_params, on_conflict: :nothing)

      trigger_account_worker(polyjuice_with_receipts)
      Logger.info("=====================UPDATED ACCOUNT")
      broadcast_block_and_tx(inserted_blocks, inserted_transactions)
      {:ok, next_number + 1}
    else
      _ -> {:ok, next_number}
    end
  end

  defp broadcast_block_and_tx(inserted_blocks, inserted_transactions) do
    home_blocks =
      Enum.map(inserted_blocks, fn block ->
        Map.take(block, [:hash, :number, :inserted_at, :transaction_count])
      end)

    home_transactions =
      Enum.map(inserted_transactions, fn tx ->
        tx
        |> Map.take([:hash, :type, :from, :to, :to_alias])
        |> Map.merge(%{
          timestamp: home_blocks |> List.first() |> Map.get(:inserted_at)
        })
      end)

    data = Chain.home_api_data(home_blocks, home_transactions)
    Publisher.broadcast([{:home, data}], :realtime)

    Enum.each(data[:tx_list], fn tx ->
      result = %{
        page: "1",
        total_count: "1",
        txs: [Map.merge(tx, %{block_number: home_blocks |> List.first() |> Map.get(:number)})]
      }

      Publisher.broadcast([{:account_transactions, result}], :realtime)
    end)
  end

  defp trigger_account_worker(transactions_params) do
    account_ids = extract_account_ids(transactions_params)

    if length(account_ids) > 0 do
      exist_ids = from(a in Account, where: a.id in ^account_ids, select: a.id) |> Repo.all()
      if length(exist_ids) > 0, do: Account.update_all_nonce!(exist_ids)

      (account_ids -- exist_ids)
      |> Enum.each(fn account_id ->
        Account.manual_create_account(account_id)
      end)
    end
  end

  defp update_block_cache([]), do: :ok

  defp update_block_cache(blocks) when is_list(blocks) do
    BlocksCache.update(blocks)
  end

  defp update_transactions_cache(transactions) do
    Transactions.update(transactions)
  end

  defp extract_account_ids(transactions_params) do
    transactions_params
    |> Enum.reduce([], fn transaction, acc ->
      acc ++ transaction[:account_ids]
    end)
    |> Enum.uniq()
  end

  defp filter_transaction_columns(params) do
    params
    |> Enum.map(fn %{
                     hash: hash,
                     from_account_id: from_account_id,
                     to_account_id: to_account_id,
                     args: args,
                     type: type,
                     nonce: nonce,
                     block_number: block_number,
                     block_hash: block_hash
                   } ->
      %{
        hash: hash,
        from_account_id: from_account_id,
        to_account_id: to_account_id,
        args: args,
        type: type,
        nonce: nonce,
        block_number: block_number,
        block_hash: block_hash
      }
      |> Map.merge(timestamps())
    end)
  end

  defp filter_polyjuice_columns(params) do
    params
    |> Enum.map(fn %{
                     is_create: is_create,
                     gas_limit: gas_limit,
                     gas_price: gas_price,
                     value: value,
                     input_size: input_size,
                     input: input,
                     gas_used: gas_used,
                     status: status,
                     receive_address: short_address,
                     receive_eth_address: eth_address,
                     transfer_count: transfer_count,
                     hash: hash
                   } ->
      %{
        is_create: is_create,
        gas_limit: gas_limit,
        gas_price: gas_price,
        value: value,
        input_size: input_size,
        input: input,
        gas_used: gas_used,
        status: status,
        receive_address: short_address,
        receive_eth_address: eth_address,
        transfer_count: transfer_count,
        tx_hash: hash
      }
      |> Map.merge(timestamps())
    end)
  end

  defp filter_polyjuice_creator_columns(params) do
    params
    |> Enum.map(fn %{
                     code_hash: code_hash,
                     hash_type: hash_type,
                     script_args: script_args,
                     fee_amount: fee_amount,
                     fee_udt_id: fee_udt_id,
                     hash: hash
                   } ->
      %{
        code_hash: code_hash,
        hash_type: hash_type,
        script_args: script_args,
        fee_amount: fee_amount,
        fee_udt_id: fee_udt_id,
        tx_hash: hash
      }
      |> Map.merge(timestamps())
    end)
  end

  defp fetch_tip_number do
    options = Application.get_env(:godwoken_explorer, :json_rpc_named_arguments)

    with {:ok, tip_block_hash} <- FetchedTipBlockHash.request() |> HTTP.json_rpc(options),
         {:ok, %{"block" => %{"raw" => %{"number" => tip_number}}}} <-
           ByHash.request(%{id: 1, hash: tip_block_hash}) |> HTTP.json_rpc(options) do
      {:ok, tip_number |> hex_to_number()}
    end
  end

  defp get_next_number do
    case Repo.one(from block in Block, order_by: [desc: block.number], limit: 1) do
      %Block{number: number} -> number + 1
      nil -> 0
    end
  end

  defp forked?(parent_hash, parent_block_number) do
    case Repo.get_by(Block, number: parent_block_number) do
      nil -> false
      %Block{hash: database_hash} -> parent_hash != database_hash
    end
  end

  defp schedule_work(next_number) do
    second =
      Application.get_env(:godwoken_explorer, :sync_worker_interval) ||
        @default_worker_interval

    Process.send_after(self(), {:work, next_number}, second * 1000)
  end
end
