# TemplatePhoenix

A Phoenix 1.8 application template.

## Starting a new project from this template

1. **Rename the app** (snake_case name; the script renames modules, files, and
   config, then deletes itself — pass `--keep` to retain it):

   ```sh
   bin/rename.sh my_app
   ```

2. **Install tool versions** (Erlang, Elixir, Node, pnpm are pinned in `mise.toml`):

   ```sh
   mise install
   ```

3. **Create the Postgres role.** Dev and test config authenticate with a role
   named after the app (username and password both match the app name):

   ```sh
   psql -d postgres -c "CREATE ROLE template_phoenix WITH LOGIN CREATEDB PASSWORD 'template_phoenix';"
   ```

   (The rename script updates this command to your app's name, so it stays
   copy-pasteable.)

4. **Set up and run:**

   ```sh
   mix setup
   mix phx.server
   ```

## Development

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

### `mix server`

A wrapper around `mix phx.server` with optional flags:

* `mix server` - picks the first free port in 4000-4500 automatically
* `mix server --port 5001` - uses the given port (any port, not just the default range)
* `mix server --subdomain myapp` - serves at `http://myapp.localhost:<port>`; the
  endpoint treats that host as its own, and `*.localhost` resolves to loopback
  without any hosts-file changes

### Testing

* Elixir: `mix test`
* JavaScript (vitest, managed with pnpm): `cd assets && pnpm install && pnpm test`

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
