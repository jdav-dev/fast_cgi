defmodule FastCGI.PlugTest do
  use ExUnit.Case
  doctest FastCGI.Plug

  test "greets the world" do
    assert FastCGI.Plug.hello() == :world
  end
end
