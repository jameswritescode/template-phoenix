defmodule TemplatePhoenixWeb.PageController do
  use TemplatePhoenixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
