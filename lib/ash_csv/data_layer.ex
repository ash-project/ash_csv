defmodule AshCsv.DataLayer do
  @behaviour Ash.DataLayer

  alias Ash.Actions.Sort
  alias Ash.Dsl.Extension

  @impl true
  def can?(_, :read), do: true
  def can?(_, :create), do: true
  def can?(_, :update), do: true
  def can?(_, :destroy), do: true
  def can?(_, :sort), do: true
  def can?(_, :filter), do: true
  def can?(_, :limit), do: true
  def can?(_, :offset), do: true
  def can?(_, :boolean_filter), do: true
  def can?(_, :transact), do: true
  def can?(_, :delete_with_query), do: false
  def can?(_, {:filter_expr, _}), do: true
  def can?(_, {:sort, _}), do: true
  def can?(_, _), do: false

  @csv %Ash.Dsl.Section{
    name: :csv,
    examples: [
      """
      csv do
        file "priv/data/tags.csv"
        create? true
        header? true
        separator '-'
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

  # Table of Contents
  #{Ash.Dsl.Extension.doc_index(@sections)}

  #{Ash.Dsl.Extension.doc(@sections)}
  """
  use Extension, sections: @sections

  defmodule Query do
    @moduledoc false
    defstruct [:resource, :sort, :filter, :limit, :offset]
  end

  @impl true
  def run_query(query, resource) do
    case read_file(resource) do
      {:ok, results} ->
        offset_records =
          results
          |> filter_matches(query.filter)
          |> Sort.runtime_sort(query.sort)
          |> Enum.drop(query.offset || 0)

        if query.limit do
          {:ok, Enum.take(offset_records, query.limit)}
        else
          {:ok, offset_records}
        end

      {:error, error} ->
        {:error, error}
    end
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
        create_from_records(records, resource, changeset)

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def update(resource, changeset) do
    resource
    |> do_read_file()
    |> do_update(resource, changeset)
  end

  @impl true
  def destroy(resource, %{data: record}) do
    resource
    |> do_read_file()
    |> do_destroy(resource, record)
  end

  defp cast_stored(resource, keys) do
    Enum.reduce_while(keys, {:ok, resource.__struct__}, fn {key, value}, {:ok, record} ->
      with attribute when not is_nil(attribute) <- Ash.Resource.Info.attribute(resource, key),
           {:value, value} when not is_nil(value) <- {:value, stored_value(value, attribute)},
           {:ok, loaded} <- Ash.Type.cast_stored(attribute.type, value) do
        {:cont, {:ok, struct(record, [{key, loaded}])}}
      else
        {:value, nil} ->
          {:cont, {:ok, struct(record, [{key, nil}])}}

        nil ->
          {:halt, {:error, "#{key} is not an attribute"}}

        :error ->
          {:halt, {:error, "#{key} could not be loaded"}}
      end
    end)
  end

  defp stored_value(value, attribute) do
    if value == "" and Ash.Type.ecto_type(attribute.type) not in [:string, :uuid, :binary_id] do
      nil
    else
      value
    end
  end

  @impl true
  def resource_to_query(resource, _) do
    %Query{resource: resource}
  end

  @impl true
  def transaction(resource, fun) do
    file = file(resource)

    :global.trans({{:csv, file}, System.unique_integer()}, fn ->
      try do
        Process.put({:csv_in_transaction, file(resource)}, true)
        {:res, fun.()}
      catch
        {{:csv_rollback, ^file}, value} ->
          {:error, value}
      end
    end)
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

  def filter_matches(records, nil), do: records

  def filter_matches(records, filter) do
    Enum.filter(records, &Ash.Filter.Runtime.matches?(nil, &1, filter.expression))
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp do_destroy({:ok, results}, resource, record) do
    columns = columns(resource)

    pkey = Ash.Resource.Info.primary_key(resource)

    changeset_pkey = Map.take(record, pkey)

    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, results} ->
      key_vals =
        columns
        |> Enum.zip(result)
        |> Enum.reject(fn {key, _value} ->
          key == :_
        end)

      cast(resource, key_vals, pkey, changeset_pkey, result, results)
    end)
    |> case do
      {:ok, rows} ->
        lines =
          rows
          |> CSV.encode(separator: separator(resource))
          |> Enum.to_list()

        resource
        |> file()
        |> File.write(lines, [:write])
        |> case do
          :ok ->
            :ok

          {:error, error} ->
            {:error, "Error while writing to CSV: #{inspect(error)}"}
        end
    end
  end

  defp do_destroy({:error, error}, _, _), do: {:error, error}

  defp cast(resource, key_vals, pkey, changeset_pkey, result, results) do
    case cast_stored(resource, key_vals) do
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
    columns = columns(resource)

    pkey = Ash.Resource.Info.primary_key(resource)

    changeset_pkey =
      Enum.into(pkey, %{}, fn key ->
        {key, Ash.Changeset.get_attribute(changeset, key)}
      end)

    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, results} ->
      key_vals =
        columns
        |> Enum.zip(result)
        |> Enum.reject(fn {key, _value} ->
          key == :_
        end)

      dump(resource, changeset, results, result, key_vals, pkey, changeset_pkey)
    end)
    |> case do
      {:ok, rows} ->
        lines =
          rows
          |> CSV.encode(separator: separator(resource))
          |> Enum.to_list()

        resource
        |> file()
        |> File.write(lines, [:write])
        |> case do
          :ok ->
            {:ok, struct(changeset.data, changeset.attributes)}

          {:error, error} ->
            {:error, "Error while writing to CSV: #{inspect(error)}"}
        end
    end
  end

  defp dump(resource, changeset, results, result, key_vals, pkey, changeset_pkey) do
    case cast_stored(resource, key_vals) do
      {:ok, casted} ->
        if Map.take(casted, pkey) == changeset_pkey do
          dump_row(resource, changeset, results)
        else
          {:cont, {:ok, [result | results]}}
        end

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp dump_row(resource, changeset, results) do
    Enum.reduce_while(Enum.reverse(columns(resource)), {:ok, []}, fn key, {:ok, row} ->
      value = Ash.Changeset.get_attribute(changeset, key)

      {:cont, {:ok, [to_string(value) | row]}}
    end)
    |> case do
      {:ok, new_row} ->
        {:cont, {:ok, [new_row | results]}}

      {:error, error} ->
        {:halt, {:error, error}}
    end
  end

  defp read_file(resource) do
    columns = columns(resource)

    resource
    |> do_read_file()
    |> case do
      {:ok, results} ->
        do_cast_stored(results, columns, resource)

      {:error, error} ->
        {:error, error}
    end
  end

  defp do_cast_stored(results, columns, resource) do
    results
    |> Enum.reduce_while({:ok, []}, fn result, {:ok, results} ->
      key_vals =
        columns
        |> Enum.zip(result)
        |> Enum.reject(fn {key, _value} ->
          key == :_
        end)

      case cast_stored(resource, key_vals) do
        {:ok, casted} -> {:cont, {:ok, [casted | results]}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp do_read_file(resource) do
    amount_to_drop =
      if header?(resource) do
        1
      else
        0
      end

    resource
    |> file()
    |> File.stream!()
    |> Stream.drop(amount_to_drop)
    |> CSV.decode(separator: separator(resource))
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, result}, {:ok, results} ->
        {:cont, {:ok, [result | results]}}

      {:error, error}, _ ->
        {:halt, {:error, error}}
    end)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp create_from_records(records, resource, changeset, retry? \\ false) do
    pkey = Ash.Resource.Info.primary_key(resource)
    pkey_value = Map.take(changeset.attributes, pkey)

    if Enum.any?(records, fn record -> Map.take(record, pkey) == pkey_value end) do
      {:error, "Record is not unique"}
    else
      row =
        Enum.reduce_while(columns(resource), {:ok, []}, fn key, {:ok, row} ->
          value = Map.get(changeset.attributes, key)

          {:cont, {:ok, [to_string(value) | row]}}
        end)

      case row do
        {:ok, row} ->
          lines =
            [Enum.reverse(row)]
            |> CSV.encode(separator: separator(resource))
            |> Enum.to_list()

          resource
          |> file()
          |> File.write(lines, [:append])
          |> case do
            :ok ->
              {:ok, struct(resource, changeset.attributes)}

            {:error, :enoent} when retry? ->
              {:error, "Error while writing to CSV: #{inspect(:enoent)}"}

            {:error, :enoent} ->
              File.mkdir_p!(Path.dirname(file(resource)))
              create_from_records(records, resource, changeset, true)

            {:error, error} ->
              {:error, "Error while writing to CSV: #{inspect(error)}"}
          end

        {:error, error} ->
          {:error, error}
      end
    end
  end
end
