defmodule Mix.Tasks.ServerTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Server

  describe "find_free_port/1" do
    test "returns a bindable port from the range" do
      port = Server.find_free_port(4000..4500)

      assert port in 4000..4500
      assert {:ok, socket} = :gen_tcp.listen(port, ip: {127, 0, 0, 1}, reuseaddr: true)
      :gen_tcp.close(socket)
    end

    test "skips busy ports and raises when the whole range is taken" do
      {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
      {:ok, busy} = :inet.port(socket)

      assert_raise Mix.Error, ~r/No free port found/, fn ->
        Server.find_free_port(busy..busy//1)
      end
    end
  end

  describe "run/1 argument validation" do
    test "rejects invalid options" do
      assert_raise Mix.Error, ~r/Invalid options: --port/, fn ->
        Server.run(["--port", "abc"])
      end
    end

    test "rejects unexpected positional arguments" do
      assert_raise Mix.Error, ~r/Unexpected arguments: foo/, fn ->
        Server.run(["foo"])
      end
    end

    test "rejects out-of-range ports" do
      assert_raise Mix.Error, ~r/--port must be between 1 and 65535/, fn ->
        Server.run(["--port", "70000"])
      end
    end

    test "rejects invalid subdomains" do
      assert_raise Mix.Error, ~r/--subdomain must contain only/, fn ->
        Server.run(["--subdomain", "Bad_Sub!", "--port", "4400"])
      end
    end
  end
end
