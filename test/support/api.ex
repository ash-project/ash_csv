# SPDX-FileCopyrightText: 2020 ash_csv contributors <https://github.com/ash-project/ash_csv/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshCsv.Test.Domain do
  @moduledoc false
  use Ash.Domain

  resources do
    resource(AshCsv.Test.Post)
    resource(AshCsv.Test.Comment)
  end
end
