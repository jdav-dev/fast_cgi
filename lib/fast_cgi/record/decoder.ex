defmodule FastCGI.Record.Decoder do
  @moduledoc false

  @callback cast(binary()) :: struct() | [struct()]
end
