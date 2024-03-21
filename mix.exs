defmodule GodwokenExplorer.MixProject do
  use Mix.Project

  def project do
    [
      app: :godwoken_explorer,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      name: "GodwokenExplorer",
      source_url: "https://github.com/Magickbase/godwoken_explorer",
      homepage_url: "http://v1.gwscan.com",
      docs: [
        main: "GodwokenExplorer",
        extras: ["README.md"],
        groups_for_modules: [
          Explorer: ~r/GodwokenExplorer.*/,
          Indexer: ~r/GodwokenIndexer.*/,
          RPC: ~r/GodwokenRPC.*/
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {GodwokenExplorer.Application, []},
      extra_applications: [:retry, :logger, :runtime_tools, :os_mon]
    ]
  end

  defp releases() do
    [
      godwoken_explorer: [
        applications: [godwoken_explorer: :permanent, runtime_tools: :permanent],
        include_erts: true,
        steps: [:assemble, :tar]
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", "test/factories"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # default phoneix template deps
      {:phoenix, "~> 1.7"},
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.11.0"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 3.3.0"},
      {:phoenix_view, "~> 2.0"},
      {:phoenix_live_reload, "~> 1.4.0", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6.1"},
      {:telemetry_poller, "~> 1.0.0"},
      {:gettext, "~> 0.23"},
      {:plug_cowboy, "~> 2.0"},
      {:httpoison, "~> 2.0"},
      {:rustler, "~> 0.30.0"},
      {:con_cache, "~> 1.0"},
      {:scrivener_ecto, "~> 2.0"},
      {:decimal, "~> 2.0"},
      {:logger_file_backend, "~> 0.0.10"},
      {:blake2_elixir, "~> 0.8.1"},
      {:fastglobal, "~> 1.0"},

      # live dashboard ecto stats
      {:ecto_psql_extras, "~> 0.7"},

      # encoder
      {:jason, "~> 1.0"},
      {:poison, "~> 5.0"},

      # admin dashboard
      {:torch, "~> 5.1.0"},

      # CORS
      {:cors_plug, "~> 3.0"},

      # monitor
      {:sentry, "~> 10.0"},
      {:nimble_options, "~> 1.0"},

      # static code analysis tool
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
      {:sobelow, "~> 0.13", only: :dev},

      # web3 tool
      {:ex_abi, "~> 0.6.0"},

      # database_history
      {:ex_audit, "~> 0.10.0"},

      # jsonapi
      {:jsonapi, "~> 1.6.2"},

      # tool
      {:timex, "~> 3.0"},
      {:retry, "~> 0.18"},
      {:briefly, "~> 0.5"},
      {:nimble_csv, "~> 1.1"},
      #      {:prom_ex, "~> 1.7.1"},
      {:dotenv, "~> 3.1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},

      # cron job
      {:oban, "~> 2.12"},

      # test
      {:ex_machina, "~> 2.7.0", only: [:test]},
      {:excoveralls, "~> 0.18.0", only: [:test]},
      {:mock, "~> 0.3.8", only: [:test], runtime: false},
      {:hammox, "~> 0.7", only: :test},
      {:ex_json_schema, "~> 0.10.0"},
      {:bypass, "~> 2.1", only: :test},

      # graphql
      {:absinthe, "~> 1.7.0"},
      {:absinthe_plug, "~> 1.5"},
      {:absinthe_phoenix, "~> 2.0"},
      {:dataloader, "~> 2.0"},
      {:money, "~> 1.9"},
      {:plug_heartbeat, "~> 1.0"},
      {:paginator, "~> 1.2.0"},
      {:quarto, "~> 1.0"},
      {:constants, "~> 0.1.0"},
      {:graphql_builder, "~> 0.3.4"},

      # http client
      {:tesla, "~> 1.4"},
      {:mint, "~> 1.0"},
      {:castore, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "cmd npm install --prefix assets"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["esbuild default --minify", "phx.digest"]
    ]
  end
end
