# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshCsv.DataLayer do
  @behaviour Ash.DataLayer

  alias Ash.Actions.Sort

  @filter_stream_size 100

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :update), do: true
  def can?(_, :upsert), do: true
  def can?(_, :destroy), do: true
  def can?(_, :sort), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :bulk_create), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, :transact), do: true
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, :nested_expressions), do: true
  def can?(_, :expression_calculation_sort), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, _), do: false

  @csv %Spark.Dsl.Section{
    name: :csv,
    examples: [
      """
      csv do
        file "priv/data/tags.csv"
        create? true
        header? true
        separator ?;
        columns [:id, :name]
      end
      """
    ],
    schema: [
      file: [
        type: :string,
        doc: "The file to read the data from",
        required: true
      ],
      create?: [
        type: :boolean,
        doc:
          "Whether or not the file should be created if it does not exist (this will only happen on writes)",
        default: false
      ],
      header?: [
        type: :boolean,
        default: false,
        doc: "If the csv file has a header that should be skipped"
      ],
      separator: [
        type: {:custom, __MODULE__, :separator_opt, []},
        default: ?,,
        doc: "The separator to use, defaults to a comma. Pass in a character (not a string)."
      ],
      columns: [
        type: {:custom, __MODULE__, :columns_opt, []},
        doc: "The order that the attributes appear in the columns of the CSV"
      ]
    ]
  }

  @deprecated "See `AshCsv.DataLayer.Info.file/1"
  defdelegate file(resource), to: AshCsv.DataLayer.Info

  @deprecated "See `AshCsv.DataLayer.Info.columns/1"
  defdelegate columns(resource), to: AshCsv.DataLayer.Info

  @deprecated "See `AshCsv.DataLayer.Info.separator/1"
  defdelegate separator(resource), to: AshCsv.DataLayer.Info

  @deprecated "See `AshCsv.DataLayer.Info.header?/1"
  defdelegate header?(resource), to: AshCsv.DataLayer.Info

  @deprecated "See `AshCsv.DataLayer.Info.create?/1"
  defdelegate create?(resource), to: AshCsv.DataLayer.Info

  @impl true
  def limit(query, offset, _), do: {:ok, %{query | limit: offset}}

  @impl true
  def offset(query, offset, _), do: {:ok, %{query | offset: offset}}

  @impl true
  def filter(query, filter, _resource) do
    {:ok, %{query | filter: filter}}
  end

  @impl true
  def sort(query, sort, _resource) do
    {:ok, %{query | sort: sort}}
  end

  @doc false
  def columns_opt(columns) do
    if Enum.all?(columns, &is_atom/1) do
      {:ok, columns}
    else
      {:error, "Expected all columns to be atoms"}
    end
  end

  @doc false
  def separator_opt(val) when is_integer(val) do
    {:ok, val}
  end

  def separator_opt(val) do
    {:error, "Expected a character for separator, got #{val}"}
  end

  @sections [@csv]

  @moduledoc """
  The data layer implementation for AshCsv
  """
  use Spark.Dsl.Extension,
    sections: @sections,
    persisters: [AshCsv.DataLayer.Transformers.BuildParser]

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset, :domain]
  end

  @impl true
  def run_query(query, resource) do
    read_file(resource, true, query.domain, query.filter, query.sort, query.offset, query.limit)
  rescue
    e in File.Error ->
      if create?(resource) do
        {:ok, []}
      else
        {:error, e}
      end
  end

  @impl true
  def create(resource, changeset) do
    case run_query(%Query{resource: resource}, resource) do
      {:ok, records} ->
        create_from_records(records, resource, changeset, false)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  # sobelow_skip ["Traversal"]
  def bulk_create(resource, stream, options) do
    stream = Enum.to_list(stream)

    if options[:upsert?] do
      # This is not optimized, but thats okay for now
      stream
      |> Enum.reduce_while({:ok, []}, fn changeset, {:ok, results} ->
        changeset =
          Ash.Changeset.set_context(changeset, %{
            private: %{upsert_fields: options[:upsert_fields] || []}
          })

        case upsert(resource, changeset, options.upsert_keys) do
          {:ok, result} ->
            {:cont,
             {:ok,
              [
                Ash.Resource.put_metadata(
                  result,
                  :bulk_create_index,
                  changeset.context.bulk_create.index
                )
                | results
              ]}}

          {:error, error} ->
            {:halt, {:error, error}}
        end
      end)
    else
      case run_query(%Query{resource: resource}, resource) do
        {:ok, records} ->
          pkey = Ash.Resource.Info.primary_key(resource)

          record_pkeys = MapSet.new(records, &Map.take(&1, pkey))

          base =
            if options.return_records? do
              :ok
            else
              {:ok, []}
            end

          Enum.reduce_while(stream, {record_pkeys, base}, fn changeset, {record_pkeys, results} ->
            pkey_value = Map.take(changeset.attributes, pkey)

            if pkey_value in record_pkeys do
              {:halt, {:error, "Record #{inspect(pkey_value)} is not unique"}}
            else
              case dump_row(resource, changeset) do
                {:ok, row} ->
                  iodata = csv_module(resource).dump_to_iodata([row])

                  result =
                    if File.exists?(file(resource)) do
                      :ok
                    else
                      if create?(resource) do
                        File.mkdir_p!(Path.dirname(file(resource)))
                        File.write!(file(resource), header(resource))
                        :ok
                      else
                        {:error, "Error while writing to CSV: #{inspect(:enoent)}"}
                      end
                    end

                  case result do
                    {:error, error} ->
                      {:halt, {:error, error}}

                    :ok ->
                      case write_result(resource, iodata) do
                        :ok ->
                          new_results =
                            if options.return_records? do
                              record =
                                resource
                                |> struct(changeset.attributes)
                                |> Ash.Resource.put_metadata(
                                  :bulk_create_index,
                                  changeset.context.bulk_create.index
                                )

                              {:ok, [record | results]}
                            else
                              :ok
                            end

                          {:cont, {MapSet.put(record_pkeys, pkey_value), new_results}}

                        {:error, error} ->
                          {:halt, {:error, error}}
                      end
                  end

                {:error, error} ->
                  {:error, {:error, error}}
              end
            end
          end)
          |> case do
            {:error, error} ->
              {:error, error}

            {_, result} ->
              result
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end

  # sobelow_skip ["Traversal"]
  defp write_result(resource, iodata, retry? \\ false) do
    resource
    |> file()
    |> File.write(iodata, [:append])
    |> case do
      :ok ->
        :ok

      {:error, :enoent} when retry? ->
        {:error, "Error while writing to CSV: #{inspect(:enoent)}"}

      {:error, :enoent} ->
        if create?(resource) do
          write_result(resource, iodata, true)
        else
          {:error, "Error while writing to CSV: #{inspect(:enoent)}"}
        end

      {:error, error} ->
        {:error, "Error while writing to CSV: #{inspect(error)}"}
    end
  end

  @impl true
  def upsert(resource, changeset, keys) do
    pkey = Ash.Resource.Info.primary_key(resource)
    keys = keys || pkey

    if Enum.any?(keys, &is_nil(Ash.Changeset.get_attribute(changeset, &1))) do
      create(resource, changeset)
    else
      key_filters =
        Enum.map(keys, fn key ->
          {key,
           Ash.Changeset.get_attribute(changeset, key) || Map.get(changeset.params, key) ||
             Map.get(changeset.params, to_string(key))}
        end)

      query = Ash.Query.do_filter(resource, and: [key_filters])

      resource
      |> resource_to_query(changeset.domain)
      |> Map.put(:filter, query.filter)
      |> Map.put(:tenant, changeset.tenant)
      |> run_query(resource)
      |> case do
        {:ok, []} ->
          create(resource, changeset)

        {:ok, [result]} ->
          to_set = Ash.Changeset.set_on_upsert(changeset, keys)

          changeset =
            changeset
            |> Map.put(:attributes, %{})
            |> Map.put(:data, result)
            |> Ash.Changeset.force_change_attributes(to_set)

          update(resource, changeset)

        {:ok, _} ->
          {:error, "Multiple records matching keys"}
      end
    end
  end

  @impl true
  def update(resource, changeset) do
    resource
    |> read_file(false, changeset.domain)
    |> do_update(resource, changeset)
  end

  @impl true
  def destroy(resource, %{data: record, domain: domain}) do
    resource
    |> read_file(false, domain)
    |> do_destroy(resource, record)
  end

  defp cast_stored(resource, keys) do
    resource.ash_csv_parse_row(keys)
  end

  @impl true
  def resource_to_query(resource, domain) do
    %Query{resource: resource, domain: domain}
  end

  @impl true
  def transaction(resource, fun, _timeout, _) do
    file = file(resource)

    :global.trans(
      {{:csv, file}, System.unique_integer()},
      fn ->
        try do
          Process.put({:csv_in_transaction, file(resource)}, true)
          {:res, fun.()}
        catch
          {{:csv_rollback, ^file}, value} ->
            {:error, value}
        end
      end,
      [node() | :erlang.nodes()],
      0
    )
    |> case do
      {:res, result} -> {:ok, result}
      {:error, error} -> {:error, error}
      :aborted -> {:error, "transaction failed"}
    end
  end

  @impl true
  def rollback(resource, error) do
    throw({{:csv_rollback, file(resource)}, error})
  end

  @impl true
  def in_transaction?(resource) do
    Process.get({:csv_in_transaction, file(resource)}, false) == true
  end

  def filter_matches(records, nil, _domain), do: records

  def filter_matches(records, filter, domain) do
    {:ok, records} = Ash.Filter.Runtime.filter_matches(domain, records, filter)
    records
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp do_destroy({:ok, results}, resource, record) do
    pkey = Ash.Resource.Info.primary_key(resource)

    changeset_pkey = Map.take(record, pkey)

    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, results} ->
      cast(resource, result, pkey, changeset_pkey, result, results)
    end)
    |> case do
      {:ok, rows} ->
        iodata = csv_module(resource).dump_to_iodata(rows)

        iodata =
          if header?(resource) do
            [header(resource), iodata]
          else
            iodata
          end

        resource
        |> file()
        |> File.write(iodata, [:write])
        |> case do
          :ok ->
            :ok

          {:error, error} ->
            {:error, "Error while writing to CSV: #{inspect(error)}"}
        end
    end
  end

  defp do_destroy({:error, error}, _, _), do: {:error, error}

  defp cast(resource, row, pkey, changeset_pkey, result, results) do
    case cast_stored(resource, row) do
      {:ok, casted} ->
        if Map.take(casted, pkey) == changeset_pkey do
          {:cont, {:ok, results}}
        else
          {:cont, {:ok, [result | results]}}
        end

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp do_update({:error, error}, _, _) do
    {:error, error}
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp do_update({:ok, results}, resource, changeset) do
    pkey = Ash.Resource.Info.primary_key(resource)

    changeset_pkey =
      Enum.into(pkey, %{}, fn key ->
        {key, Ash.Changeset.get_attribute(changeset, key)}
      end)

    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, results} ->
      dump(resource, changeset, results, result, pkey, changeset_pkey)
    end)
    |> case do
      {:ok, rows} ->
        iodata = csv_module(resource).dump_to_iodata(rows)

        if File.exists?(file(resource)) do
          :ok
        else
          if create?(resource) do
            File.mkdir_p!(Path.dirname(file(resource)))
            File.write!(file(resource), header(resource))
            :ok
          else
            {:error, "Error while writing to CSV: #{inspect(:enoent)}"}
          end
        end

        iodata =
          if header?(resource) do
            [header(resource), iodata]
          else
            iodata
          end

        resource
        |> file()
        |> File.write(iodata, [:write])
        |> case do
          :ok ->
            {:ok, struct(changeset.data, changeset.attributes)}

          {:error, error} ->
            {:error, "Error while writing to CSV: #{inspect(error)}"}
        end
    end
  end

  defp dump(resource, changeset, results, result, pkey, changeset_pkey) do
    case cast_stored(resource, result) do
      {:ok, casted} ->
        if Map.take(casted, pkey) == changeset_pkey do
          case dump_row(resource, %{changeset | data: casted}) do
            {:ok, row} -> {:cont, {:ok, [row | results]}}
            {:error, error} -> {:halt, {:error, error}}
          end
        else
          {:cont, {:ok, [result | results]}}
        end

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp dump_row(resource, changeset) do
    resource.ash_csv_dump_row(struct(changeset.data, changeset.attributes))
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_file(
         resource,
         decode?,
         domain,
         filter \\ nil,
         sort \\ nil,
         offset \\ nil,
         limit \\ nil,
         retry? \\ false
       ) do
    amount_to_drop =
      if header?(resource) do
        1
      else
        0
      end

    results =
      resource
      |> file()
      |> then(fn file ->
        if decode? do
          file
          |> File.stream!()
          |> Stream.drop(amount_to_drop)
          |> csv_module(resource).parse_stream(skip_headers: false)
          |> Stream.map(fn row ->
            case cast_stored(resource, row) do
              {:ok, casted} -> casted
              {:error, error} -> throw({:error, error})
            end
          end)
          |> filter_stream(domain, filter)
          |> sort_stream(resource, domain, sort)
          |> offset_stream(offset)
          |> limit_stream(limit)
          |> Enum.to_list()
        else
          file
          |> File.stream!()
          |> Stream.drop(amount_to_drop)
          |> csv_module(resource).parse_stream(skip_headers: false)
          |> Enum.to_list()
        end
      end)

    {:ok, results}
  rescue
    e in NimbleCSV.ParseError ->
      {:error, Exception.message(e)}

    e in File.Error ->
      if e.reason == :enoent && !retry? do
        file = file(resource)
        File.mkdir_p!(Path.dirname(file))
        File.write!(file(resource), header(resource))
        read_file(resource, decode?, domain, filter, sort, offset, limit, true)
      else
        reraise e, __STACKTRACE__
      end
  catch
    {:error, error} ->
      {:error, error}
  end

  defp sort_stream(stream, _resource, _domain, sort) when sort in [nil, []] do
    stream
  end

  defp sort_stream(stream, resource, domain, sort) do
    Sort.runtime_sort(stream, sort, domain: domain, resource: resource)
  end

  defp filter_stream(stream, _domain, nil), do: stream

  defp filter_stream(stream, domain, filter) do
    stream
    |> Stream.chunk_every(@filter_stream_size)
    |> Stream.flat_map(fn chunk ->
      filter_matches(chunk, filter, domain)
    end)
  end

  defp offset_stream(stream, offset) when offset in [0, nil], do: stream
  defp offset_stream(stream, offset), do: Stream.drop(stream, offset)

  defp limit_stream(stream, nil), do: stream
  defp limit_stream(stream, limit), do: Stream.take(stream, limit)

  # sobelow_skip ["Traversal.FileModule"]
  defp create_from_records(records, resource, changeset, retry?) do
    pkey = Ash.Resource.Info.primary_key(resource)
    pkey_value = Map.take(changeset.attributes, pkey)

    if Enum.find(records, fn record -> Map.take(record, pkey) == pkey_value end) do
      {:error, "Record is not unique"}
    else
      row =
        Enum.reduce_while(columns(resource), {:ok, []}, fn key, {:ok, row} ->
          value = Map.get(changeset.attributes, key)

          {:cont, {:ok, [to_string(value) | row]}}
        end)

      case row do
        {:ok, row} ->
          iodata = csv_module(resource).dump_to_iodata([Enum.reverse(row)])

          result =
            if File.exists?(file(resource)) do
              :ok
            else
              if create?(resource) do
                File.mkdir_p!(Path.dirname(file(resource)))
                File.write!(file(resource), header(resource))
                :ok
              else
                {:error, "Error while writing to CSV: #{inspect(:enoent)}"}
              end
            end

          case result do
            {:error, error} ->
              {:error, error}

            :ok ->
              resource
              |> file()
              |> File.write(iodata, [:append])
              |> case do
                :ok ->
                  {:ok, struct(resource, changeset.attributes)}

                {:error, :enoent} when retry? ->
                  {:error, "Error while writing to CSV: #{inspect(:enoent)}"}

                {:error, :enoent} ->
                  if create?(resource) do
                    create_from_records(records, resource, changeset, true)
                  else
                    {:error, "Error while writing to CSV: #{inspect(:enoent)}"}
                  end

                {:error, error} ->
                  {:error, "Error while writing to CSV: #{inspect(error)}"}
              end
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp header(resource) do
    if header?(resource) do
      separator =
        case separator(resource) do
          sep when is_integer(sep) ->
            <<sep>>

          sep ->
            to_string(sep)
        end

      resource |> columns() |> Enum.join(separator) |> Kernel.<>("\n")
    else
      ""
    end
  end

  defp csv_module(resource) do
    AshCsv.DataLayer.Info.csv_module(resource)
  end
end
