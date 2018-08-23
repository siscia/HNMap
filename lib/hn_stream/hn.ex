defmodule HyperFeeder do
  use Agent

  def start_link([[lower, upper], opts]) do
    Agent.start_link(fn -> start_feeders(lower..upper) end)
  end

  def init({:ok, [lower, upper]}) do
    start_feeders(lower..upper)
  end

  def start_feeders(range) do
    start_feeders(range, 100)
  end

  def start_feeders(range, n) do
    chunks = Enum.chunk_every(range, n)
    start_feeders_chunks(chunks)
  end

  def start_feeders_chunks([chunk | chunks]) do
    lower = hd(chunk)
    upper = List.last(chunk)
    # spawn(fn -> Feeder.start_link([lower, upper]) end)
    spawn(fn -> DynamicSupervisor.start_child(DynamicScheduler, {Feeder, [lower, upper]}) end)
    start_feeders_chunks(chunks)
  end

  def start_feeders_chunks([]) do
  end
end

defmodule Feeder do
  use Agent

  def start_link([lower, upper]) do
    spawn(fn -> spawn_getter(lower, upper) end)

    Agent.start_link(fn ->
      nil
    end)
  end

  def spawn_getter(lower, lower) do
    spawn(fn -> DynamicSupervisor.start_child(DynamicScheduler, {Get, lower}) end)
  end

  def spawn_getter(lower, upper) do
    spawn(fn -> DynamicSupervisor.start_child(DynamicScheduler, {Get, lower}) end)
    spawn_getter(lower + 1, upper)
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
  use Task, restart: :transient

  def start_link(n) do
    Task.start_link(__MODULE__, :get, [n])
  end

  def get(n) do
    lookup =
      :poolboy.transaction(:redis_manager_pool, fn p ->
        RedisManager.get_item(p, n)
      end)

    case lookup do
      {:ok, :empty} ->
        item =
          n
          |> Integer.to_string()
          |> HnMap.GetItem.get_item()
          |> Poison.decode!()

        :ok =
          :poolboy.transaction(:redis_manager_pool, fn p ->
            RedisManager.store_item(p, item)
          end)

      {:ok, _} ->
        nil
    end
  end
end
