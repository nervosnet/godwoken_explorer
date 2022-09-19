defmodule GodwokenRPC.Transaction.FetchedEthHashByGwHashes do
  alias GodwokenRPC.Transaction.FetchedEthHashByGwHash

  defstruct params_list: [],
            errors: []

  def from_responses(responses, id_to_params) do
    responses
    |> Enum.map(&FetchedEthHashByGwHash.from_response(&1, id_to_params))
    |> Enum.reduce(
      %__MODULE__{},
      fn
        {:ok, params}, %__MODULE__{params_list: params_list} = acc ->
          %__MODULE__{acc | params_list: [params | params_list]}

        {:error, reason}, %__MODULE__{errors: errors} = acc ->
          %__MODULE__{acc | errors: [reason | errors]}
      end
    )
  end

  def requests(id_to_params) when is_map(id_to_params) do
    Enum.map(id_to_params, fn {id, %{gw_tx_hash: tx_hash}} ->
      FetchedEthHashByGwHash.request(%{id: id, gw_tx_hash: tx_hash})
    end)
  end
end
