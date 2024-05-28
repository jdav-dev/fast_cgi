defmodule FastCGI.TempPhpSocket do
  @behaviour FastCGI.SocketPool

  @impl FastCGI.SocketPool
  def checkout!(socket_fun) do
    wrapper_path = Path.expand("../../priv/wrapper", __DIR__)
    php_cgi_path = System.find_executable("php-cgi")
    sock_dir = Path.join([System.tmp_dir!(), to_string(FastCGI), to_string(Mix.env())])
    File.mkdir_p!(sock_dir)
    sock_path = Path.join(sock_dir, "#{System.unique_integer([:positive])}.sock")
    doc_root = Path.join(__DIR__, "php")

    port =
      Port.open({:spawn_executable, wrapper_path}, [
        :binary,
        args: [
          php_cgi_path,
          "-b=#{sock_path}",
          "-n",
          "-d=doc_root=#{doc_root}"
        ]
      ])

    # Allow php-cgi to start
    Process.sleep(500)

    {:ok, socket} = FastCGI.connect({:local, sock_path}, 0)

    result = socket_fun.(socket)

    FastCGI.close(socket)
    Port.close(port)
    File.rm!(sock_path)

    result
  end
end
