defmodule AshCsv.Test.Api do
  @moduledoc false
  use Ash.Api

  resources do
    resource(AshCsv.Test.Post)
    resource(AshCsv.Test.Comment)
  end
end
