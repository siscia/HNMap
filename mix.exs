defmodule HnStream.MixProject do
  use Mix.Project

  def project do
    [
      app: :hn_stream,
      version: "0.1.0",
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {HnStream.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:redix, ">= 0.7.0"},
      {:httpotion, "~> 3.1.0"},
      {:poison, "~> 3.1"},
      {:poolboy, "~> 1.5.1"}
    ]
  end
end
