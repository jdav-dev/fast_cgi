defmodule FastCGI.Record.BeginRequestBody do
  @behaviour FastCGI.Record.Decoder

  @enforce_keys [:role]
  defstruct [:role, keep_conn: true]

  @type t :: %__MODULE__{
          role: :responder | :authorizer | :filter,
          keep_conn: boolean()
        }

  @impl FastCGI.Record.Decoder
  @doc false
  def cast(<<role::16, keep_conn, _reserved::binary-size(5)>>) do
    %__MODULE__{role: cast_role(role), keep_conn: cast_keep_conn(keep_conn)}
  end

  defp cast_role(1), do: :responder
  defp cast_role(2), do: :authorizer
  defp cast_role(3), do: :filter

  defp cast_keep_conn(0), do: false
  defp cast_keep_conn(_), do: true

  defimpl FastCGI.Record.Encoder do
    alias FastCGI.Record.BeginRequestBody

    @reserved <<0, 0, 0, 0, 0>>

    def to_iodata(%BeginRequestBody{role: role, keep_conn: keep_conn})
        when role in [:responder, :authorizer, :filter] and is_boolean(keep_conn) do
      <<role_to_integer(role)::16, keep_conn_to_integer(keep_conn), @reserved::binary>>
    end

    defp role_to_integer(:responder), do: 1
    defp role_to_integer(:authorizer), do: 2
    defp role_to_integer(:filter), do: 3

    defp keep_conn_to_integer(false), do: 0
    defp keep_conn_to_integer(true), do: 1
  end
end
