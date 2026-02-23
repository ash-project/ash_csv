# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshCsv.DataLayer.Transformers.BuildParser do
  @moduledoc false
  use Spark.Dsl.Transformer

  def transform(dsl) do
    columns = AshCsv.DataLayer.Info.columns(dsl)
    separator = AshCsv.DataLayer.Info.separator(dsl) || ?,

    separator_string =
      try do
        <<separator::utf8>>
      rescue
        _ ->
          raise ArgumentError,
            "Invalid separator value: #{inspect(separator)}. Expected a valid UTF-8 character."
      end

    func_args =
      Enum.map(columns, fn name ->
        {name, [], Elixir}
      end)

    fields =
      Enum.map(columns, fn column ->
        attribute = Ash.Resource.Info.attribute(dsl, column)
        matcher = {column, [], Elixir}

        value =
          if Ash.Type.ecto_type(attribute.type) in [:string, :uuid, :binary_id] do
            quote do
              unquote(matcher)
            end
          else
            quote do
              if unquote(matcher) == "" do
                nil
              else
                unquote(matcher)
              end
            end
          end

        quote do
          value = unquote(value)

          unquote(matcher) =
            case Ash.Type.cast_stored(
                   unquote(Macro.escape(attribute.type)),
                   value,
                   unquote(Macro.escape(attribute.constraints))
                 ) do
              {:ok, value} ->
                value

              :error ->
                throw(
                  {:error,
                   "stored value for #{unquote(column)} could not be casted from the stored value to type #{unquote(inspect(Macro.escape(attribute.type)))}: #{inspect(value)}"}
                )
            end
        end
      end)

    dump_fields =
      Enum.map(columns, fn column ->
        attribute = Ash.Resource.Info.attribute(dsl, column)
        matcher = {column, [], Elixir}

        quote do
          value = unquote(matcher)

          unquote(matcher) =
            case Ash.Type.dump_to_embedded(
                   unquote(Macro.escape(attribute.type)),
                   value,
                   unquote(Macro.escape(attribute.constraints))
                 ) do
              {:ok, value} ->
                value

              :error ->
                throw(
                  {:error,
                   "stored value for #{unquote(column)} could not be dumped to type #{inspect(unquote(Macro.escape(attribute.type)))}: #{inspect(value)}"}
                )
            end
        end
      end)

    map = {:%{}, [], Enum.map(columns, fn column -> {column, {column, [], Elixir}} end)}

    resource_module = Spark.Dsl.Transformer.get_persisted(dsl, :module)
    csv_module = AshCsv.DataLayer.Info.csv_module(resource_module)

    struct =
      {:struct, [],
       [
         resource_module,
         map
       ]}

    {:ok,
     Spark.Dsl.Transformer.eval(
       dsl,
       [],
       quote do
        # Define the NimbleCSV parser
        NimbleCSV.define(unquote(csv_module),
          separator: unquote(separator_string),
          line_separator: "\n"
        )

        def ash_csv_dump_row(unquote(map)) do
           {:ok, unquote(dump_fields)}
         catch
           {:error, error} ->
             {:error, error}
         end

         def ash_csv_parse_row([unquote_splicing(func_args) | _]) do
           unquote(fields)
           {:ok, unquote(struct)}
         catch
           {:error, error} ->
             {:error, error}
         end

         def ash_csv_parse_row([unquote_splicing(func_args)]) do
           {:error, "Invald row #{inspect([unquote_splicing(func_args)])}"}
         end
       end
     )}
  end
end
