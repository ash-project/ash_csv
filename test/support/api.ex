defmodule AshCsv.Test.Api do
  @moduledoc false
  use Ash.Api

  resources do
    registry(AshCsv.Test.Registry)
  end
end
