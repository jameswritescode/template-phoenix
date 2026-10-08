---
name: start-a-task
description: Use when beginning any development task in this repo — a feature, fix, migration, or experiment — before editing files or setting up a workspace, especially when the user or other agents may be working concurrently.
---

# Starting a task

Never work directly in the user's checkout. Every task gets its own worktree
with pinned env (subdomain, database partitions, port) and warm build caches.

## Every worktree gets its own databases

Each worktree pins `DB_PARTITION` and `MIX_TEST_PARTITION` (in `.env`), so it
has its own dev database (`template_phoenix_dev_<partition>`) and its own test
database (`template_phoenix_test_<partition>`). Both lanes below set this up;
neither is optional. Never point a worktree at the shared `template_phoenix_dev`
or `template_phoenix_test` — the user's running server and other agents' test
runs use those. The partition is created on setup and dropped on teardown
with `bin/drop-partition.sh <partition>`.

## Preferred: worktrunk

If `wt` is available (`which wt`):

```sh
wt switch --create <branch-name>
```

The pre-start hook (`.config/wt.toml`) does everything: copies `deps/`,
`_build/` (dialyzer PLTs, asset binaries), `assets/node_modules/`, and `.env`
from the primary worktree; re-derives the four managed `.env` keys (`PORT`,
`SUBDOMAIN`, `DB_PARTITION`, `MIX_TEST_PARTITION`) for the branch; runs
`mix setup` against the warm caches, which creates the partition database.
You land in a ready, isolated workspace in seconds.

- If wt reports hooks need approval, stop and ask the user to run
  `wt config approvals add` — never bypass it with `--yes` yourself

## Fallback: plain git worktree

Not everyone uses worktrunk. Without it, mirror the pre-start hook by hand —
`.config/wt.toml` is the source of truth. From the new worktree:

```sh
mise trust
cp -Rc <primary>/deps <primary>/_build .          # warm caches (reflink; optional)
cp -Rc <primary>/assets/node_modules assets/
```

Copy the primary's `.env` if present, strip any `PORT`, `SUBDOMAIN`,
`DB_PARTITION`, `MIX_TEST_PARTITION` lines from it, then append fresh pins
derived from the branch (dashes for the subdomain, snake_case for the
partitions; omit `PORT` — `mix server` scans for a free one). The partition
pins are what give this worktree its own databases — don't skip them:

```sh
printf 'SUBDOMAIN=%s\nDB_PARTITION=%s\nMIX_TEST_PARTITION=%s\n' \
  my-branch my_branch my_branch >> .env
mise exec -- mix setup   # creates template_phoenix_dev_my_branch
```

## During the task

- Database work follows the database-partition skill: check the pins first,
  then bare mix commands are safe here because they target this worktree's
  partition
- Verify user-facing changes with the tophat skill — the worktree's pinned
  `PORT` belongs to the main dev server, so tophat servers scan for a free
  port with `--free-port` (the skill shows the command)
- Wrapping up, opening a PR, and tearing down the worktree after merge:
  follow the finish-a-task skill
