defmodule AshCsv.Test.Registry do
  @moduledoc false
  use Ash.Registry

  entries do
    entry(AshCsv.Test.Post)
    entry(AshCsv.Test.Comment)
  end
end
