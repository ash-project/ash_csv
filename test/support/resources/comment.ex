# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshCsv.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshCsv.Test.Domain,
    data_layer: AshCsv.DataLayer

  csv do
    create? true
    columns [:id, :title]
    file "test/data_files/comments.csv"
  end

  actions do
    default_accept(:*)
    defaults([:create, :read, :update, :destroy])

    create :create_touching_posts do
      touches_resources([AshCsv.Test.Post])
    end

    create :create_with_post do
      change(
        after_action(fn _changeset, comment, _context ->
          AshCsv.Test.Post
          |> Ash.Changeset.for_create(:create, %{title: comment.title})
          |> Ash.create()
          |> case do
            {:ok, _} -> {:ok, comment}
            {:error, error} -> {:error, error}
          end
        end)
      )
    end
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
  end

  relationships do
    belongs_to(:post, AshCsv.Test.Post, public?: true)
  end
end
