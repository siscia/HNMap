defmodule RedisManager do
  use GenServer

  @db_file "/home/simo/hn_map.sqlite"
  @db "HN_MAP_MEM"
  @item_table "CREATE TABLE IF NOT EXISTS items(id INTEGER PRIMARY KEY, type STRING, by STRING, time INTEGER, data STRING);"
  @insert_item "INSERT INTO items VALUES(?1, ?2, ?3, ?4, ?5)"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def store_item(server, item) do
    GenServer.call(server, {:store_item, item})
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

    {:ok, []}
  end

  def handle_call({:store_item, item}, _from, _data) do
    id = item["id"]
    type = item["type"]
    by = item["by"]
    time = item["time"]
    data = Poison.encode!(item)

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
end
