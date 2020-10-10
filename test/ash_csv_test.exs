defmodule AshCsvTest do
  use ExUnit.Case, async: false
  alias AshCsv.Test.{Api, Post}
  require Ash.Query

  setup do
    on_exit(fn ->
      File.rm_rf!("test/data_files")
    end)
  end

  test "resources can be created" do
    Post
    |> Ash.Changeset.new(%{title: "title"})
    |> Api.create!()

    assert [%{title: "title"}] = Api.read!(Post)
  end

  test "a resource can be updated" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

    post
    |> Ash.Changeset.new(%{title: "new_title"})
    |> Api.update!()

    assert [%{title: "new_title"}] = Api.read!(Post)
  end

  test "a resource can be deleted" do
    post =
      Post
      |> Ash.Changeset.new(%{title: "title"})
      |> Api.create!()

    Api.destroy!(post)

    assert [] = Api.read!(Post)
  end

  test "filters/sorts can be applied" do
    Post
    |> Ash.Changeset.new(%{title: "title1"})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "title2"})
    |> Api.create!()

    Post
    |> Ash.Changeset.new(%{title: "title3"})
    |> Api.create!()

    results =
      Post
      |> Ash.Query.filter(title in ["title1", "title2"])
      |> Ash.Query.sort(:title)
      |> Api.read!()

    assert [%{title: "title1"}, %{title: "title2"}] = results
  end
end
