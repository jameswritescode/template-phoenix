---
name: database-partition
description: Use when a task adds tables, writes or tests migrations, alters schemas, or backfills data — before running any ecto.create/migrate/rollback/reset or seed command — especially in worktrees or when the user and other agents may be using the shared dev database.
---

# Database partitioning

The shared dev database (`template_phoenix_dev`) belongs to the user's running
server and other agents. Schema-changing or data-heavy work runs in its own
partition database instead.

## Use your own partition

Derive a snake_case partition name from your task (e.g. `audit_logs_backfill`)
and carry `DB_PARTITION=<name>` on every stateful mix command; it targets
`template_phoenix_dev_<name>`:

```sh
DB_PARTITION=audit_logs_backfill mise exec -- mix ecto.create
DB_PARTITION=audit_logs_backfill mise exec -- mix ecto.migrate
DB_PARTITION=audit_logs_backfill mise exec -- mix run priv/repo/seeds.exs
```

- **Set-and-forget per worktree**: instead of prefixing every command, pin the
  partition once with `echo 'DB_PARTITION=<name>' > .env` — mise loads it for
  every command in that directory. Note mise-managed env overrides shell vars:
  with a `.env` pin in place, `DB_PARTITION=other mise exec -- mix ...` still
  uses the pin; to override one command, use
  `mise exec -- env DB_PARTITION=other mix ...`.
- **Standing rule**: while schema work is in flight, never run a bare
  `mix ecto.migrate`, `ecto.rollback`, `ecto.reset`, or backfill `mix run` —
  bare commands hit the shared database. The shared database receives your
  migration through the normal merge flow, not during development.
- **Tests**: `MIX_TEST_PARTITION=<name> mise exec -- mix test` targets
  `template_phoenix_test_<name>`, isolating concurrent suite runs across
  worktrees (bare name; the underscore is added for you, same as DB_PARTITION).
- **Tophatting**: combine with the tophat skill:
  `DB_PARTITION=<name> mise exec -- mix server --subdomain tophat-<task>`.

## Realistic data for backfills

`mix ecto.setup` gives you schema + seeds only. To exercise a backfill against
realistic dev data, clone the shared database:

```sh
psql -d postgres -c "CREATE DATABASE template_phoenix_dev_<name> TEMPLATE template_phoenix_dev"
```

If this fails with "source database is being accessed by other users", that is
expected while anything is connected to the shared DB — never kill those
connections (they are the user's). Fall back to `ecto.setup` plus seeding the
data your backfill needs.

## Verify migrations both ways

- `DB_PARTITION=<name> mise exec -- mix ecto.migrations` — new migration shows `up`
- `DB_PARTITION=<name> mise exec -- mix ecto.rollback --step 1` then re-migrate —
  proves the migration is reversible before anyone else runs it

## SQLite projects (ecto_sqlite3)

Some projects derived from this template swap Postgres for SQLite. The same
partition workflow and rules apply — the database is a file, so the
engine-specific commands change:

- `config/dev.exs` shape: `database: "template_phoenix_dev#{db_partition}.db"` —
  `DB_PARTITION` selects a separate database file, same env var, same naming
- **Realistic data**: never `cp` a live SQLite file (you'd catch a mid-write
  state and miss WAL content); use the online backup API instead:

  ```sh
  sqlite3 template_phoenix_dev.db ".backup template_phoenix_dev_<name>.db"
  ```

- **Leak check**: partition databases are just files —
  `ls template_phoenix_dev_*.db*`
- **Cleanup**: `DB_PARTITION=<name> mise exec -- mix ecto.drop`, or delete the
  file together with its `-wal`/`-shm` siblings

## Cleanup — required

- `DB_PARTITION=<name> mise exec -- mix ecto.drop`
- `MIX_ENV=test MIX_TEST_PARTITION=<name> mise exec -- mix ecto.drop` if you ran tests
- Check nothing leaked: `psql -d postgres -Atc "SELECT datname FROM pg_database WHERE datname LIKE 'template_phoenix_%_%'"`
