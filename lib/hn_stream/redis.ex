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

  def store_item(server, item) do
    GenServer.call(server, {:store_item, item}, 50_000)
  end

  def get_item(server, id) do
    GenServer.call(server, {:get_item, id}, 50_000)
  end

  def init(:ok) do
    try do
      # Redix.command(:redix, ["REDISQL.CREATE_DB", @db, @db_file])
      Redix.command(:redix, ["REDISQL.CREATE_DB", @db])
    rescue
      _ ->
        nil
    end

    try do
      Redix.command(:redix, ["REDISQL.EXEC", @db, @item_table])
    rescue
      _ -> nil
    end

    try do
      Redix.command(:redix, ["REDISQL.CREATE_STATEMENT", @db, "insert_item", @insert_item])
    rescue
      _ -> nil
    end

    try do
      Redix.command(:redix, ["REDISQL.CREATE_STATEMENT", @db, "get_item", @get_item])
    rescue
      _ -> nil
    end

    {:ok, []}
  end

  def handle_call({:store_item, item}, _from, _data) do
    id = item["id"]
    type = item["type"]
    by = item["by"]
    time = item["time"]
    data = Poison.encode!(item)

    # IO.inspect({:store_item, id})

    try do
      Redix.command(:redix, [
        "REDISQL.EXEC_STATEMENT",
        @db,
        "insert_item",
        id,
        type,
        by,
        time,
        data
      ])
    rescue
      e ->
        nil
    end

    {:reply, :ok, []}
  end

  def handle_call({:get_item, id}, _from, _data) do
    case Redix.command(:redix, ["REDISQL.QUERY_STATEMENT", @db, "get_item", id]) do
      {:ok, ["DONE", 0]} ->
        {:reply, {:ok, :empty}, []}

      {:ok, item} ->
        {:reply, {:ok, item}, []}
    end
  end
end
