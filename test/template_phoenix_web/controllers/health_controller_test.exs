defmodule TemplatePhoenixWeb.HealthControllerTest do
  use TemplatePhoenixWeb.ConnCase, async: true

  test "GET /health reports ok with a healthy database", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert json_response(conn, 200) == %{
             "status" => "ok",
             "checks" => %{"database" => "ok"}
           }
  end
end
