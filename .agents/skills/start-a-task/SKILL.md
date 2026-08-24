---
name: start-a-task
description: Use when beginning any development task in this repo — a feature, fix, migration, or experiment — before editing files or setting up a workspace, especially when the user or other agents may be working concurrently.
---

# Starting a task

Never work directly in the user's checkout. Every task gets its own worktree
with pinned env (subdomain, database partitions, port) and warm build caches.

## Preferred: worktrunk

If `wt` is available (`which wt`):

```sh
wt switch --create <branch-name>
```

The pre-start hook (`.config/wt.toml`) does everything: copies `deps/`,
`_build/` (dialyzer PLTs, asset binaries), `assets/node_modules/`, and `.env`
from the primary worktree; re-derives the four managed `.env` keys (`PORT`,
`SUBDOMAIN`, `DB_PARTITION`, `MIX_TEST_PARTITION`) for the branch; runs
`mix setup` against the warm caches. You land in a ready, isolated workspace
in seconds.

- If wt reports hooks need approval, stop and ask the user to run
  `wt config approvals add` — never bypass it with `--yes` yourself
- Finishing: `wt merge` runs the full gate and, on removal, drops the
  partition databases automatically

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
partitions; omit `PORT` — `mix server` scans for a free one):

```sh
printf 'SUBDOMAIN=%s\nDB_PARTITION=%s\nMIX_TEST_PARTITION=%s\n' \
  my-branch my_branch my_branch >> .env
mise exec -- mix setup
```

## During the task

- Database work follows the database-partition skill's rules (the pins make
  bare mix commands safe here, but its standing rules still apply)
- Verify user-facing changes with the tophat skill — `mix server` picks up
  the pinned `SUBDOMAIN` and `PORT` automatically
- Run `mise exec -- mix precommit` (and `pnpm test` for JS changes) before
  calling the task done

## Finishing without worktrunk

```sh
mise exec -- env DB_PARTITION=my_branch mix ecto.drop
mise exec -- env MIX_ENV=test MIX_TEST_PARTITION=my_branch mix ecto.drop
git worktree remove <path>
```
