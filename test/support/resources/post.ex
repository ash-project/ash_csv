defmodule AshCsv.Test.Post do
  @moduledoc false
  use Ash.Resource,
    data_layer: AshCsv.DataLayer

  csv do
    create? true
    columns [:id, :title, :score, :public]
    file "test/data_files/posts.csv"
  end

  actions do
    defaults([:create, :read, :update, :destroy])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string)
    attribute(:score, :integer)
    attribute(:public, :boolean)
  end

  relationships do
    has_many(:comments, AshCsv.Test.Comment, destination_field: :post_id)
  end
end
