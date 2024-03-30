defmodule AshCsvTest do
  use ExUnit.Case, async: false
  alias AshCsv.Test.Post
  require Ash.Query

  setup do
    on_exit(fn ->
      File.rm_rf!("test/data_files")
    end)
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

  test "a resource can be deleted" do
    post =
      Post
      |> Ash.Changeset.for_create(:create, %{title: "title"})
      |> Ash.create!()

    Ash.destroy!(post)

    assert [] = Ash.read!(Post)
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
end
