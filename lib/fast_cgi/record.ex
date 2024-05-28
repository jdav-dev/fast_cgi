defmodule FastCGI.Record do
  import Bitwise

  alias FastCGI.Record.BeginRequestBody
  alias FastCGI.Record.Encoder
  alias FastCGI.Record.NameValuePair
  alias FastCGI.Record.EndRequestBody
  alias FastCGI.Record.UnknownTypeBody

  @enforce_keys [:type]
  defstruct type: nil,
            request_id: nil,
            content: nil

  @type t ::
          begin_request()
          | abort_request()
          | end_request()
          | params()
          | stdin()
          | stdout()
          | stderr()
          | data()
          | get_values()
          | get_values_result()
          | unknown_type()

  @type begin_request :: %__MODULE__{
          type: :begin_request,
          request_id: request_id(),
          content: BeginRequestBody.t()
        }

  @type abort_request :: %__MODULE__{
          type: :abort_request,
          request_id: request_id(),
          content: nil
        }

  @type end_request :: %__MODULE__{
          type: :end_request,
          request_id: request_id(),
          content: EndRequestBody.t()
        }

  @type params :: %__MODULE__{
          type: :params,
          request_id: request_id(),
          content: [NameValuePair.t()]
        }

  @type stdin :: %__MODULE__{
          type: :stdin,
          request_id: request_id(),
          content: binary() | nil
        }

  @type stdout :: %__MODULE__{
          type: :stdout,
          request_id: request_id(),
          content: binary() | nil
        }

  @type stderr :: %__MODULE__{
          type: :stderr,
          request_id: request_id(),
          content: binary() | nil
        }

  @type data :: %__MODULE__{
          type: :data,
          request_id: request_id(),
          content: binary() | nil
        }

  @type get_values :: %__MODULE__{
          type: :get_values,
          request_id: nil,
          content: [NameValuePair.name_only()]
        }

  @type get_values_result :: %__MODULE__{
          type: :get_values_result,
          request_id: nil,
          content: [NameValuePair.t()]
        }

  @type unknown_type :: %__MODULE__{
          type: :unknown_type,
          request_id: nil,
          content: UnknownTypeBody.t()
        }

  @type request_id :: 1..65535

  @version 1

  @doc false
  def receive_record(socket, timeout) do
    with {:ok, <<@version, type, request_id::16, content_length::16, padding_length, _reserved>>} <-
           :gen_tcp.recv(socket, 8, timeout),
         type <- cast_type(type),
         {:ok, content} <- maybe_receive(socket, content_length, timeout),
         {:ok, _padding} <- maybe_receive(socket, padding_length, timeout) do
      {:ok,
       %__MODULE__{
         type: type,
         request_id: cast_request_id(request_id),
         content: cast_content(type, content)
       }}
    end
  end

  defp cast_type(1), do: :begin_request
  defp cast_type(2), do: :abort_request
  defp cast_type(3), do: :end_request
  defp cast_type(4), do: :params
  defp cast_type(5), do: :stdin
  defp cast_type(6), do: :stdout
  defp cast_type(7), do: :stderr
  defp cast_type(8), do: :data
  defp cast_type(9), do: :get_values
  defp cast_type(10), do: :get_values_result
  defp cast_type(11), do: :unknown_type

  defp maybe_receive(_socket, 0, _timeout), do: {:ok, nil}
  defp maybe_receive(socket, length, timeout), do: :gen_tcp.recv(socket, length, timeout)

  defp cast_request_id(0), do: nil
  defp cast_request_id(request_id), do: request_id

  defp cast_content(:begin_request, content) do
    BeginRequestBody.cast(content)
  end

  defp cast_content(:end_request, content) do
    EndRequestBody.cast(content)
  end

  defp cast_content(type, content) when type in [:params, :get_values, :get_values_result] do
    NameValuePair.cast(content)
  end

  defp cast_content(:unknown_type, content) do
    UnknownTypeBody.cast(content)
  end

  defp cast_content(_type, content), do: content

  defimpl FastCGI.Record.Encoder do
    alias FastCGI.Record

    @version 1
    @max_content_length 65535
    @reserved <<0>>

    defguardp is_content(content)
              when is_struct(content, BeginRequestBody) or is_list(content) or
                     is_struct(content, EndRequestBody) or is_struct(content, UnknownTypeBody) or
                     (is_binary(content) and byte_size(content) <= @max_content_length) or
                     is_nil(content)

    def to_iodata(%Record{
          type: type,
          request_id: request_id,
          content: content
        })
        when type in [
               :begin_request,
               :abort_request,
               :end_request,
               :params,
               :stdin,
               :stdout,
               :stderr,
               :data,
               :get_values,
               :get_values_result,
               :unknown_type
             ] and (request_id in 1..65535 or is_nil(request_id)) and is_content(content) do
      content_iodata = Encoder.to_iodata(content)
      content_length = IO.iodata_length(content_iodata)
      padding_length = -content_length &&& 7
      padding = <<0::size(8 * padding_length)>>

      [
        <<@version, type_to_integer(type), request_id_to_integer(request_id)::16,
          content_length::16, padding_length, @reserved::binary>>,
        content_iodata,
        padding
      ]
    end

    defp request_id_to_integer(nil), do: 0
    defp request_id_to_integer(request_id), do: request_id

    defp type_to_integer(:begin_request), do: 1
    defp type_to_integer(:abort_request), do: 2
    defp type_to_integer(:end_request), do: 3
    defp type_to_integer(:params), do: 4
    defp type_to_integer(:stdin), do: 5
    defp type_to_integer(:stdout), do: 6
    defp type_to_integer(:stderr), do: 7
    defp type_to_integer(:data), do: 8
    defp type_to_integer(:get_values), do: 9
    defp type_to_integer(:get_values_result), do: 10
    defp type_to_integer(:unknown_type), do: 11
  end
end
