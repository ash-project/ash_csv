defmodule AshCsv.MixProject do
  use Mix.Project

  @version "0.1.1"

  @description "A CSV data layer for Ash"

  def project do
    [
      app: :ash_csv,
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test
      ],
      docs: docs(),
      aliases: aliases(),
      description: @description,
      source_url: "https://github.com/ash-project/ash_csv",
      homepage_url: "https://github.com/ash-project/ash_csv"
    ]
  end

  defp docs do
    [
      main: "AshCsv",
      source_ref: "v#{@version}",
      logo: "logos/small-logo.png"
    ]
  end

  defp package do
    [
      name: :ash_csv,
      licenses: ["MIT"],
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
      {:ash, "~> 1.9"},
      {:csv, "~> 2.3"},
      {:ex_doc, "~> 0.22", only: :dev, runtime: false},
      {:ex_check, "~> 0.11.0", only: :dev},
      {:credo, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:sobelow, ">= 0.0.0", only: :dev, runtime: false},
      {:git_ops, "~> 2.0.1", only: :dev},
      {:excoveralls, "~> 0.13.0", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      sobelow: "sobelow --skip",
      credo: "credo --strict",
      "ash.formatter": "ash.formatter --extensions AshCsv.DataLayer"
    ]
  end
end
