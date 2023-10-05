defmodule AshCsv.MixProject do
  use Mix.Project

  @version "0.9.5"

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
    "documentation/**/*.{md,cheatmd,livemd}"
    |> Path.wildcard()
    |> Enum.map(fn path ->
      title =
        path
        |> Path.basename(".md")
        |> Path.basename(".livemd")
        |> Path.basename(".cheatmd")
        |> String.split(~r/[-_]/)
        |> Enum.map_join(" ", &capitalize/1)
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

  defp capitalize(string) do
    string
    |> String.split(" ")
    |> Enum.map(fn string ->
      [hd | tail] = String.graphemes(string)
      String.capitalize(hd) <> Enum.join(tail)
    end)
  end

  defp groups_for_extras() do
    [
      Tutorials: ~r'documentation/tutorials',
      "How To": ~r'documentation/how_to',
      Topics: ~r'documentation/topics',
      DSLs: ~r'documentation/dsls'
    ]
  end

  defp docs do
    [
      main: "get-started-with-csv",
      source_ref: "v#{@version}",
      before_closing_head_tag: fn type ->
        if type == :html do
          """
          <script>
            if (location.hostname === "hexdocs.pm") {
              var script = document.createElement("script");
              script.src = "https://plausible.io/js/script.js";
              script.setAttribute("defer", "defer")
              script.setAttribute("data-domain", "ashhexdocs")
              document.head.appendChild(script);
            }
          </script>
          """
        end
      end,
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
      {:ash, ash_version("~> 2.6")},
      {:csv, "~> 2.4"},
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.12.0", only: [:dev, :test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:dialyxir, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:sobelow, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.0.1", only: [:dev, :test]},
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
      docs: [
        "spark.cheat_sheets",
        "docs",
        "ash.replace_doc_links",
        "spark.cheat_sheets_in_search"
      ],
      "spark.formatter": "spark.formatter --extensions AshCsv.DataLayer",
      "spark.cheat_sheets": "spark.cheat_sheets --extensions AshCsv.DataLayer",
      "spark.cheat_sheets_in_search": "spark.cheat_sheets_in_search --extensions AshCsv.DataLayer"
    ]
  end
end
