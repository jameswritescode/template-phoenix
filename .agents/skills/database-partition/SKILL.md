---
name: database-partition
description: Use when a task adds tables, writes or tests migrations, alters schemas, backfills data, or needs a second database — before running any ecto.create/migrate/rollback/reset or seed command.
---

# Database partitioning

Every worktree has its own databases. The start-a-task skill (worktrunk's
pre-start hook, or its manual fallback) pins `DB_PARTITION` and
`MIX_TEST_PARTITION` in the worktree's `.env`, so every mix command there
targets `template_phoenix_dev_<partition>` and
`template_phoenix_test_<partition>`. That includes bare `mix ecto.migrate`,
`mix test`, and tophat servers.

The shared `template_phoenix_dev` and `template_phoenix_test` belong to the
user's main checkout. No worktree should ever touch them.

## Check the pins before any database command

```sh
mise exec -- env | grep -E '^(DB|MIX_TEST)_PARTITION='
```

Both lines should show your worktree's partition. If either is missing, your
commands are aimed at a shared database: stop and fix the worktree setup
(start-a-task) before running anything. Don't work around a missing pin with
one-off overrides.

## Your worktree's partition

- `mix setup` created it when the worktree was set up (schema + seeds)
- Don't change the pin. The worktree's dev server, tests, and teardown all
  rely on it
- Rebuild it any time with `mise exec -- mix ecto.reset`. With the pins in
  place this resets your partition only

## Extra scratch partitions

Sometimes you want a second database: isolating a flaky test, or a
destructive experiment you don't want to run on your partition. Override one
command at a time. mise env beats shell vars, so a plain
`DB_PARTITION=... mise exec -- ...` prefix loses to the pin; put the override
inside the exec:

```sh
mise exec -- env DB_PARTITION=<scratch> mix ecto.setup
mise exec -- env MIX_TEST_PARTITION=<scratch> mix test
```

Name scratch partitions after your task. Worktree teardown only drops the
worktree's own partition, so drop scratch ones yourself before finishing:
`bin/drop-partition.sh <scratch>`.

## Realistic data for backfills

`mix setup` gives schema + seeds only. To backfill against real data, replace
your partition with a clone of the shared dev database. Stop your own servers
first, since the drop fails while anything is connected to your partition:

```sh
bin/drop-partition.sh <partition>
psql -d postgres -c "CREATE DATABASE template_phoenix_dev_<partition> TEMPLATE template_phoenix_dev"
mise exec -- mix ecto.migrate
```

- `<partition>` is your `DB_PARTITION` from the pin check above
- The drop goes through the script rather than a bare `mix ecto.drop`
  because the script names the partition explicitly and refuses an empty
  one; a bare drop with a missing pin would drop the shared database
- Cloning only reads the shared database. It fails with "source database is
  being accessed by other users" while anything is connected to the shared
  database, usually the user's server. Never kill those connections. Instead,
  recreate your partition with `mise exec -- mix ecto.setup` and seed what
  your backfill needs
- `mix ecto.migrate` applies your branch's migrations on top of the clone

## Verify migrations both ways

- `mise exec -- mix ecto.migrations`: the new migration shows `up`
- `mise exec -- mix ecto.rollback --step 1`, then `mise exec -- mix ecto.migrate`:
  reversibility proven before anyone else runs it

## Cleanup

Your worktree's partition is dropped when the worktree is removed (the
finish-a-task skill). Only scratch partitions are yours to clean up:
`bin/drop-partition.sh <scratch>`. It refuses an empty name, which would mean
the shared databases.

Leak check (partitions only, never the shared databases):

```sh
psql -d postgres -Atc "SELECT datname FROM pg_database WHERE datname ~ '^template_phoenix_(dev|test)_.+'"
```

## SQLite projects (ecto_sqlite3)

Some derived projects swap Postgres for SQLite. Same workflow, same rules; the
database is a file, so three commands differ:

- **Clone**: `sqlite3 template_phoenix_dev.db ".backup template_phoenix_dev_<partition>.db"`.
  Never `cp` a live file (mid-write state, missed WAL content)
- **Leak check**: `ls template_phoenix_dev_*.db*`
- **Drop**: `bin/drop-partition.sh` works unchanged (it runs `mix ecto.drop`),
  or delete the file with its `-wal`/`-shm` siblings

(`config/dev.exs` shape: `database: "template_phoenix_dev#{db_partition}.db"`)
