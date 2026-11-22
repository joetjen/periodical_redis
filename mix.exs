defmodule PeriodicalRedis.MixProject do
  @moduledoc false
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/joetjen/periodical_redis"

  @spec project() :: keyword()
  def project do
    [
      app: :periodical_redis,
      version: @version,
      elixir: "~> 1.19",
      name: "PeriodicalRedis",
      description: "Redis and KeyDB coordinator for Periodical: run each scheduled occurrence on one instance",
      source_url: @source_url,
      docs: docs(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  @spec application() :: keyword()
  def application, do: [extra_applications: [:logger]]

  @spec cli() :: keyword()
  def cli do
    [preferred_envs: [credo: :dev, dialyzer: :dev, docs: :docs, "hex.publish": :docs, precommit: :dev, test: :test]]
  end

  @spec elixirc_paths(atom()) :: [Path.t()]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  @spec dialyzer() :: keyword()
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_core_path: "_build/plts",
      plt_file: {:no_warn, "_build/plts/dialyzer.plt"}
    ]
  end

  @spec docs() :: keyword()
  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  @spec package() :: keyword()
  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  @spec aliases() :: keyword()
  defp aliases do
    [
      build: ["compile --force --warnings-as-errors"],
      precommit: [
        "build",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "cmd sh -c 'MIX_ENV=test mix test'"
      ]
    ]
  end

  @spec deps() :: [Mix.Project.dependency()]
  defp deps do
    [
      # development and test dependencies
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:docs], runtime: false},
      {:stream_data, "~> 1.2", only: [:dev, :test]},

      # runtime dependencies
      periodical(),
      {:redix, "~> 1.5"}
    ]
  end

  # Until the Periodical release with `Periodical.Coordinator` is on Hex,
  # develop against a checkout: PERIODICAL_PATH=../periodical mix test
  @spec periodical() :: Mix.Project.dependency()
  defp periodical do
    case System.get_env("PERIODICAL_PATH") do
      nil -> {:periodical, "~> 0.2"}
      path -> {:periodical, path: path, override: true}
    end
  end
end
