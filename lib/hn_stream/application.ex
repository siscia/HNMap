defmodule HnStream.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Redix, [[], [name: :redix]]},
      {RedisManager, [name: :redis_manager]},
      {DynamicSupervisor,
       [name: DynamicScheduler, strategy: :one_for_one, max_restarts: 5_000, max_seconds: 1]},
      {HyperFeeder, [[10_000_000, 10_100_000], []]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HnStream.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
