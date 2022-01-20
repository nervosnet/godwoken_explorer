defmodule GodwokenExplorer.DepositWithdrawalView do
  use GodwokenExplorer, :schema

  def list_by_block_number(block_number, page) do
    parsed_struct =
      withdrawal_base_query(dynamic([w], w.block_number == ^block_number))
      |> order_by(desc: :inserted_at)
      |> Repo.paginate(page: page)

    %{
      page: Integer.to_string(parsed_struct.page_number),
      total_count: Integer.to_string(parsed_struct.total_entries),
      data: parsed_struct.entries
    }
  end

  def list_by_udt_id(udt_id, page) do
    deposits = deposit_base_query(dynamic([d], d.udt_id == ^udt_id)) |> Repo.all()
    withdrawals = withdrawal_base_query(dynamic([w], w.udt_id == ^udt_id)) |> Repo.all()

    parse_struct(deposits ++ withdrawals, page)
  end

  def list_by_script_hash(script_hash, page) do
    deposits = deposit_base_query(dynamic([d], d.script_hash == ^script_hash)) |> Repo.all()
    withdrawals = withdrawal_base_query(dynamic([w], w.account_script_hash == ^script_hash)) |> Repo.all()
    parse_struct(deposits ++ withdrawals, page)
  end

  def parse_struct(original_struct, page) do
    parsed_struct =
      original_struct
      |> Enum.sort(&(&1.timestamp > &2.timestamp))
      |> Scrivener.paginate(%{page: page, page_size: 10})

    %{
      page: Integer.to_string(parsed_struct.page_number),
      total_count: Integer.to_string(parsed_struct.total_entries),
      data: parsed_struct.entries
    }
  end

  def withdrawal_base_query(condition) do
    from(w in WithdrawalRequest,
      join: u in UDT,
      on: u.id == w.udt_id,
      join: u2 in UDT,
      on: u2.id == w.fee_udt_id,
      join: b3 in Block,
      on: b3.number == w.block_number,
      where: ^condition,
      select: %{
        account_script_hash: w.account_script_hash,
        value: fragment("? / power(10, ?)::decimal", w.amount, u.decimal),
        capacity: w.capacity,
        owner_lock_hash: w.owner_lock_hash,
        payment_lock_hash: w.payment_lock_hash,
        sell_value: fragment("? / power(10, ?)::decimal", w.sell_amount, u.decimal),
        sell_capacity: w.sell_capacity,
        fee_value: fragment("? / power(10, ?)::decimal", w.fee_amount, u2.decimal),
        fee_udt_id: w.fee_udt_id,
        fee_udt_name: u2.name,
        fee_udt_symbol: u2.symbol,
        fee_udt_icon: u2.icon,
        sudt_script_hash: w.sudt_script_hash,
        udt_id: w.udt_id,
        udt_name: u.name,
        udt_symbol: u.symbol,
        udt_icon: u.icon,
        block_hash: w.block_hash,
        nonce: w.nonce,
        block_number: w.block_number,
        type: "withdrawal",
        timestamp: b3.timestamp
      }
    )
  end

  def deposit_base_query(condition) do
    from(d in DepositHistory,
      join: u in UDT,
      on: u.id == d.udt_id,
      where: ^condition,
      select: %{
        script_hash: d.script_hash,
        value: fragment("? / power(10, ?)::decimal", d.amount, u.decimal),
        udt_id: d.udt_id,
        layer1_block_number: d.layer1_block_number,
        layer1_tx_hash: d.layer1_tx_hash,
        layer1_output_index: d.layer1_output_index,
        ckb_lock_hash: d.ckb_lock_hash,
        timestamp: d.timestamp,
        udt_symbol: u.symbol,
        udt_name: u.name,
        udt_icon: u.icon,
        type: "deposit"
      }
    )
  end
end
