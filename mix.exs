defmodule FastCGI.Plug.MixProject do
  use Mix.Project

  def project do
    [
      app: :fast_cgi,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:plug, "~> 1.0", optional: true},
      {:stream_data, "~> 1.0", only: [:dev, :test]}
    ]
  end
end
