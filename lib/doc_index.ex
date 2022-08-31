defmodule AshCsv.DocIndex do
  @moduledoc false

  use Spark.DocIndex,
    otp_app: :ash_csv,
    guides_from: [
      "documentation/**/*.md"
    ]

  @impl true
  def for_library, do: "ash_csv"

  @impl true
  def extensions do
    [
      %{
        module: AshCsv.DataLayer,
        name: "AshCsv",
        target: "Ash.Resource",
        type: "DataLayer"
      }
    ]
  end

  @impl true
  def code_modules do
    [
      {"Introspection",
       [
         AshCsv.DataLayer.Info
       ]}
    ]
  end
end
