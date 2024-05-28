defmodule FastCGITest do
  use FastCGI.SocketCase, async: true
  use ExUnitProperties

  alias FastCGI.Record
  alias FastCGI.Record.BeginRequestBody
  alias FastCGI.Record.EndRequestBody
  alias FastCGI.Record.NameValuePair
  alias FastCGI.Record.UnknownTypeBody

  @tag :skip_socket_case
  test "socket function default values" do
    {listen_socket, port} = find_open_port()
    on_exit(fn -> FastCGI.close(listen_socket) end)

    {:ok, socket} = FastCGI.connect({127, 0, 0, 1}, port)
    on_exit(fn -> FastCGI.close(socket) end)

    assert {:ok, remote_socket} = FastCGI.accept(listen_socket)
    on_exit(fn -> FastCGI.close(remote_socket) end)
  end

  defp find_open_port(port \\ 4000) do
    if port > 4100, do: flunk("couldn't find open port")

    case FastCGI.listen(port) do
      {:ok, listen_socket, ^port} -> {listen_socket, port}
      {:error, :eaddrinuse} -> find_open_port(port + 1)
    end
  end

  describe "get_values/2" do
    property "sends value list to the application and maps the response", %{
      remote_socket: remote_socket,
      socket: socket
    } do
      check all variables <- map_of(string(:utf8), string(:utf8, min_length: 1)) do
        Task.start_link(fn ->
          assert {:ok, %Record{type: :get_values, content: content}} =
                   FastCGI.receive_record(remote_socket)

          for name_value_pair <- content do
            assert %NameValuePair{name: name, value: nil} = name_value_pair
            assert is_map_key(variables, name)
          end

          response_content =
            for {key, value} <- variables, do: %NameValuePair{name: key, value: value}

          :ok =
            FastCGI.send(remote_socket, %Record{
              type: :get_values_result,
              content: response_content
            })
        end)

        assert {:ok, ^variables} = FastCGI.get_values(socket, Map.keys(variables))
      end
    end

    test "handles empty values", %{remote_socket: remote_socket, socket: socket} do
      Task.start_link(fn ->
        assert {:ok, %Record{type: :get_values, content: []}} =
                 FastCGI.receive_record(remote_socket)

        :ok = FastCGI.send(remote_socket, %Record{type: :get_values_result, content: []})
      end)

      assert {:ok, %{}} == FastCGI.get_values(socket, [])
    end
  end

  property "records can be sent and received", %{remote_socket: remote_socket, socket: socket} do
    check all records <- list_of(record_generator(), min_length: 1) do
      assert :ok = FastCGI.send(socket, records)

      for record <- records do
        assert {:ok, record} == FastCGI.receive_record(remote_socket)
      end
    end
  end

  test "send/2 returns :ok for empty lists", %{
    remote_socket: remote_socket,
    socket: socket
  } do
    :ok = FastCGI.close(remote_socket)
    assert :ok = FastCGI.send(socket, [])
  end

  property "receive/2 casts empty binary content as nil", %{
    remote_socket: remote_socket,
    socket: socket
  } do
    check all binary_type <- one_of([:stdin, :stdout, :stderr, :data]),
              request_id <- request_id_generator(binary_type) do
      record = %Record{type: binary_type, request_id: request_id, content: ""}
      :ok = FastCGI.send(socket, record)
      assert {:ok, %Record{content: nil}} = FastCGI.receive_record(remote_socket)
    end
  end

  defp record_generator do
    gen all type <- type_generator(),
            request_id <- request_id_generator(type),
            content <- content_generator(type) do
      %Record{type: type, request_id: request_id, content: content}
    end
  end

  defp type_generator do
    one_of([
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
    ])
  end

  defp request_id_generator(type) when type in [:get_values, :get_values_result, :unknown_type] do
    nil
  end

  defp request_id_generator(_type) do
    integer(1..65535)
  end

  defp content_generator(:begin_request) do
    gen all role <- one_of([:responder, :authorizer, :filter]),
            keep_conn <- boolean() do
      %BeginRequestBody{role: role, keep_conn: keep_conn}
    end
  end

  defp content_generator(:abort_request) do
    nil
  end

  defp content_generator(:end_request) do
    gen all app_status <- integer(0..4_294_967_295),
            protocol_status <-
              one_of([:request_complete, :cannot_multiplex_connection, :overloaded, :unknown_role]) do
      %EndRequestBody{app_status: app_status, protocol_status: protocol_status}
    end
  end

  defp content_generator(type) when type in [:params, :get_values_result] do
    gen all variables <- map_of(string(:utf8), string(:utf8, min_length: 1)) do
      for {key, value} <- variables do
        %NameValuePair{name: key, value: value}
      end
    end
  end

  defp content_generator(type) when type in [:stdin, :stdout, :stderr, :data] do
    one_of([binary(min_length: 1), nil])
  end

  defp content_generator(:get_values) do
    gen all names <- list_of(string(:utf8)) do
      for name <- names do
        %NameValuePair{name: name}
      end
    end
  end

  defp content_generator(:unknown_type) do
    gen all type <- integer(0..255) do
      %UnknownTypeBody{type: type}
    end
  end

  describe "php" do
    @describetag :php

    test "get_values/2 returns a map of values" do
      FastCGI.TempPhpSocket.checkout!(fn socket ->
        assert FastCGI.get_values(socket, [
                 "FCGI_MAX_CONNS",
                 "FCGI_MAX_REQS",
                 "FCGI_MPXS_CONNS",
                 "NOT_A_KEY"
               ]) ==
                 {:ok,
                  %{"FCGI_MAX_CONNS" => "1", "FCGI_MAX_REQS" => "1", "FCGI_MPXS_CONNS" => "0"}}
      end)
    end

    test "get_values/2 handles empty values" do
      FastCGI.TempPhpSocket.checkout!(fn socket ->
        assert {:ok, %{}} == FastCGI.get_values(socket, [])
      end)
    end
  end
end
