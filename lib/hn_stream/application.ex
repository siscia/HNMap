defmodule HnStream.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {RedisManager, [name: :redis_manager]},
      :poolboy.child_spec(
        :redis_read_pool,
        [
          {:name, {:local, :redis_read_pool}},
          {:worker_module, :eredis},
          {:size, 100},
          {:max_overflow, 300}
        ],
        [{:host, '51.15.142.13'}]
      ),
      :poolboy.child_spec(
        :redis_write_pool,
        [
          {:name, {:local, :redis_write_pool}},
          {:worker_module, :eredis},
          {:size, 50},
          {:max_overflow, 30}
        ],
        [{:host, '51.15.142.13'}]
      ),
      :poolboy.child_spec(
        :redis_manager_write_pool,
        [
          {:name, {:local, :redis_manager_write_pool}},
          {:worker_module, RedisManager},
          {:size, 500},
          {:max_overflow, 100}
        ],
        []
      ),
      :poolboy.child_spec(
        :redis_manager_read_pool,
        [
          {:name, {:local, :redis_manager_read_pool}},
          {:worker_module, RedisManager},
          {:size, 50},
          {:max_overflow, 100}
        ],
        []
      ),
      {DynamicSupervisor,
       [
         name: DynamicFeeder,
         strategy: :one_for_one,
         max_restarts: 5,
         max_seconds: 1
       ]},
      {DynamicSupervisor,
       [
         name: DynamicLookup,
         strategy: :one_for_one,
         max_restarts: 5_000,
         max_seconds: 1,
         max_children: 10_000
       ]},
      {DynamicSupervisor,
       [
         name: DynamicGetter,
         strategy: :one_for_one,
         max_restarts: 5_000,
         max_seconds: 1,
         max_children: 10_000
       ]},
      {DynamicSupervisor,
       [
         name: DynamicStorer,
         strategy: :one_for_one,
         max_restarts: 5_000,
         max_seconds: 1,
         max_children: 5_000
       ]},
      {Stage.Feeder, {{1, 100}, [name: :feeder]}},
      {Stage.Lookup, [name: :lookup]},
      {Stage.Fetch, [name: :fetch]},
      {Stage.Store, [name: :store]},
      {HyperFeeder, [[10_000_000, 10_100_000], []]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HnStream.Supervisor]
    {:ok, p} = :eredis.start_link([{:host, '51.15.142.13'}])
    Process.register(p, :eredis)
    Supervisor.start_link(children, opts)
  end
end
