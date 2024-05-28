defmodule FastCGI.SocketPool do
  @callback checkout!(socket_fun :: (FastCGI.socket() -> result)) :: result when result: term()
end
