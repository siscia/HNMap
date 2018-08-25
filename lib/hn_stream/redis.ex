defmodule RedisManager do
  use GenServer

  @db_file "/home/simo/hn_map.sqlite"
  @db "HN_MAP_MEM"
  @item_table "CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, type STRING, by STRING, time INTEGER, data STRING);"
  @insert_item "INSERT INTO items VALUES(?1, ?2, ?3, ?4, ?5)"
  @get_item "SELECT * FROM items WHERE id = ?1"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def store_item(item) do
    case :poolboy.status(:redis_manager_write_pool) do
      {:full, _, _, _} ->
        IO.inspect({:redis_manager_write_pool, :poolboy.status(:redis_manager_write_pool)})

      _ ->
        nil
    end

    :poolboy.transaction(:redis_manager_write_pool, fn p ->
      GenServer.call(p, {:store_item, item})
    end)
  end

  def get_item(id) do
    case :poolboy.status(:redis_manager_read_pool) do
      {:full, _, _, _} ->
        IO.inspect({:redis_manager_read_pool, :poolboy.status(:redis_manager_read_pool)})

      _ ->
        nil
    end

    :poolboy.transaction(:redis_manager_read_pool, fn p ->
      GenServer.call(p, {:get_item, id})
    end)
  end

  def init(:ok) do
    :eredis.q(:eredis, ["REDISQL.CREATE_DB", @db])
    {:ok, _} = :eredis.q(:eredis, ["REDISQL.EXEC.NOW", @db, @item_table])

    :eredis.q(:eredis, ["REDISQL.CREATE_STATEMENT.NOW", @db, "insert_item", @insert_item])

    :eredis.q(:eredis, ["REDISQL.CREATE_STATEMENT.NOW", @db, "get_item", @get_item])

    {:ok, {[], []}}
  end

  def handle_call({:store_item, item}, from, {data, receiver}) do
    id = item["id"]
    type = item["type"]
    by = item["by"]
    time = item["time"]
    raw = Poison.encode!(item)

    query = [
      "REDISQL.EXEC_STATEMENT.NOW",
      @db,
      "insert_item",
      id,
      type,
      by,
      time,
      raw
    ]

    data = [query | data]
    receiver = [{:store, from} | receiver]
    payload = {data, receiver}

    case :poolboy.status(:redis_write_pool) do
      {:full, _, _, _} ->
        IO.inspect({:redis_write_pool, :poolboy.status(:redis_write_pool)})
        {:reply, :ok, payload}

      {_, _, _, _} ->
        :poolboy.transaction(:redis_write_pool, fn p ->
          flush_buffer(p, payload)
        end)

        {:reply, :ok, {[], []}}
    end
  end

  def handle_call({:get_item, id}, from, {data, receiver}) do
    IO.inspect({:redis_read_pool, :poolboy.status(:redis_read_pool)})

    query = ["REDISQL.QUERY_STATEMENT.NOW", @db, "get_item", id]
    data = [query | data]
    receiver = [{:get, from, id} | receiver]
    payload = {data, receiver}

    case :poolboy.status(:redis_read_pool) do
      {:full, _, _, _} ->
        IO.inspect({:redis_read_pool, :poolboy.status(:redis_read_pool)})
        {:noreply, payload}

      {_, _, _, _} ->
        :poolboy.transaction(:redis_read_pool, fn p ->
          flush_buffer(p, payload)
        end)

        {:noreply, {[], []}}
    end
  end

  defp flush_buffer(redis, {data, receiver}) do
    result = :eredis.qp(redis, data)
    Enum.zip(receiver, result) |> defferite_reply
  end

  defp defferite_reply([]) do
    :ok
  end

  defp defferite_reply([{{:store, _}, _} | tail]) do
    defferite_reply(tail)
  end

  defp defferite_reply([{{:get, from, n}, result} | tail]) do
    case result do
      {:ok, ["DONE", "0"]} ->
        GenServer.reply(from, {:ok, :empty, n})

      {:ok, item} ->
        GenServer.reply(from, {:ok, item, n})

      _ ->
        GenServer.reply(from, result)
    end

    defferite_reply(tail)
  end
end
