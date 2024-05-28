defmodule FastCGI.Record.UnknownTypeBody do
  @behaviour FastCGI.Record.Decoder

  @enforce_keys [:type]
  defstruct [:type, reserved: <<0, 0, 0, 0, 0, 0, 0>>]

  @type t :: %__MODULE__{
          type: 0..255
        }

  @impl FastCGI.Record.Decoder
  @doc false
  def cast(<<type, _reserved::binary-size(7)>>) do
    %__MODULE__{type: type}
  end

  defimpl FastCGI.Record.Encoder do
    alias FastCGI.Record.UnknownTypeBody

    @reserved <<0, 0, 0, 0, 0, 0, 0>>

    def to_iodata(%UnknownTypeBody{type: type})
        when type in 0..255 do
      [type, @reserved]
    end
  end
end
