if Code.ensure_loaded?(Plug) do
  defmodule FastCGI.Plug do
    @moduledoc """
    Documentation for `FastCGI.Plug`.
    """

    @behaviour Plug

    import Plug.Conn

    alias FastCGI.Record
    alias FastCGI.Record.BeginRequestBody
    alias FastCGI.Record.NameValuePair

    require Logger

    @server_software "#{inspect(__MODULE__)}/#{Mix.Project.config()[:version]}"

    @impl Plug
    def init(opts) do
      chunk_size = Keyword.get(opts, :chunk_size, 8_000_000)
      script = Keyword.fetch!(opts, :script)

      script_dir =
        Keyword.get_lazy(opts, :script_dir, fn ->
          Application.fetch_env(:fast_cgi, :script_dir)
        end)

      socket_pool_impl =
        Keyword.get_lazy(opts, :socket_pool, fn ->
          Application.fetch_env!(:fast_cgi, :socket_pool)
        end)

      %{
        chunk_size: chunk_size,
        script: script,
        script_dir: script_dir,
        socket_pool_impl: socket_pool_impl
      }
    end

    @impl Plug
    def call(conn, opts) do
      %{
        chunk_size: chunk_size,
        script: script_name,
        script_dir: script_dir,
        socket_pool_impl: socket_pool_impl
      } = opts

      socket_pool_impl.checkout!(fn socket ->
        with {:ok, request_id} <- begin_cgi_request(socket),
             :ok <- send_params(socket, conn, request_id, script_dir, script_name),
             {:ok, conn} <- send_body(socket, conn, request_id, chunk_size),
             {:ok, conn} <- receive_headers(socket, conn),
             {:ok, conn} <- receive_body(socket, conn) do
          conn
        else
          {:error, reason} -> raise FastCGI.SocketError, reason: reason
        end
      end)
    end

    defp begin_cgi_request(socket) do
      request_id = FastCGI.new_request_id()
      Logger.metadata(fast_cgi_request_id: request_id)
      Logger.info("Begin FastCGI request\n  Request ID: #{request_id}")

      with :ok <-
             FastCGI.send(socket, %Record{
               type: :begin_request,
               request_id: request_id,
               content: %BeginRequestBody{role: :responder}
             }) do
        {:ok, request_id}
      end
    end

    defp send_params(socket, conn, request_id, script_dir, script_name) do
      params = build_params(conn, script_dir, script_name)
      name_value_pairs = for {name, value} <- params, do: %NameValuePair{name: name, value: value}

      FastCGI.send(socket, [
        %Record{type: :params, request_id: request_id, content: name_value_pairs},
        %Record{type: :params, request_id: request_id}
      ])
    end

    defp build_params(conn, script_dir, script_name) do
      peer_ip = conn.remote_ip |> :inet.ntoa() |> to_string()

      %{
        "GATEWAY_INTERFACE" => "CGI/1.1",
        "QUERY_STRING" => conn.query_string,
        "REMOTE_ADDR" => peer_ip,
        "REMOTE_HOST" => peer_ip,
        "REQUEST_METHOD" => conn.method,
        "SCRIPT_NAME" => script_name,
        "SERVER_NAME" => conn.host,
        "SERVER_PORT" => to_string(conn.port),
        "SERVER_PROTOCOL" => conn |> get_http_protocol() |> to_string(),
        "SERVER_SOFTWARE" => @server_software,
        # PHP
        "SCRIPT_FILENAME" => Path.join(script_dir, script_name),
        "REQUEST_URI" => conn.request_path
      }
      |> put_auth_type(conn)
      |> put_content_length(conn)
      |> put_content_type(conn)
      |> put_path_info(conn)
      |> put_path_translated(script_dir)
      |> put_remote_user(conn)
      |> put_http_headers(conn)
    end

    defp put_auth_type(params, conn) do
      case get_req_header(conn, "authorization") do
        ["Basic " <> _credentials] -> Map.put(params, "AUTH_TYPE", "Basic")
        ["Digest " <> _credentials] -> Map.put(params, "AUTH_TYPE", "Digest")
        _authorization -> params
      end
    end

    defp put_content_length(params, conn) do
      case get_req_header(conn, "content-length") do
        [content_length] -> Map.put(params, "CONTENT_LENGTH", content_length)
        _content_length -> params
      end
    end

    defp put_content_type(params, conn) do
      case get_req_header(conn, "content-type") do
        [content_type] -> Map.put(params, "CONTENT_TYPE", content_type)
        _content_type -> params
      end
    end

    defp put_path_info(params, conn) do
      case conn.path_info do
        [] ->
          params

        path_info ->
          decoded_path_info = ["/" | path_info] |> Path.join() |> URI.decode()
          Map.put(params, "PATH_INFO", decoded_path_info)
      end
    end

    defp put_path_translated(params, script_dir) do
      case Map.fetch(params, "PATH_INFO") do
        {:ok, path_info} ->
          Map.put(params, "PATH_TRANSLATED", Path.join(script_dir, path_info))

        :error ->
          params
      end
    end

    defp put_remote_user(params, conn) do
      case conn.assigns[:remote_user] do
        remote_user when is_binary(remote_user) -> Map.put(params, "REMOTE_USER", remote_user)
        _remote_user -> params
      end
    end

    @skip_headers ["authorization", "content-length", "content-type"]

    defp put_http_headers(params, conn) do
      for {header, value} <- conn.req_headers, header not in @skip_headers, reduce: params do
        acc ->
          key = "HTTP_#{header |> String.upcase() |> String.replace("-", "_")}"
          Map.update(acc, key, value, &Enum.join([&1, value], ", "))
      end
    end

    defp send_body(socket, conn, request_id, length) do
      case read_body(conn, length: length) do
        {:ok, body, conn} ->
          records = [
            %Record{type: :stdin, request_id: request_id, content: body},
            %Record{type: :stdin, request_id: request_id}
          ]

          with :ok <- FastCGI.send(socket, records) do
            {:ok, conn}
          end

        {:more, partial_body, conn} ->
          record = %Record{type: :stdin, request_id: request_id, content: partial_body}

          with :ok <- FastCGI.send(socket, record) do
            send_body(socket, conn, request_id, length)
          end
      end
    end

    defp receive_headers(socket, conn) do
      with {:ok, %Record{content: content}} <- receive_stdout(socket, conn) do
        case String.split(content, "\r\n\r\n", parts: 2) do
          [headers, partial_body] ->
            conn = reduce_headers(headers, conn) |> Map.update!(:resp_headers, &Enum.reverse/1)
            conn = send_chunked(conn, conn.status || 200)
            chunk(conn, partial_body)

          [headers] ->
            conn = reduce_headers(headers, conn)
            receive_headers(socket, conn)
        end
      end
    end

    defp receive_stdout(socket, conn) do
      case FastCGI.receive_record(socket) do
        {:ok, %Record{type: :stdout} = record} ->
          {:ok, record}

        {:ok, %Record{type: :stderr, content: content}} ->
          Logger.error(content)
          receive_stdout(socket, conn)

        {:ok, %Record{type: :end_request, request_id: request_id, content: content}} ->
          Logger.info([
            "End FastCGI request\n  Request ID: ",
            to_string(request_id),
            "\n  Application status: ",
            inspect(content.app_status),
            "\n  Protocol status: ",
            to_string(content.protocol_status)
          ])

          {:ok, conn}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp reduce_headers(headers, conn) do
      headers
      |> String.split("\r\n")
      |> Enum.reduce(conn, fn header, conn ->
        case String.split(header, ":", parts: 2) do
          ["Status", status] ->
            {status, _reason_phrase} = status |> String.trim() |> Integer.parse()
            put_status(conn, status)

          [key, value] ->
            prepend_resp_headers(conn, [{String.downcase(key), String.trim(value)}])

          [""] ->
            conn

          [key] ->
            prepend_resp_headers(conn, [{String.downcase(key), ""}])
        end
      end)
    end

    defp receive_body(socket, conn) do
      with {:ok, %Record{content: content}} <- receive_stdout(socket, conn),
           {:ok, conn} <- chunk(conn, content) do
        receive_body(socket, conn)
      end
    end
  end
end
