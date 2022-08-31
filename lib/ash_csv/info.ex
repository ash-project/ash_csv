defmodule AshCsv.DataLayer.Info do
  @moduledoc "Introspection helpers for AshCsv.DataLayer"

  alias Spark.Dsl.Extension

  def file(resource) do
    resource
    |> Extension.get_opt([:csv], :file, "", true)
    |> Path.expand(File.cwd!())
  end

  def columns(resource) do
    Extension.get_opt(resource, [:csv], :columns, [], true)
  end

  def separator(resource) do
    Extension.get_opt(resource, [:csv], :separator, nil, true)
  end

  def header?(resource) do
    Extension.get_opt(resource, [:csv], :header?, nil, true)
  end

  def create?(resource) do
    Extension.get_opt(resource, [:csv], :create?, nil, true)
  end
end
