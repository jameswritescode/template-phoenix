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

### Agent skills

Skills live canonically in `.agents/skills/` (read natively by Codex).
`.claude/skills/` contains one symlink per skill, because Claude Code follows
per-skill symlinks but not a symlinked skills directory
([claude-code#38051](https://github.com/anthropics/claude-code/issues/38051)).
When a new skill is added (by hand or by `mix usage_rules.sync`), run
`mix skills.link` — it creates missing per-skill symlinks, repoints wrong
ones, and prunes dangling links for removed skills.

### Environment variables

mise manages env vars — no dotenv library needed. Three layers, all
per-directory (each worktree gets its own):

* `mise.toml` `[env]` - committed, shared defaults
* `.env` - gitignored, loaded by mise via `[env] _.file` (e.g.
  `echo 'DB_PARTITION=my_task' > .env` in a worktree, then forget it)
* `mise.local.toml` - gitignored personal overrides

With mise activated in your shell these load automatically on `cd`. In
non-interactive contexts (agents, scripts, CI), prefix commands with
`mise exec --` so tools and env resolve from the current directory.

Precedence: mise-managed values (`[env]`, `.env`, `mise.local.toml`)
override variables set in the shell — `DB_PARTITION=x mise exec -- ...`
loses to a `.env` pin. To override one command, set the var inside the
exec: `mise exec -- env DB_PARTITION=x mix ecto.drop`.

### Database partitions

Schema-changing or backfill work shouldn't share the main dev database.
`DB_PARTITION=<name>` suffixes the dev database (`template_phoenix_dev_<name>`)
for every mix command, e.g. `DB_PARTITION=checkout_backfill mix ecto.setup`.
Drop it when done: `DB_PARTITION=checkout_backfill mix ecto.drop`.

### Monitoring

`GET /health` returns `{"status":"ok","checks":{"database":"ok"}}`, or 503
when a check fails — point uptime monitors and load balancers at it. Example
alerts and charts to pair with the telemetry metrics are documented in
`TemplatePhoenix.Health`.

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
