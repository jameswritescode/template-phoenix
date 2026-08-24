defmodule TemplatePhoenix.Health do
  @moduledoc """
  Application health checks backing `GET /health`.

  Returns `{:ok | :error, checks}` where each check is `"ok"` or `"error"`.
  Add further checks (cache, external services) to `check/0` as the
  application grows.

  ## Example alerts and charts

  Suggested monitoring to wire up in your APM/alerting tool, built on this
  endpoint and the metrics in `TemplatePhoenixWeb.Telemetry`:

  Alerts:

    * `GET /health` returns non-200 (or times out) from an uptime monitor —
      page-level outage signal
    * p95 of `phoenix.router_dispatch.stop.duration` above your latency
      budget for 5+ minutes
    * p95 of `template_phoenix.repo.query.query_time` rising — database
      degradation before it becomes an outage
    * `vm.memory.total` trending up without recovery — memory leak

  Charts:

    * request rate and latency percentiles (router dispatch duration)
    * database query time breakdown (query/queue/idle time)
    * BEAM memory and run queue lengths
  """

  alias Ecto.Adapters.SQL
  alias TemplatePhoenix.Repo

  @doc """
  Runs all health checks.
  """
  @spec check() :: {:ok | :error, %{String.t() => String.t()}}
  def check do
    checks = %{"database" => database_check()}
    status = if Enum.all?(Map.values(checks), &(&1 == "ok")), do: :ok, else: :error
    {status, checks}
  end

  defp database_check do
    case SQL.query(Repo, "SELECT 1", []) do
      {:ok, _result} -> "ok"
      {:error, _reason} -> "error"
    end
  rescue
    _error -> "error"
  catch
    :exit, _reason -> "error"
  end
end
