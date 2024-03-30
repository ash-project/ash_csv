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
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
  end

  relationships do
    belongs_to(:post, AshCsv.Test.Post, public?: true)
  end
end
