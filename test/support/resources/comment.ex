defmodule AshCsv.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshCsv.DataLayer

  csv do
    create? true
    columns [:id, :title]
    file "test/data_files/comments.csv"
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string)
  end

  relationships do
    belongs_to(:post, AshCsv.Test.Post)
  end
end
