defmodule FastCGI.PlugTest do
  use FastCGI.SocketCase, async: true
  use Plug.Test

  import ExUnit.CaptureLog

  alias FastCGI.Record
  alias FastCGI.Record.BeginRequestBody
  alias FastCGI.Record.EndRequestBody

  doctest FastCGI.Plug

  defmodule Router do
    use Plug.Router

    @script_dir Path.expand("../support/php", __DIR__)

    plug :match
    plug :dispatch

    forward "/test",
      to: FastCGI.Plug,
      init_opts: [
        script: "some_script",
        script_dir: @script_dir,
        socket_pool: FastCGI.ProcessDictSocket
      ]

    forward "/chunked",
      to: FastCGI.Plug,
      init_opts: [
        chunk_size: 8,
        script: "some_script",
        script_dir: @script_dir,
        socket_pool: FastCGI.ProcessDictSocket
      ]

    forward "/test.php",
      to: FastCGI.Plug,
      init_opts: [script: "test.php", script_dir: @script_dir, socket_pool: FastCGI.TempPhpSocket]
  end

  @opts Router.init([])

  test "sends a begin request", %{remote_socket: remote_socket} do
    conn = conn(:get, "/test")

    Task.start_link(fn ->
      assert {:ok,
              %Record{
                type: :begin_request,
                request_id: request_id,
                content: %BeginRequestBody{role: :responder, keep_conn: true}
              }} = FastCGI.receive_record(remote_socket)

      assert is_integer(request_id)
      assert request_id > 0

      send_empty_response(remote_socket, request_id)
    end)

    info_log =
      capture_log([level: :info], fn ->
        Router.call(conn, @opts)
      end)

    assert info_log =~ "Begin FastCGI request\n  Request ID: "
  end

  test "sends base params from the conn", %{remote_socket: remote_socket} do
    conn = conn(:get, "/test/with/additional/path", name: "World")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: ^request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: ^request_id, content: []}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      assert params["GATEWAY_INTERFACE"] == "CGI/1.1"
      assert params["QUERY_STRING"] == "name=World"
      assert params["REMOTE_ADDR"] == "127.0.0.1"
      assert params["REMOTE_HOST"] == "127.0.0.1"
      assert params["REQUEST_METHOD"] == "GET"
      assert params["SCRIPT_NAME"] == "some_script"
      assert params["SERVER_NAME"] == "www.example.com"
      assert params["SERVER_PORT"] == "80"
      assert params["SERVER_PROTOCOL"] == "HTTP/1.1"
      assert params["SERVER_SOFTWARE"] == "FastCGI.Plug/0.1.0"
      assert params["SCRIPT_FILENAME"] =~ "/fast_cgi/test/support/php/some_script"
      assert params["REQUEST_URI"] == "/test/with/additional/path"

      refute params["AUTH_TYPE"]
      refute params["CONTENT_LENGTH"]
      refute params["CONTENT_TYPE"]
      assert params["PATH_INFO"] == "/with/additional/path"
      assert params["PATH_TRANSLATED"] =~ "/fast_cgi/test/support/php/with/additional/path"
      refute params["REMOTE_USER"]

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "sets the basic auth type in params", %{remote_socket: remote_socket} do
    conn =
      conn(:get, "/test")
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("testuser", "testpass"))

    Task.start_link(fn ->
      {:ok, _begin_request} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      assert params["AUTH_TYPE"] == "Basic"

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "sets the digest auth type in params", %{remote_socket: remote_socket} do
    conn =
      conn(:get, "/test")
      |> put_req_header("authorization", "Digest some_digest")

    Task.start_link(fn ->
      {:ok, _begin_request} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      assert params["AUTH_TYPE"] == "Digest"

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "passes through content length from headers", %{remote_socket: remote_socket} do
    conn =
      conn(:post, "/test")
      |> put_req_header("content-length", "123")

    Task.start_link(fn ->
      {:ok, _begin_request} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      assert params["REQUEST_METHOD"] == "POST"
      assert params["CONTENT_LENGTH"] == "123"

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "passes through content type from headers", %{remote_socket: remote_socket} do
    conn =
      conn(:post, "/test")
      |> put_req_header("content-type", "application/json")

    Task.start_link(fn ->
      {:ok, _begin_request} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      assert params["REQUEST_METHOD"] == "POST"
      assert params["CONTENT_TYPE"] == "application/json"

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "passes through remote_user from assigns", %{remote_socket: remote_socket} do
    conn =
      conn(:get, "/test")
      |> assign(:remote_user, "some user_id")

    Task.start_link(fn ->
      {:ok, _begin_request} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      assert params["REMOTE_USER"] == "some user_id"

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "passes HTTP headers through params", %{remote_socket: remote_socket} do
    conn =
      conn(:post, "/test")
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("testuser", "testpass"))
      |> put_req_header("content-length", "123")
      |> put_req_header("content-type", "application/json")
      |> prepend_req_headers([{"x-test-repeated", "1"}, {"x-test-repeated", "2"}])
      |> put_req_header("x-test-no-value", "")
      |> put_req_header("x-test-multiple-colons", "value:with:colons")

    Task.start_link(fn ->
      {:ok, _begin_request} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :params, request_id: request_id, content: name_value_pairs}} =
               FastCGI.receive_record(remote_socket)

      params = Map.new(name_value_pairs, &{&1.name, &1.value})

      refute params["HTTP_AUTHORIZATION"]
      refute params["HTTP_CONTENT_LENGTH"]
      refute params["HTTP_CONTENT_TYPE"]
      assert params["HTTP_X_TEST_REPEATED"] == "1, 2"
      assert {:ok, nil} = Map.fetch(params, "HTTP_X_TEST_NO_VALUE")
      assert params["HTTP_X_TEST_MULTIPLE_COLONS"] == "value:with:colons"

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "sends no stdin content if there is no request body", %{remote_socket: remote_socket} do
    conn = conn(:post, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      {:ok, _params} = FastCGI.receive_record(remote_socket)
      {:ok, _params} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: nil}} =
               FastCGI.receive_record(remote_socket)

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "sends all chunks from the request body", %{remote_socket: remote_socket} do
    request_body = ~s/{"key1":"value1","key2":"value2"}/

    conn =
      conn(:post, "/chunked", request_body)
      |> put_req_header("content-type", "application/json")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      {:ok, _params} = FastCGI.receive_record(remote_socket)
      {:ok, _params} = FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: ~s/{"key1":/}} =
               FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: ~s/"value1"/}} =
               FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: ~s/,"key2":/}} =
               FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: ~s/"value2"/}} =
               FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: ~s/}/}} =
               FastCGI.receive_record(remote_socket)

      assert {:ok, %Record{type: :stdin, request_id: ^request_id, content: nil}} =
               FastCGI.receive_record(remote_socket)

      send_empty_response(remote_socket, request_id)
    end)

    Router.call(conn, @opts)
  end

  test "returns empty response from the application", %{remote_socket: remote_socket} do
    conn = conn(:post, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      send_empty_response(remote_socket, request_id)
    end)

    conn = Router.call(conn, @opts)

    assert conn.status == 200
    assert [{"cache-control", _value}] = conn.resp_headers
    assert conn.resp_body == ""
  end

  test "sets status from the application", %{remote_socket: remote_socket} do
    conn = conn(:post, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(remote_socket, [
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "Status: 418 I'm a teapot\r\n\r\n"
          },
          %Record{
            type: :end_request,
            request_id: request_id,
            content: %EndRequestBody{app_status: 0, protocol_status: :request_complete}
          }
        ])
    end)

    conn = Router.call(conn, @opts)

    assert conn.status == 418
    assert get_resp_header(conn, "status") == []
  end

  test "sets headers from the application", %{remote_socket: remote_socket} do
    conn = conn(:post, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(remote_socket, [
          %Record{
            type: :stdout,
            request_id: request_id,
            content:
              "Content-Type: application/json; charset=UTF-8\r\nX-Test-Repeated: 1\r\n" <>
                "X-Test-Repeated: 2\r\nX-Test-No-Colon\r\nX-Test-No-Value:\r\n" <>
                "X-Test-No-Value-Whitespace: \r\nX-Test-Multiple-Colons: value:with:colons\r\n" <>
                "X-Test-No-Whitespace:value\r\n\r\n"
          },
          %Record{
            type: :end_request,
            request_id: request_id,
            content: %EndRequestBody{app_status: 0, protocol_status: :request_complete}
          }
        ])
    end)

    conn = Router.call(conn, @opts)

    assert get_resp_header(conn, "content-type") == ["application/json; charset=UTF-8"]
    assert get_resp_header(conn, "x-test-repeated") == ["1", "2"]
    assert get_resp_header(conn, "x-test-no-colon") == [""]
    assert get_resp_header(conn, "x-test-no-value") == [""]
    assert get_resp_header(conn, "x-test-no-value-whitespace") == [""]
    assert get_resp_header(conn, "x-test-multiple-colons") == ["value:with:colons"]
    assert get_resp_header(conn, "x-test-no-whitespace") == ["value"]
  end

  test "reads all response body chunks", %{remote_socket: remote_socket} do
    conn = conn(:get, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(remote_socket, [
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "Content-Type: text/plain; charset=UTF-8"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "\r\n\r\n"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "1234"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "5678"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "90"
          },
          %Record{
            type: :end_request,
            request_id: request_id,
            content: %EndRequestBody{app_status: 0, protocol_status: :request_complete}
          }
        ])
    end)

    conn = Router.call(conn, @opts)

    assert get_resp_header(conn, "content-type") == ["text/plain; charset=UTF-8"]
    assert conn.resp_body == "1234567890"
  end

  test "handles stderr from the application", %{remote_socket: remote_socket} do
    conn = conn(:get, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(remote_socket, [
          %Record{
            type: :stderr,
            request_id: request_id,
            content: "123"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "Content-Type: text/plain; charset=UTF-8"
          },
          %Record{
            type: :stderr,
            request_id: request_id,
            content: "456"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "\r\n\r\n"
          },
          %Record{
            type: :stderr,
            request_id: request_id,
            content: "789"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "first stdout"
          },
          %Record{
            type: :stderr,
            request_id: request_id,
            content: "0AB"
          },
          %Record{
            type: :stdout,
            request_id: request_id,
            content: ", second stdout"
          },
          %Record{
            type: :stderr,
            request_id: request_id,
            content: "CDE"
          },
          %Record{
            type: :end_request,
            request_id: request_id,
            content: %EndRequestBody{app_status: 0, protocol_status: :request_complete}
          }
        ])
    end)

    {conn, error_log} =
      with_log([level: :error], fn ->
        Router.call(conn, @opts)
      end)

    assert get_resp_header(conn, "content-type") == ["text/plain; charset=UTF-8"]
    assert conn.resp_body == "first stdout, second stdout"

    assert error_log =~ "123"
    assert error_log =~ "456"
    assert error_log =~ "789"
    assert error_log =~ "0AB"
    assert error_log =~ "CDE"
  end

  test "raises an error if the socket is closed before sending", %{remote_socket: remote_socket} do
    conn = conn(:get, "/test")

    FastCGI.close(remote_socket)

    exception =
      assert_raise Plug.Conn.WrapperError, fn ->
        Router.call(conn, @opts)
      end

    assert %FastCGI.SocketError{reason: :closed} = exception.reason
  end

  test "raises an error if the socket is closed in the middle of reading headers", %{
    remote_socket: remote_socket
  } do
    conn = conn(:get, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(
          remote_socket,
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "Content-Type: text/plain; charset=UTF-8"
          }
        )

      FastCGI.close(remote_socket)
    end)

    exception =
      assert_raise Plug.Conn.WrapperError, fn ->
        Router.call(conn, @opts)
      end

    assert %FastCGI.SocketError{reason: :closed} = exception.reason
  end

  test "raises an error if the socket is closed in the middle of reading the body", %{
    remote_socket: remote_socket
  } do
    conn = conn(:get, "/test")

    Task.start_link(fn ->
      {:ok, %Record{type: :begin_request, request_id: request_id}} =
        FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(
          remote_socket,
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "Content-Type: text/plain; charset=UTF-8\r\n\r\nbody starts here"
          }
        )

      FastCGI.close(remote_socket)
    end)

    exception =
      assert_raise Plug.Conn.WrapperError, fn ->
        Router.call(conn, @opts)
      end

    assert %FastCGI.SocketError{reason: :closed} = exception.reason
  end

  test "logs the end request statuses", %{remote_socket: remote_socket} do
    conn = conn(:get, "/test")

    app_status = Enum.random(0..4_294_967_295)

    protocol_status =
      Enum.random([:request_complete, :cannot_multiplex_connection, :overloaded, :unknown_role])

    Task.start_link(fn ->
      assert {:ok, %Record{type: :begin_request, request_id: request_id}} =
               FastCGI.receive_record(remote_socket)

      :ok =
        FastCGI.send(remote_socket, [
          %Record{
            type: :stdout,
            request_id: request_id,
            content: "\r\n\r\n"
          },
          %Record{
            type: :end_request,
            request_id: request_id,
            content: %EndRequestBody{app_status: app_status, protocol_status: protocol_status}
          }
        ])
    end)

    info_log =
      capture_log([level: :info], fn ->
        Router.call(conn, @opts)
      end)

    assert info_log =~ "End FastCGI request\n  Request ID: "

    assert info_log =~
             "\n  Application status: #{app_status}\n  Protocol status: #{protocol_status}"
  end

  describe "php socket" do
    @describetag :php

    test "returns hello world" do
      conn = conn(:get, "/test.php", name: "World")

      {conn, error_log} =
        with_log([level: :error], fn ->
          Router.call(conn, @opts)
        end)

      assert conn.status == 200

      assert conn.resp_body =~ "Hello, World!\n"
      assert conn.resp_body =~ "PHP Version 8.3.7"

      assert get_resp_header(conn, "x-powered-by") == ["PHP/8.3.7"]
      assert get_resp_header(conn, "x-test-repeated") == ["1", "2"]
      assert get_resp_header(conn, "x-test-no-colon") == [""]
      assert get_resp_header(conn, "x-test-no-value") == [""]
      assert get_resp_header(conn, "x-test-no-value-whitespace") == [""]
      assert get_resp_header(conn, "x-test-multiple-colons") == ["value:with:colons"]
      assert get_resp_header(conn, "x-test-no-whitespace") == ["value"]
      assert get_resp_header(conn, "content-type") == ["text/html; charset=UTF-8"]

      assert error_log =~ "Hello, CGI stderr!"
    end
  end

  defp send_empty_response(remote_socket, request_id) do
    :ok =
      FastCGI.send(remote_socket, [
        %Record{
          type: :stdout,
          request_id: request_id,
          content: "\r\n\r\n"
        },
        %Record{
          type: :end_request,
          request_id: request_id,
          content: %EndRequestBody{app_status: 0, protocol_status: :request_complete}
        }
      ])
  end
end
