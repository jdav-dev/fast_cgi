defmodule FastCGI.SocketCase do
  use ExUnit.CaseTemplate

  setup tags do
    if tags[:skip_socket_case] || tags[:php] do
      :ok
    else
      {:ok, listen_socket, port} = FastCGI.listen()
      on_exit(fn -> FastCGI.close(listen_socket) end)

      {:ok, socket} = FastCGI.connect({127, 0, 0, 1}, port)
      on_exit(fn -> FastCGI.close(socket) end)

      {:ok, remote_socket} = FastCGI.accept(listen_socket, 0)
      on_exit(fn -> FastCGI.close(socket) end)

      Process.put(:fast_cgi_socket, socket)

      {:ok, remote_socket: remote_socket, socket: socket}
    end
  end
end
