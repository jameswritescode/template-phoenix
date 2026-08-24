import Config

# MIX_TEST_PARTITION suffixes the test database name, same normalized form as
# DB_PARTITION in dev.exs: bare names, underscore added automatically.
test_partition =
  case System.get_env("MIX_TEST_PARTITION") do
    empty when empty in [nil, ""] -> ""
    partition -> "_" <> partition
  end

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :template_phoenix, TemplatePhoenix.Repo,
  username: "template_phoenix",
  password: "template_phoenix",
  hostname: "localhost",
  database: "template_phoenix_test#{test_partition}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :template_phoenix, TemplatePhoenixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "YhBg/ieHWqzaGv4tG5+LIYAWZns9rOiCkkNmyOEjef0d8zPVT9oJrUP7fI1SGJFW",
  server: false

# In test we don't send emails
config :template_phoenix, TemplatePhoenix.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
