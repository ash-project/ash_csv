# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshCsvTest do
  use ExUnit.Case, async: false
  alias AshCsv.Test.Post
  import Spark.Test
  require Ash.Query

  setup do
    on_exit(fn ->
      File.rm_rf!("test/data_files")
    end)
  end

  test "an identity must be checked with `pre_check_with`" do
    error =
      assert_dsl_error %Spark.Error.DslError{} do
        defmodule Elixir.AshCsvTest.UncheckedIdentity do
          @moduledoc false
          use Ash.Resource, data_layer: AshCsv.DataLayer

          csv do
            columns [:id, :email]
            file "test/data_files/unchecked_identity.csv"
          end

          actions do
            defaults([:read])
          end

          attributes do
            uuid_primary_key(:id)
            attribute(:email, :string, public?: true)
          end

          identities do
            identity(:unique_email, [:email])
          end
        end
      end

    assert error.message =~ "Must specify the `pre_check_with` option."
  end

  test "an identity checked with `pre_check_with` is accepted" do
    refute_dsl_errors do
      defmodule Elixir.AshCsvTest.CheckedIdentity do
        @moduledoc false
        use Ash.Resource, data_layer: AshCsv.DataLayer

        csv do
          columns [:id, :email]
          file "test/data_files/checked_identity.csv"
        end

        actions do
          defaults([:read])
        end

        attributes do
          uuid_primary_key(:id)
          attribute(:email, :string, public?: true)
        end

        identities do
          identity(:unique_email, [:email], pre_check_with: AshCsv.Test.Domain)
        end
      end
    end
  end

  test "resources can be created" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    assert [%{title: "title"}] = Ash.read!(Post)
  end

  test "resources can be upserted" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title", unique: "foo"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "new_title", unique: "foo"})
    |> Ash.create!(upsert?: true, upsert_identity: :unique_unique)

    assert [%{title: "new_title"}] = Ash.read!(Post)
  end

  test "a resource can be updated" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    post
    |> Ash.Changeset.for_update(:update, %{title: "new_title"})
    |> Ash.update!()

    assert [%{title: "new_title"}] = Ash.read!(Post)
  end

  test "in_transaction? is cleared after a write completes" do
    refute AshCsv.DataLayer.in_transaction?(Post)

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title"})
    |> Ash.create!()

    # The transaction flag used to be set but never cleared, so it stayed
    # true for the rest of the process and later writes silently skipped the
    # :global write lock (lost updates, duplicate primary keys).
    refute AshCsv.DataLayer.in_transaction?(Post)
  end

  test "a resource can be deleted" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    Ash.destroy!(post)

    assert [] = Ash.read!(Post)
  end

  test "updating a record preserves the order of rows in the file" do
    [_first, second, _third] = create_posts(["title1", "title2", "title3"])

    second
    |> Ash.Changeset.for_update(:update, %{title: "updated"})
    |> Ash.update!()

    assert file_titles() == ["title1", "updated", "title3"]
  end

  test "destroying a record preserves the order of rows in the file" do
    [_first, second, _third] = create_posts(["title1", "title2", "title3"])

    Ash.destroy!(second)

    assert file_titles() == ["title1", "title3"]
  end

  test "rewriting the file leaves no temporary files behind" do
    [post] = create_posts(["title"])

    post
    |> Ash.Changeset.for_update(:update, %{title: "new_title"})
    |> Ash.update!()

    Ash.destroy!(post)

    assert File.ls!("test/data_files") == ["posts.csv"]
  end

  test "filters/sorts can be applied" do
    Post
    |> Ash.Changeset.for_create(:create, %{title: "title1"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title2"})
    |> Ash.create!()

    Post
    |> Ash.Changeset.for_create(:create, %{title: "title3"})
    |> Ash.create!()

    results =
      Post
      |> Ash.Query.filter(title in ["title1", "title2"])
      |> Ash.Query.sort(:title)
      |> Ash.read!()

    assert [%{title: "title1"}, %{title: "title2"}] = results
  end

  test "simultaneous creates all succeed" do
    tasks =
      for n <- 1..20 do
        Task.async(fn ->
          receive do
            :go ->
              Post
              |> Ash.Changeset.for_create(:create, %{title: "title#{n}"})
              |> Ash.create()
          end
        end)
      end

    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks)

    assert Enum.all?(results, &match?({:ok, _}, &1))
    assert length(Ash.read!(Post)) == 20
  end

  test "actions that touch each other's files in opposite orders all complete" do
    results =
      for _round <- 1..10 do
        pair_at_once([
          {AshCsv.Test.Post, :create_touching_comments},
          {AshCsv.Test.Comment, :create_touching_posts}
        ])
      end

    assert Enum.all?(List.flatten(results), &match?({:ok, _}, &1))
  end

  test "actions that write each other's files from hooks finish" do
    results =
      for _round <- 1..10 do
        pair_at_once([
          {AshCsv.Test.Post, :create_with_comment},
          {AshCsv.Test.Comment, :create_with_post}
        ])
      end

    refute Enum.member?(List.flatten(results), :still_waiting)
  end

  # Runs one create on each resource at the same moment, giving each three seconds.
  defp pair_at_once(actions) do
    tasks =
      for {resource, action} <- actions do
        Task.async(fn ->
          receive do
            :go ->
              resource
              |> Ash.Changeset.for_create(action, %{title: "title"})
              |> Ash.create()
          end
        end)
      end

    Enum.each(tasks, &send(&1.pid, :go))

    tasks
    |> Task.yield_many(3_000)
    |> Enum.map(fn
      {_task, {:ok, result}} ->
        result

      {task, nil} ->
        Task.shutdown(task, :brutal_kill)
        :still_waiting
    end)
  end

  defp create_posts(titles) do
    Enum.map(titles, fn title ->
      Post
      |> Ash.Changeset.for_create(:create, %{title: title})
      |> Ash.create!()
    end)
  end

  # Reads the raw file (not through Ash) so we assert on the on-disk row order.
  # `Post` is configured without a header row.
  defp file_titles do
    "test/data_files/posts.csv"
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> line |> String.split(",") |> Enum.at(1) end)
  end
end
