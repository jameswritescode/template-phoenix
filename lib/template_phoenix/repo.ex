defmodule TemplatePhoenix.Repo do
  use Ecto.Repo,
    otp_app: :template_phoenix,
    adapter: Ecto.Adapters.Postgres
end
