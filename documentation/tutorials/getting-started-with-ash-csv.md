# Getting Started with CSV

AshCsv offers basic support for storing and reading resources from csv files.

## Installation

Add `ash_csv` to your list of dependencies in `mix.exs`:

```elixir
{:ash_csv, "~> 0.9.7"}
```

## Usage

```
defmodule MyApp.MyResource do
  use Ash.Resource,
    domain: MyApp,
    data_layer: AshCsv.DataLayer

  csv do
    ... # see configuration options below
  end
end
```

For information on how to configure ash_csv, see the [DSL documentation.](/documentation/dsls/DSL:-AshCsv.DataLayer.md)
