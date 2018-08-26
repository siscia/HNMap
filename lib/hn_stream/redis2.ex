defmodule RedisManager2 do
  use GenServer

  @timeout_limit 3_000
  @top_reduction 100

  @db "HN_MAP_MEM"

  defstruct [:redis, :pipeline, :waiting, :reductions, :timeout]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, {:ok, 'localhost'}, opts)
  end

  def init({:ok, connection_opts}) do
    {:ok, redis} = :eredis.start_link(connection_opts)
    time = :erlang.monotonic_time(:millisecond) + @timeout_limit
    data = %RedisManager2{redis: redis, pipeline: [], waiting: [], reductions: 0, timeout: time}
    :erlang.send_after(@timeout_limit, self(), {:flush_timeout, time})
    {:ok, data}
  end

  def handle_call(
        {:store_item, item},
        from,
        state = %RedisManager2{reductions: reds, pipeline: pipeline, waiting: waiting}
      ) do
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

    state = %{
      state
      | reductions: reds + 1,
        pipeline: [query | pipeline],
        waiting: [from | waiting]
    }

    state =
      if state.reductions >= @top_reduction do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_call(
        {:get_item, id},
        from,
        state = %RedisManager2{reductions: reds, pipeline: pipeline, waiting: waiting}
      ) do
    query = ["REDISQL.QUERY_STATEMENT.NOW", @db, "get_item", id]

    state = %{
      state
      | reductions: reds + 1,
        pipeline: [query | pipeline],
        waiting: [from | waiting]
    }

    state =
      if state.reductions >= @top_reduction do
        flush(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:flush_timeout, time}, state = %RedisManager2{timeout: t}) when t <= time do
    state = flush(state)
    :erlang.send_after(@timeout_limit, self(), {:flush_timeout, time})
    {:noreply, state}
  end

  def handle_info({:flush_timeout, time}, state = %RedisManager2{timeout: t}) when t > time do
    time = :erlang.monotonic_time(:millisecond) + @timeout_limit
    :erlang.send_after(@timeout_limit, self(), {:flush_timeout, time})
    {:noreply, state}
  end

  defp flush(
         state = %RedisManager2{
           redis: redis,
           pipeline: pipeline,
           waiting: waiting,
           reductions: reds,
           timeout: timeout
         }
       ) do
    IO.inspect({:flush, reds})
    time = :erlang.monotonic_time(:millisecond) + @timeout_limit

    if reds >= @top_reduction or timeout + @timeout_limit <= time do
      spawn(fn ->
        results = :eredis.qp(redis, pipeline)
        :ok = Enum.zip(waiting, results) |> reply_from_pipeline
      end)

      %{state | pipeline: [], waiting: [], timeout: time, reductions: 0}
    else
      state
    end
  end

  defp reply_from_pipeline([]), do: :ok

  defp reply_from_pipeline([{from, result} | tail]) do
    GenServer.reply(from, result)
    reply_from_pipeline(tail)
  end
end
