defmodule FastCGI.Record.EndRequestBody do
  @behaviour FastCGI.Record.Decoder

  @enforce_keys [:app_status, :protocol_status]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          app_status: 0..4_294_967_295,
          protocol_status:
            :request_complete | :cannot_multiplex_connection | :overloaded | :unknown_role
        }

  @impl FastCGI.Record.Decoder
  @doc false
  def cast(<<app_status::32, protocol_status, _reserved::binary-size(3)>>) do
    %__MODULE__{
      app_status: app_status,
      protocol_status: cast_protocol_status(protocol_status)
    }
  end

  defp cast_protocol_status(0), do: :request_complete
  defp cast_protocol_status(1), do: :cannot_multiplex_connection
  defp cast_protocol_status(2), do: :overloaded
  defp cast_protocol_status(3), do: :unknown_role

  defimpl FastCGI.Record.Encoder do
    alias FastCGI.Record.EndRequestBody

    @reserved <<0, 0, 0>>

    def to_iodata(%EndRequestBody{
          app_status: app_status,
          protocol_status: protocol_status
        })
        when app_status in 0..4_294_967_295 and
               protocol_status in [
                 :request_complete,
                 :cannot_multiplex_connection,
                 :overloaded,
                 :unknown_role
               ] do
      <<app_status::32, protocol_status_to_integer(protocol_status), @reserved::binary>>
    end

    defp protocol_status_to_integer(:request_complete), do: 0
    defp protocol_status_to_integer(:cannot_multiplex_connection), do: 1
    defp protocol_status_to_integer(:overloaded), do: 2
    defp protocol_status_to_integer(:unknown_role), do: 3
  end
end
