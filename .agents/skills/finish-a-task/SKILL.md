---
name: finish-a-task
description: Use when wrapping up development work in this repo — before calling a task done, before pushing or opening a PR, and after a PR merges when it is time to remove the worktree and its databases.
---

# Finishing a task

Finishing happens at two separate moments. **Ready for review** is when the
code is done. **Teardown** comes after the merge. Until then the worktree is
still needed for review fixes, so never tear down at PR time.

## Phase 1: ready for review

1. **Gate**: `mise exec -- mix precommit`. For JS changes, also run
   `mise exec -- mix cmd --cd assets pnpm test`. If you changed anything under
   `bin/`, run the matching e2e too (`bin/test-rename.sh`, and
   `bin/test-remove-auth.sh` if present). Fix failures in the code; never
   disable a check
2. **Tophat** user-facing changes against the final code (tophat skill)
3. **Clean up what you started**:
   - stop your tophat servers. The worktree's pinned-`PORT` server is the
     user's, not yours
   - close the browser tabs you opened
   - drop any scratch partitions you made beyond the worktree's own:
     `bin/drop-partition.sh <name>`
4. **Review your own diff**: `git status` is clean, with no stray logs or
   debug calls
5. **Open the PR** only when the user has asked; pushing is outward-facing.
   Push the branch, then `gh pr create`
   - **Never use `wt merge` for PR work.** It squashes your branch into the
     local default branch, fast-forwards it, and removes the worktree. That is
     a local merge that skips review, meant only for branches the user wants
     merged without a PR
   - The description needs an **Observability** section (AGENTS.md): the logs
     and metrics you added, plus suggested alerts and charts. If there are
     none, say so and why
6. **Leave the worktree and its partition databases in place**

## Phase 2: teardown, after the merge

1. **Confirm the merge**: `gh pr view <number> --json state` must say
   `MERGED`. Never tear down an open PR's worktree
2. **Confirm nothing is lost**: `git status` is clean, and every commit is on
   the remote (`git log @{upstream}..HEAD` prints nothing). A squash-merged
   branch looking "unmerged" locally is expected. Uncommitted or unpushed work
   is not, so stop and ask
3. **Remove the worktree** (run from anywhere in the repo):
   - **worktrunk**: `wt remove <branch>`. Its pre-remove hook runs
     `bin/drop-partition.sh` for the branch's partition
     - It refuses a dirty worktree. Never add `-f` or `-D` to get past that
       without asking
     - Never use `--reap`: it kills every process running from the worktree,
       including the user's dev server
   - **without worktrunk**: run `bin/drop-partition.sh <partition>` from the
     worktree, then `git worktree remove <path>`
   - If a drop fails with "being accessed by other users", something is
     still connected. Stop it if it's your server; otherwise ask. Never kill
     connections you didn't open
4. **Leak check**. This lists partition databases only, never the shared
   `template_phoenix_dev` / `template_phoenix_test`:

   ```sh
   psql -d postgres -Atc "SELECT datname FROM pg_database WHERE datname ~ '^template_phoenix_(dev|test)_.+' ORDER BY 1"
   ```

   - A partition with no matching worktree (`git worktree list`) is a leak.
     Drop it with `bin/drop-partition.sh <partition>`
   - If you can't tell whose a partition is, ask before dropping it
