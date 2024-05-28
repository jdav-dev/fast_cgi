defmodule FastCGI.ProcessDictSocket do
  @behaviour FastCGI.SocketPool

  @impl FastCGI.SocketPool
  def checkout!(socket_fun) do
    socket = Process.get(:fast_cgi_socket)
    socket_fun.(socket)
  end
end
