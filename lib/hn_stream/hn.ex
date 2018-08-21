defmodule Feeder do
  use Agent

  def start_link([lower, upper]) do
    Agent.start_link(fn ->
      for n <- lower..upper do
        DynamicSupervisor.start_child(DynamicScheduler, {Get, n})
      end
    end)
  end
end

defmodule HnMap.MaxItem do
  use GenServer

  @url "https://hacker-news.firebaseio.com/v0/maxitem.json"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, [name: MaxItemServer] ++ opts)
  end

  def max_item(server) do
    GenServer.call(server, :max_item)
  end

  def init(:ok) do
    {:ok, %{}}
  end

  def handle_call(:max_item, _from, _data) do
    max_item = HTTPotion.get(@url).body
    {:reply, max_item, %{}}
  end
end

defmodule HnMap.GetItem do
  @root "https://hacker-news.firebaseio.com/v0/item/"
  @leaf ".json"

  def get_item(item_id) do
    url = @root <> item_id <> @leaf
    response = HTTPotion.get(url)
    response.body
  end
end

defmodule Get do
  use Agent

  def start_link(n) do
    Agent.start_link(__MODULE__, :get, [n])
  end

  def get(n) do
    IO.puts(n)

    item =
      try do
        n
        |> Integer.to_string()
        |> HnMap.GetItem.get_item()
        |> Poison.decode!()
      rescue
        _ -> exit(:retry)
      end

    :ok = RedisManager.store_item(:redis_manager, item)
  end
end

defmodule Scheduler do
  use GenServer

  def start_link([lowerbound, upperbound, total_worker]) do
    GenServer.start_link(__MODULE__, {:ok, lowerbound, upperbound, total_worker}, [])
  end

  def spawn_workers([], map, _lowerbound, _upperbound) do
    map
  end

  def spawn_workers([i | tail], map, lowerbound, upperbound) do
    index = Kernel.min(lowerbound + i, upperbound)
    p = spawn_link(Get, :get, [index])
    spawn_workers(tail, Map.put(map, p, index), lowerbound, upperbound)
  end

  def init({:ok, lowerbound, upperbound, total_worker}) do
    Process.flag(:trap_exit, true)

    in_fligh = spawn_workers(Enum.to_list(0..total_worker), Map.new(), lowerbound, upperbound)

    lowerbound = Kernel.min(lowerbound + total_worker, upperbound)

    {:ok,
     %{
       lowerbound: lowerbound,
       upperbound: upperbound,
       total_worker: total_worker,
       in_fligh: in_fligh,
       errors: Map.new(),
       to_remove: 0
     }}
  end

  def handle_info({:EXIT, from, :normal}, data) do
    index = Map.get(data.in_fligh, from)

    in_fligh = Map.delete(data.in_fligh, from)
    data = Map.put(data, :in_fligh, in_fligh)

    lowerbound = data.lowerbound

    cond do
      lowerbound <= data.upperbound ->
        p = spawn_link(Get, :get, [lowerbound])
        in_fligh = Map.put(data.in_fligh, p, lowerbound)
        lowerbound = lowerbound + 1

        data =
          data
          |> Map.put(:in_fligh, in_fligh)
          |> Map.put(:lowerbound, lowerbound)

        {:noreply, data}

      lowerbound > data.upperbound ->
        {:noreply, data}
    end
  end

  def handle_info({:EXIT, from, _error}, data) do
    # get the failed index
    index = Map.get(data.in_fligh, from)
    # remove it from the in_fligh map
    in_fligh = Map.delete(data.in_fligh, from)
    data = Map.put(data, :in_fligh, in_fligh)

    case Map.get(data.errors, index) do
      errors when errors > 5 ->
        # giving up
        # remove the error count
        errors = Map.delete(data.errors, index)
        data = Map.put(data, :errors, errors)

        lowerbound = data.lowerbound
        upperbound = data.upperbound

        cond do
          lowerbound <= upperbound ->
            p = spawn_link(Get, :get, [lowerbound])
            lowerbound = lowerbound + 1
            in_fligh = Map.put(data.in_fligh, p, lowerbound)

            data =
              data
              |> Map.put(:in_fligh, in_fligh)
              |> Map.put(:lowerbound, lowerbound)

            {:noreply, data}

          lowerbound > upperbound ->
            {:noreply, data}
        end

      errors when errors <= 5 ->
        # spawn a new worker
        p = spawn_link(Get, :get, [index])
        # track again the new actor
        in_fligh = Map.put(in_fligh, p, index)
        # incremente the error count
        errors = Map.put(data.errors, index, errors + 1)

        data = Map.put(data, :errors, errors)
        data = Map.put(data, :in_fligh, in_fligh)

        {:noreply, data}
    end
  end

  def handle_info(message, data) do
    {:noreply, data}
  end
end
