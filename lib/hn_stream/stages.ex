defmodule Stage.Feeder do
  use GenStage

  def start_link({lower, upper}, opts \\ []) do
    GenStage.start_link(__MODULE__, {lower, upper}, opts)
  end

  def init({lower, upper}) do
    {:producer, {lower, upper}}
  end

  def handle_demand(demand, {lower, upper}) when demand > 0 do
    new_lower = min(lower + demand, upper)
    events = lower..new_lower
    {:noreply, events, {new_lower, upper}}
  end

  def handle_demand(demand, {n, n}) do
    {:stop, :finish_elements, {n, n}}
  end
end

defmodule Stage.Lookup do
  use GenStage

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:producer_consumer, nil}
  end

  def handle_events(events, _from, data) do
    events =
      events
      |> Enum.map(&RedisManager.get_item(&1))
      |> Enum.filter(&filter_empty(&1))
      |> Enum.map(&get_id(&1))

    {:noreply, events, data}
  end

  defp filter_empty({:ok, :empty, _}), do: true
  defp filter_empty({:ok, _, _}), do: false
  defp filter_empty(_), do: false

  defp get_id({:ok, :empty, id}), do: id
end

defmodule Stage.Fetch do
  use GenStage

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:producer_consumer, nil}
  end

  def handle_events(events, _, data) do
    events =
      events
      |> Enum.map(&Integer.to_string(&1))
      |> Enum.map(&HnMap.GetItem.get_item(&1))
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.map(&Poison.decode!(&1))

    {:noreply, events, data}
  end
end

defmodule Stage.Store do
  use GenStage

  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, :ok, opts)
  end

  def init(:ok) do
    {:consumer, nil}
  end

  def handle_events(events, _, data) do
    events =
      events
      |> Enum.map(&RedisManager.store_item(&1))

    {:noreply, events, data}
  end
end
