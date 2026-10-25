# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshCsv.Test.Post do
  @moduledoc false
  use Ash.Resource,
    domain: AshCsv.Test.Domain,
    data_layer: AshCsv.DataLayer

  csv do
    create? true
    columns [:id, :title, :score, :public, :unique]
    file "test/data_files/posts.csv"
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])

    create :create_touching_comments do
      touches_resources([AshCsv.Test.Comment])
    end

    create :create_with_comment do
      change(
        after_action(fn _changeset, post, _context ->
          AshCsv.Test.Comment
          |> Ash.Changeset.for_create(:create, %{title: post.title})
          |> Ash.create()
          |> case do
            {:ok, _} -> {:ok, post}
            {:error, error} -> {:error, error}
          end
        end)
      )
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
    attribute(:score, :integer, public?: true)
    attribute(:public, :boolean, public?: true)
    attribute(:unique, :string, public?: true)
  end

  identities do
    identity(:unique_unique, [:unique])
  end

  relationships do
    has_many(:comments, AshCsv.Test.Comment, destination_attribute: :post_id, public?: true)
  end
end
