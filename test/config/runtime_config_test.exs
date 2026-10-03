defmodule TemplatePhoenix.RuntimeConfigTest do
  # config/runtime.exs is evaluated at app start, after `mix server` has put
  # its resolved PORT/PHX_HOST into the environment; config/dev.exs is
  # evaluated at Mix boot, before the task runs. These tests evaluate
  # runtime.exs the same way app.config does, so they pin the values the
  # endpoint actually serves with.
  use ExUnit.Case, async: false

  @vars ~w(PHX_HOST SUBDOMAIN PORT)

  setup do
    originals = Map.new(@vars, &{&1, System.get_env(&1)})
    Enum.each(@vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(originals, fn
        {var, nil} -> System.delete_env(var)
        {var, value} -> System.put_env(var, value)
      end)
    end)
  end

  describe "dev endpoint URL host" do
    test "a --subdomain override (PHX_HOST) wins over a pinned SUBDOMAIN" do
      System.put_env("SUBDOMAIN", "worktree-pin")
      System.put_env("PHX_HOST", "tophat-feature.localhost")

      assert endpoint_url_host(:dev) == "tophat-feature.localhost"
    end

    test "a SUBDOMAIN pin implies <subdomain>.localhost" do
      System.put_env("SUBDOMAIN", "worktree-pin")

      assert endpoint_url_host(:dev) == "worktree-pin.localhost"
    end

    test "falls back to localhost when neither is set" do
      assert endpoint_url_host(:dev) == "localhost"
    end

    test "empty values mean unset" do
      System.put_env("PHX_HOST", "")
      System.put_env("SUBDOMAIN", "")

      assert endpoint_url_host(:dev) == "localhost"
    end
  end

  describe "endpoint HTTP port" do
    test "honors PORT" do
      System.put_env("PORT", "4123")

      assert endpoint_http(:dev)[:port] == 4123
    end

    test "an empty PORT means unset rather than crashing" do
      System.put_env("PORT", "")

      assert endpoint_http(:dev)[:port] == 4000
    end
  end

  @spec endpoint_url_host(atom()) :: String.t() | nil
  defp endpoint_url_host(env), do: get_in(endpoint_config(env), [:url, :host])

  @spec endpoint_http(atom()) :: keyword()
  defp endpoint_http(env), do: endpoint_config(env)[:http]

  @spec endpoint_config(atom()) :: keyword()
  defp endpoint_config(env) do
    "config/runtime.exs"
    |> Config.Reader.read!(env: env, target: :host)
    |> get_in([:template_phoenix, TemplatePhoenixWeb.Endpoint])
  end
end
