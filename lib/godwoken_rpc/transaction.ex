defmodule GodwokenRPC.Transaction do
  import GodwokenRPC.Util, only: [hex_to_number: 1, parse_le_number: 1]
  import Godwoken.MoleculeParser, only: [parse_meta_contract_args: 1]

  def elixir_to_params(%{
        "block_hash" => block_hash,
        "block_number" => block_number,
        "raw" => %{
          "from_id" => from_account_id,
          "to_id" => to_account_id,
          "nonce" => nonce,
          "args" => "0x" <> args
        },
        "hash" => hash
      })
      when to_account_id == "0x0" do
    {{code_hash, hash_type, script_args}, {fee_sudt_id, fee_amount_hex_string}} =
      parse_meta_contract_args(args)

    udt_id = script_args |> String.slice(64..-1) |> parse_le_number()
    fee_amount = fee_amount_hex_string |> parse_le_number()
    from_account_id = hex_to_number(from_account_id)

    %{
      type: :polyjuice_creator,
      hash: hash,
      block_hash: block_hash,
      block_number: block_number,
      nonce: hex_to_number(nonce),
      args: "0x" <> args,
      from_account_id: from_account_id,
      to_account_id: hex_to_number(to_account_id),
      code_hash: "0x" <> code_hash,
      hash_type: transform_hash_type(hash_type),
      udt_id: udt_id,
      fee_udt_id: fee_sudt_id,
      fee_amount: fee_amount,
      script_args: script_args,
      account_ids: [from_account_id]
    }
  end

  def elixir_to_params(%{
        "block_hash" => block_hash,
        "block_number" => block_number,
        "raw" => %{
          "from_id" => from_account_id,
          "to_id" => to_id,
          "nonce" => nonce,
          "args" => "0x" <> args
        },
        "hash" => hash
      })
      when byte_size(args) == 80 do
    [to_account_id, amount, fee] = parse_sudt_args(args)
    from_account_id = hex_to_number(from_account_id)

    %{
      type: :sudt,
      hash: hash,
      block_hash: block_hash,
      block_number: block_number,
      nonce: hex_to_number(nonce),
      args: "0x" <> args,
      from_account_id: from_account_id,
      to_account_id: to_account_id,
      udt_id: hex_to_number(to_id),
      amount: amount,
      fee: fee,
      account_ids: [from_account_id, to_account_id]
    }
  end

  def elixir_to_params(%{
        "block_hash" => block_hash,
        "block_number" => block_number,
        "raw" => %{
          "from_id" => from_account_id,
          "to_id" => to_account_id,
          "nonce" => nonce,
          "args" => "0x" <> args
        },
        "hash" => hash
      }) do
    [is_create, gas_limit, gas_price, value, input_size, input] = parse_polyjuice_args(args)

    from_account_id = hex_to_number(from_account_id)
    to_account_id = hex_to_number(to_account_id)

    %{
      type: :polyjuice,
      hash: hash,
      block_hash: block_hash,
      block_number: block_number,
      nonce: hex_to_number(nonce),
      args: "0x" <> args,
      from_account_id: from_account_id,
      to_account_id: to_account_id,
      is_create: is_create,
      gas_limit: gas_limit,
      gas_price: gas_price,
      value: value,
      input_size: input_size,
      input: input,
      account_ids: [from_account_id, to_account_id]
    }
  end

  # withdrawal raw transaction
  # account_script_hash: "0xfde513739e40531ff59a7d06beba53abbcff59fa9c076e4b7441a5677fb59cf5"
  # amount: "0x0"
  # capacity: "0x9502f9000"
  # nonce: "0x4"
  # owner_lock_hash: "0xb98cd75013755a295a0cb273caa00b1de594b1692c806f8c3412a7962afb8b5e"
  # payment_lock_hash: "0x0000000000000000000000000000000000000000000000000000000000000000"
  # sell_amount: "0x0"
  # sell_capacity: "0x2540be400"
  # sudt_script_hash: "0x0000000000000000000000000000000000000000000000000000000000000000"
  def elixir_to_params(%{
        "block_hash" => block_hash,
        "block_number" => block_number,
        "raw" => %{
          "account_script_hash" => account_script_hash,
          "amount" => amount,
          "capacity" => capacity,
          "nonce" => nonce,
          "owner_lock_hash" => owner_lock_hash,
          "payment_lock_hash" => payment_lock_hash,
          "sell_amount" => sell_amount,
          "sell_capacity" => sell_capacity,
          "sudt_script_hash" => sudt_script_hash,
          "fee" => _fee
        },
        "hash" => hash
      }) do
    from_account_id = GodwokenRPC.fetch_account_id(account_script_hash)

    %{
      type: :withdrawal,
      hash: hash,
      block_hash: block_hash,
      block_number: block_number,
      nonce: hex_to_number(nonce),
      args: nil,
      from_account_id: from_account_id,
      # TODO: Maybe can withdraw to other account?
      to_account_id: from_account_id,
      account_script_hash: account_script_hash,
      amount: amount,
      capacity: capacity,
      owner_lock_hash: owner_lock_hash,
      payment_lock_hash: payment_lock_hash,
      sell_amount: sell_amount,
      sell_capacity: sell_capacity,
      sudt_script_hash: sudt_script_hash,
      # TODO: Can query from udt?
      udt_id: nil,
      account_ids: [from_account_id]
    }
  end

  defp parse_sudt_args(hex_string) do
    to_account_id =
      hex_string
      |> String.slice(8, 8)
      |> parse_le_number()

    amount =
      hex_string
      |> String.slice(16, 32)
      |> parse_le_number()

    fee =
      hex_string
      |> String.slice(48, 32)
      |> parse_le_number()

    [to_account_id, amount, fee]
  end

  defp parse_polyjuice_args(hex_string) do
    is_create = hex_string |> String.slice(14, 2) == "03"

    gas_limit =
      hex_string
      |> String.slice(16, 16)
      |> parse_le_number()

    gas_price =
      hex_string
      |> String.slice(32, 32)
      |> parse_le_number()

    value = hex_string |> String.slice(64, 32)

    input_size =
      hex_string
      |> String.slice(96, 8)
      |> parse_le_number()

    input = hex_string |> String.slice(104..-1)
    [is_create, gas_limit, gas_price, value, input_size, "0x" <> input]
  end

  defp transform_hash_type(hash_type) do
    case hash_type do
      "00" -> "data"
      _ -> "type"
    end
  end
end
