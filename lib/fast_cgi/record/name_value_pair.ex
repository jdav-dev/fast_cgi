defmodule FastCGI.Record.NameValuePair do
  @behaviour FastCGI.Record.Decoder

  @enforce_keys [:name]
  defstruct [:name, :value]

  @type t :: %__MODULE__{
          name: binary(),
          value: binary() | nil
        }

  @type name_only :: %__MODULE__{
          name: binary(),
          value: nil
        }

  @impl FastCGI.Record.Decoder
  @doc false
  def cast(binary) when is_binary(binary), do: cast_binary(binary, [])
  def cast(nil), do: []

  defp cast_binary("", acc) do
    Enum.reverse(acc)
  end

  defp cast_binary(binary, acc) when is_binary(binary) do
    {name_length, binary} =
      case binary do
        <<0::1, name_length::7, rest::binary>> -> {name_length, rest}
        <<1::1, name_length::31, rest::binary>> -> {name_length, rest}
      end

    {value_length, binary} =
      case binary do
        <<0::1, value_length::7, rest::binary>> -> {value_length, rest}
        <<1::1, value_length::31, rest::binary>> -> {value_length, rest}
      end

    <<name::binary-size(name_length), value::binary-size(value_length), rest::binary>> = binary
    value = if value_length == 0, do: nil, else: value

    cast_binary(rest, [%__MODULE__{name: name, value: value} | acc])
  end

  defimpl FastCGI.Record.Encoder do
    alias FastCGI.Record.NameValuePair

    @max_binary_size 2_147_483_647

    def to_iodata(%NameValuePair{name: name, value: value})
        when is_binary(name) and byte_size(name) <= @max_binary_size and
               ((is_binary(value) and byte_size(value) <= @max_binary_size) or is_nil(value)) do
      name_length = byte_size(name)
      value = value || ""
      value_length = byte_size(value)

      name_length_binary =
        case name_length do
          name_length when name_length <= 127 -> <<0::1, name_length::7>>
          name_length when name_length > 127 -> <<1::1, name_length::31>>
        end

      value_length_binary =
        case value_length do
          value_length when value_length <= 127 -> <<0::1, value_length::7>>
          value_length when value_length > 127 -> <<1::1, value_length::31>>
        end

      [name_length_binary, value_length_binary, name, value]
    end
  end
end
