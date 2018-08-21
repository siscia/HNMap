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
      # {Scheduler, [17_709_752, 17_809_752, 5000]},
      {DynamicSupervisor, name: DynamicScheduler, strategy: :one_for_one},
      {Feeder, [17_708_642, 17_709_752]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HnStream.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
