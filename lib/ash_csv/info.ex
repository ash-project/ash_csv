# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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

  def csv_module(resource) do
    Module.concat([resource, AshCsvNimbleCSV])
  end
end
