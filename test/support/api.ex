defmodule AshCsv.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshCsv.Test.Post)
    resource(AshCsv.Test.Comment)
  end
end
