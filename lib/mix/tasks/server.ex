defmodule Mix.Tasks.Server do
  @shortdoc "Starts the Phoenix server on a free port, optionally under a .localhost subdomain"

  @port_range 4000..4500

  @moduledoc """
  Starts the Phoenix server like `mix phx.server`, with two optional flags:

      mix server [--subdomain SUBDOMAIN] [--port PORT]

  ## Options

    * `--port` - the port to bind. When omitted, a `PORT` env var (e.g. the
      per-worktree pin written by the worktrunk pre-start hook) is used; when
      neither is set, the first free port in the `#{inspect(@port_range)}`
      range is used. A provided port is used as-is, even outside that range.

    * `--subdomain` - serves the app at `http://<subdomain>.localhost`, setting
      the URL host. When omitted, a `SUBDOMAIN` env var (e.g. the per-worktree
      pin written by the worktrunk pre-start hook) is used instead; when
      neither is set, the app serves plain `localhost`. The subdomain sets
      the endpoint's URL host (via the `PHX_HOST` env var read by
      `config/dev.exs`) so the server treats it as its hostname and generated
      URLs use it. The chosen port is likewise passed via `PORT`. Browsers and modern system resolvers resolve
      `*.localhost` to loopback, so no hosts-file changes are needed.

  ## Examples

      mix server
      mix server --port 5001
      mix server --subdomain myapp
      mix server --subdomain myapp --port 4123
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, strict: [subdomain: :string, port: :integer])

    if invalid != [] do
      Mix.raise("Invalid options: " <> Enum.map_join(invalid, ", ", fn {opt, _} -> opt end))
    end

    if argv != [] do
      Mix.raise("Unexpected arguments: " <> Enum.join(argv, " "))
    end

    port = resolve_port(opts[:port])
    subdomain = opts[:subdomain] || env_subdomain()
    host = subdomain && validate_subdomain!(subdomain) <> ".localhost"

    System.put_env("PORT", Integer.to_string(port))
    if host, do: System.put_env("PHX_HOST", host)

    Mix.shell().info("Starting server on http://#{host || "localhost"}:#{port}")
    Mix.Task.run("phx.server", [])
  end

  @doc """
  Returns the first port in `range` that is free to bind on 127.0.0.1.

  Raises `Mix.Error` when every port in the range is taken.
  """
  @spec find_free_port(Range.t()) :: :inet.port_number()
  def find_free_port(range) do
    Enum.find(range, &port_free?/1) ||
      Mix.raise("No free port found in #{inspect(range)}. Pass --port to choose one explicitly.")
  end

  defp resolve_port(nil), do: env_port() || find_free_port(@port_range)
  defp resolve_port(port) when port in 1..65_535, do: port

  defp resolve_port(port) do
    Mix.raise("--port must be between 1 and 65535, got: #{port}")
  end

  defp env_port do
    case System.get_env("PORT") do
      empty when empty in [nil, ""] -> nil
      port -> String.to_integer(port)
    end
  end

  defp validate_subdomain!(subdomain) do
    if subdomain =~ ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/ do
      subdomain
    else
      Mix.raise(
        "Subdomain (--subdomain flag or SUBDOMAIN env) must contain only lowercase " <>
          "letters, digits, and inner hyphens, got: #{subdomain}"
      )
    end
  end

  defp env_subdomain do
    case System.get_env("SUBDOMAIN") do
      empty when empty in [nil, ""] -> nil
      subdomain -> subdomain
    end
  end

  defp port_free?(port) do
    case :gen_tcp.listen(port, ip: {127, 0, 0, 1}, reuseaddr: true) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end
end
