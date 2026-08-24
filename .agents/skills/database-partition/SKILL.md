---
name: database-partition
description: Use when a task adds tables, writes or tests migrations, alters schemas, or backfills data — before running any ecto.create/migrate/rollback/reset or seed command — especially in worktrees or when the user and other agents may be using the shared dev database.
---

# Database partitioning

The shared dev database (`template_phoenix_dev`) belongs to the user's running
server and other agents. Schema-changing or data-heavy work runs in its own
partition database.

**Already in a worktree?** The partition is ambient, not a choice: worktrunk's
pre-start hook (and the start-a-task skill's fallback) pins `DB_PARTITION` and
`MIX_TEST_PARTITION` in `.env`, so bare mix commands are already isolated.
This skill then governs what still needs judgment: what data your partition
needs (empty + seeds, or the clone below for backfill realism), the
reversibility checks, and the standing rules — which apply with full force
whenever you are *not* pinned (the main checkout).

## Use your own partition

Derive a snake_case name from your task and set up in one command — every mix
command accepts the same prefix and targets `template_phoenix_dev_<name>`:

```sh
DB_PARTITION=audit_logs_backfill mise exec -- mix ecto.setup
```

- **Pin it per worktree**: `echo 'DB_PARTITION=<name>' > .env` — mise then
  loads it for every command in that directory. mise env beats shell vars, so
  with a pin in place `DB_PARTITION=other mise exec -- mix ...` still uses the
  pin; override one command with `mise exec -- env DB_PARTITION=other mix ...`
- **Standing rule**: while schema work is in flight, never run a bare
  `mix ecto.migrate`, `ecto.rollback`, `ecto.reset`, or backfill `mix run` —
  bare commands hit the shared database, which receives your migration through
  merge, not during development
- **Tests**: `MIX_TEST_PARTITION=<name> mise exec -- mix test` targets
  `template_phoenix_test_<name>` (bare name, underscore added automatically)
- **Tophatting**: `DB_PARTITION=<name> mise exec -- mix server --subdomain tophat-<task>`

## Realistic data for backfills

`ecto.setup` gives schema + seeds only. Clone the shared database when you
need real data:

```sh
psql -d postgres -c "CREATE DATABASE template_phoenix_dev_<name> TEMPLATE template_phoenix_dev"
```

Failing with "source database is being accessed by other users" is expected
while anything is connected — never kill those connections (they are the
user's). Fall back to `ecto.setup` plus seeding what your backfill needs.

## Verify migrations both ways

With your `DB_PARTITION` set:

- `mix ecto.migrations` — the new migration shows `up`
- `mix ecto.rollback --step 1`, then re-migrate — reversibility proven before
  anyone else runs it

## Cleanup — required

- `DB_PARTITION=<name> mise exec -- mix ecto.drop`
- `MIX_ENV=test MIX_TEST_PARTITION=<name> mise exec -- mix ecto.drop` if you ran tests
- Leak check: `psql -d postgres -Atc "SELECT datname FROM pg_database WHERE datname LIKE 'template_phoenix_%_%'"`

## SQLite projects (ecto_sqlite3)

Some derived projects swap Postgres for SQLite. Same workflow, same rules —
the database is a file, so three commands differ:

- **Clone**: `sqlite3 template_phoenix_dev.db ".backup template_phoenix_dev_<name>.db"` —
  never `cp` a live file (mid-write state, missed WAL content)
- **Leak check**: `ls template_phoenix_dev_*.db*`
- **Drop**: `ecto.drop` as above, or delete the file with its `-wal`/`-shm`
  siblings

(`config/dev.exs` shape: `database: "template_phoenix_dev#{db_partition}.db"`)
