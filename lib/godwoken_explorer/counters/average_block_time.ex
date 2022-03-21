defmodule GodwokenExplorer.Counters.AverageBlockTime do
  use GenServer

  @moduledoc """
  Caches the number of token holders of a token.
  """

  import Ecto.Query, only: [from: 2]

  alias GodwokenExplorer.{Block, Repo}
  alias Timex.Duration

  @latest_block_count 12

  @doc """
  Starts a process to periodically update the counter of the token holders.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def average_block_time do
    GenServer.call(__MODULE__, :average_block_time)
  end

  def refresh do
    GenServer.call(__MODULE__, :refresh_timestamps)
  end

  ## Server
  @impl true
  def init(_) do
    refresh_period = average_block_cache_period()
    Process.send_after(self(), :refresh_timestamps, refresh_period)

    {:ok, refresh_timestamps()}
  end

  @impl true
  def handle_call(:average_block_time, _from, %{average: average} = state), do: {:reply, average, state}

  @impl true
  def handle_call(:refresh_timestamps, _, _) do
    {:reply, :ok, refresh_timestamps()}
  end

  @impl true
  def handle_info(:refresh_timestamps, _) do
    refresh_period = Application.get_env(:explorer, __MODULE__)[:period]
    Process.send_after(self(), :refresh_timestamps, refresh_period)

    {:noreply, refresh_timestamps()}
  end

  defp refresh_timestamps do
    base_query =
      from(block in Block,
        limit: @latest_block_count,
        order_by: [desc: block.number],
        select: {block.number, block.timestamp}
      )

    timestamps_query =
        base_query

    timestamps_row =
      timestamps_query
      |> Repo.all()

    timestamps =
      timestamps_row
      |> Enum.sort_by(fn {_, timestamp} -> timestamp end, &>=/2)
      |> Enum.map(fn {number, timestamp} ->
        {number, DateTime.to_unix(timestamp, :millisecond)}
      end)

    %{timestamps: timestamps, average: average_distance(timestamps)}
  end

  defp average_distance([]), do: Duration.from_milliseconds(0)
  defp average_distance([_]), do: Duration.from_milliseconds(0)

  defp average_distance(timestamps) do
    durations = durations(timestamps)

    {sum, count} =
      Enum.reduce(durations, {0, 0}, fn duration, {sum, count} ->
        {sum + duration, count + 1}
      end)

    average = if count == 0, do: 0, else: sum / count

    average
    |> round()
    |> Duration.from_milliseconds()
  end

  defp durations(timestamps) do
    timestamps
    |> Enum.reduce({[], nil, nil}, fn {block_number, timestamp}, {durations, last_block_number, last_timestamp} ->
      if last_timestamp do
        block_numbers_range = last_block_number - block_number

        if block_numbers_range == 0 do
          {durations, block_number, timestamp}
        else
          duration = (last_timestamp - timestamp) / block_numbers_range
          {[duration | durations], block_number, timestamp}
        end
      else
        {durations, block_number, timestamp}
      end
    end)
    |> elem(0)
  end

  defp average_block_cache_period do
    case Integer.parse(System.get_env("AVERAGE_BLOCK_CACHE_PERIOD", "")) do
      {secs, ""} -> :timer.seconds(secs)
      _ -> :timer.minutes(30)
    end
  end
end
