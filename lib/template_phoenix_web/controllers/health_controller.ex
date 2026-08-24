defmodule TemplatePhoenixWeb.HealthController do
  use TemplatePhoenixWeb, :controller

  alias TemplatePhoenix.Health

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, _params) do
    {status, checks} = Health.check()

    conn
    |> put_status(if status == :ok, do: 200, else: 503)
    |> json(%{status: status, checks: checks})
  end
end
