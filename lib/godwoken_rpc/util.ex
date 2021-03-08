defmodule GodwokenRPC.Util do
  @stringify_keys ~w(from to block_number number tx_count l1_block l2_block nonce gas_price fee aggregator)a

  def hex_to_number(hex_number) do
    hex_number |> String.slice(2..-1) |> String.to_integer(16)
  end

  def number_to_hex(number) do
    "0x" <> (number |> Integer.to_string(16) |> String.downcase())
  end

  def utc_to_unix(iso_datetime) do
    iso_datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  end

  def stringify_and_unix_maps(original_map) do
    original_map
    |> Enum.into(%{}, fn {k, v} ->
      new_v =
        case k do
          n when n in @stringify_keys -> v |> Integer.to_string()
          :timestamp -> utc_to_unix(v)
          _ -> v
        end

      {k, new_v}
    end)
  end
end
