defmodule GodwokenExplorer.WithdrawalHistory do
  use GodwokenExplorer, :schema

  schema "withdrawal_histories" do
    field :block_hash, :binary
    field :block_number, :integer
    field :layer1_block_number, :integer
    field :l2_script_hash, :binary
    field :layer1_output_index, :integer
    field :layer1_tx_hash, :binary
    field :owner_lock_hash, :binary
    field :payment_lock_hash, :binary
    field :sell_amount, :decimal
    field :sell_capacity, :decimal
    field :udt_script_hash, :binary

    timestamps()
  end

  @doc false
  def changeset(withdrawal_history, attrs) do
    withdrawal_history
    |> cast(attrs, [:layer1_block_number, :layer1_tx_hash, :layer1_output_index, :l2_script_hash, :block_hash, :block_number, :udt_script_hash, :sell_amount, :sell_capacity, :owner_lock_hash, :payment_lock_hash])
    |> validate_required([:layer1_block_number, :layer1_tx_hash, :layer1_output_index, :l2_script_hash, :block_hash, :block_number, :udt_script_hash, :sell_amount, :sell_capacity, :owner_lock_hash, :payment_lock_hash])
    |> unique_constraint([:layer1_tx_hash, :layer1_block_number, :layer1_output_index])
  end

  def create_or_update_history!(attrs) do
    case Repo.get_by(__MODULE__, layer1_tx_hash: attrs[:layer1_tx_hash], layer1_block_number: attrs[:layer1_block_number], layer1_output_index: attrs[:layer1_output_index]) do
      nil -> %__MODULE__{}
      history -> history
    end
    |> changeset(attrs)
    |> Repo.insert_or_update!()
  end

  def rollback!(layer1_block_number) do
    from(w in WithdrawalHistory, where: w.layer1_block_number == ^layer1_block_number)
    |> Repo.all()
    |> Enum.each(fn history ->
      Repo.delete!(history)
    end)
  end
end
