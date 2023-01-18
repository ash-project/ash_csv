defmodule AshCsv.MixProject do
  use Mix.Project

  @version "0.9.1"

  @description "A CSV data layer for Ash"

  def project do
    [
      app: :ash_csv,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      aliases: aliases(),
      description: @description,
      source_url: "https://github.com/ash-project/ash_csv",
      homepage_url: "https://github.com/ash-project/ash_csv"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp extras() do
    "documentation/**/*.md"
    |> Path.wildcard()
    |> Enum.map(fn path ->
      title =
        path
        |> Path.basename(".md")
        |> String.split(~r/[-_]/)
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")
        |> case do
          "F A Q" ->
            "FAQ"

          other ->
            other
        end

      {String.to_atom(path),
       [
         title: title
       ]}
    end)
  end

  defp groups_for_extras() do
    "documentation/*"
    |> Path.wildcard()
    |> Enum.map(fn folder ->
      name =
        folder
        |> Path.basename()
        |> String.split(~r/[-_]/)
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      {name, folder |> Path.join("**") |> Path.wildcard()}
    end)
  end

  defp docs do
    [
      main: "AshCsv",
      source_ref: "v#{@version}",
      spark: [
        extensions: [
          %{
            module: AshCsv.DataLayer,
            name: "AshCsv",
            target: "Ash.Resource",
            type: "DataLayer"
          }
        ]
      ],
      extras: extras(),
      groups_for_extras: groups_for_extras(),
      groups_for_modules: [
        Introspection: [
          AshCsv.DataLayer.Info
        ],
        Internals: ~r/.*/
      ],
      logo: "logos/small-logo.png"
    ]
  end

  defp package do
    [
      name: :ash_csv,
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*
      CHANGELOG* documentation),
      links: %{
        GitHub: "https://github.com/ash-project/ash_csv"
      }
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, ash_version("~> 2.0")},
      {:csv, "~> 2.4"},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:ex_check, "~> 0.12.0", only: :dev},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, ">= 0.0.0", only: :dev, runtime: false},
      {:git_ops, "~> 2.0.1", only: :dev},
      {:excoveralls, "~> 0.13.0", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp ash_version(default_version) do
    case System.get_env("ASH_VERSION") do
      nil -> default_version
      "local" -> [path: "../ash"]
      "main" -> [git: "https://github.com/ash-project/ash.git"]
      version -> "~> #{version}"
    end
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      docs: ["docs", "ash.replace_doc_links"],
      "spark.formatter": "spark.formatter --extensions AshCsv.DataLayer"
    ]
  end
end
