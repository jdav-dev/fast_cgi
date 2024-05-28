defmodule FastCGI.SocketError do
  @moduledoc """
  The request could not be processed due to a socket error.
  """

  defexception [:reason]

  def message(%{reason: reason}) do
    "could not process the request due to socket error: #{inspect(reason)}"
  end
end
