defmodule FastCGI do
  @moduledoc """
  Documentation for `FastCGI`.
  """

  alias FastCGI.Record
  alias FastCGI.Record.Encoder
  alias FastCGI.Record.NameValuePair

  @opaque socket :: :gen_tcp.socket()

  @spec accept(socket(), timeout()) ::
          {:ok, socket()} | {:error, reason :: :closed | :timeout | :system_limit | :inet.posix()}
  def accept(socket, timeout \\ :timer.seconds(5)) do
    :gen_tcp.accept(socket, timeout)
  end

  @spec close(socket()) :: :ok
  def close(socket) do
    :gen_tcp.close(socket)
  end

  @spec connect(
          address :: :inet.socket_address() | :inet.hostname(),
          port :: :inet.port_number(),
          timeout()
        ) ::
          {:ok, socket()} | {:error, reason :: :timeout | :inet.posix()}
  def connect(address, port, timeout \\ :timer.seconds(5)) do
    :gen_tcp.connect(
      address,
      port,
      [:binary, active: false, packet: 0, send_timeout: timeout],
      timeout
    )
  end

  @doc """
  Query variables within the FastCGI application.

  FastCGI variables include:

    * `FCGI_MAX_CONNS` - The maximum number of concurrent transport connections the application
      will accept.
    * `FCGI_MAX_REQS` - The maximum number of concurrent requests the application will accept.
    * `FCGI_MPXS_CONNS` - `"0"` if the application does not multiplex connections (i.e. handle
      concurrent requests over each connection), `"1"` otherwise.
  """
  @spec get_values(socket(), variable_names :: [String.t()]) ::
          {:ok, values_map :: map()}
          | {:error, reason :: :closed | {:timeout, rest_data :: binary} | :inet.posix()}
  def get_values(socket, variable_names) when is_list(variable_names) do
    name_values = for name <- variable_names, do: %NameValuePair{name: name}
    record = %Record{type: :get_values, content: name_values}

    with :ok <- FastCGI.send(socket, record),
         {:ok, record} <- receive_record(socket) do
      {:ok, Map.new(record.content, &{&1.name, &1.value})}
    end
  end

  @spec listen(port :: :inet.port_number()) ::
          {:ok, socket(), port :: :inet.port_number()}
          | {:error, reason :: :system_limit | :inet.posix()}
  def listen(port \\ 0) do
    with {:ok, socket} <- :gen_tcp.listen(port, [:binary, active: false]) do
      {:ok, port} = :inet.port(socket)
      {:ok, socket, port}
    end
  end

  @spec new_request_id() :: Record.request_id()
  def new_request_id do
    :rand.uniform(65535)
  end

  @spec receive_record(socket(), timeout()) ::
          {:ok, Record.t()} | {:error, reason :: :closed | :inet.posix()}
  defdelegate receive_record(socket, timeout \\ :timer.seconds(5)), to: Record

  @spec send(socket(), Record.t() | [Record.t()]) ::
          :ok | {:error, reason :: :closed | {:timeout, rest_data :: binary} | :inet.posix()}
  def send(_socket, []) do
    :ok
  end

  def send(socket, record_or_records) do
    record_or_records
    |> Encoder.to_iodata()
    |> then(&:gen_tcp.send(socket, &1))
  end
end
