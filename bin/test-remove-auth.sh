#!/usr/bin/env bash
#
# End-to-end test for bin/remove-auth.sh:
#   1. strips auth from a copy of the COMMITTED tree and runs the FULL
#      quality gate (mix precommit) plus JS tests on the result;
#   2. proves rename-then-remove also works (compile-level);
#   3. proves the pre-flight refuses an already-stripped tree.
# Uses MIX_TEST_PARTITION=remove_auth so it never touches the developer's
# real test database. The scratch precommit runs under MIX_ENV=test (forced
# by mix.exs's `preferred_envs: [precommit: :test]`), so it only ever
# creates/migrates/drops template_phoenix_test_remove_auth -- it never reads
# config/dev.exs, so an ambient DB_PARTITION (this worktree pins one) is
# never consulted and the real dev database is never touched.
set -euo pipefail
cd "$(dirname "$0")/.."
ORIG=$(pwd)

export MIX_TEST_PARTITION=remove_auth

TMP=$(mktemp -d)
TMP2=$(mktemp -d)

cleanup() {
  status=$?
  psql -d postgres -c "DROP DATABASE IF EXISTS template_phoenix_test_remove_auth;" >/dev/null 2>&1 || true
  rm -rf "$TMP" "$TMP2"
  if [ "$status" -eq 0 ]; then
    echo "PASS: remove-auth e2e"
  else
    echo "FAIL: remove-auth e2e (status $status)" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

fail() { echo "$1" >&2; exit 1; }

echo "==> Exporting committed tree"
git -C "$ORIG" archive HEAD | tar -x -C "$TMP"
cd "$TMP"

echo "==> Running bin/remove-auth.sh"
bin/remove-auth.sh

echo "==> Asserting no auth leftovers"
if grep -riE --exclude-dir=static \
    'user_auth|user_token|user_session|user_live|passkey|webauthn|argon2|auth:begin|auth:end' \
    lib/ test/ config/ priv/ assets/js/ assets/test/ 2>/dev/null; then
  fail "Auth leftovers found (above)"
fi
if grep -rwE 'wax_|mox' mix.exs 2>/dev/null; then
  fail "Auth deps still in mix.exs"
fi

echo "==> Asserting paths"
for path in bin/remove-auth.sh bin/test-remove-auth.sh \
    .agents/skills/remove-auth .claude/skills/remove-auth \
    lib/template_phoenix/accounts.ex lib/template_phoenix_web/user_auth.ex \
    test/support/fixtures/accounts_fixtures.ex; do
  [ ! -e "$path" ] || fail "Should have been deleted: $path"
done
for path in lib/template_phoenix/health.ex lib/template_phoenix_web/router.ex bin/rename.sh; do
  [ -e "$path" ] || fail "Should still exist: $path"
done
grep -q 'get "/", PageController, :home' lib/template_phoenix_web/router.ex \
  || fail "Router lost the home route"
if grep -qE 'live_session|UserAuth|fetch_current_scope' lib/template_phoenix_web/router.ex; then
  fail "Router still references auth"
fi
# The remove-auth CI job and skill symlink only make sense while auth exists;
# both must be gone from the stripped app (the job is marker-wrapped in ci.yml,
# the symlink is in the script's delete list).
grep -q 'remove-auth:' .github/workflows/ci.yml && fail "CI still has the remove-auth job"
[ -e .claude/skills/remove-auth ] && fail "remove-auth skill symlink should not exist"
[ -L CLAUDE.md ] || fail "CLAUDE.md symlink lost"
for link in .claude/skills/*; do
  [ -L "$link" ] && [ -e "$link" ] || fail "Broken skill symlink: $link"
done

echo "==> Bootstrapping postgres role (if needed)"
psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='template_phoenix'" | grep -q 1 \
  || psql -d postgres -c "CREATE ROLE template_phoenix WITH LOGIN CREATEDB PASSWORD 'template_phoenix';"

echo "==> Full quality gate on the stripped tree"
mise trust >/dev/null 2>&1 || true
mise exec -- mix deps.get
mise exec -- mix precommit

echo "==> Asserting the lock file healed"
if grep -qE '"wax_"|"argon2_elixir"|"mox"' mix.lock; then
  fail "mix.lock still contains auth deps after precommit"
fi

echo "==> JS tests on stripped assets"
(cd assets && pnpm install --frozen-lockfile >/dev/null && pnpm test)

echo "==> Pre-flight refuses an already-stripped tree"
# remove-auth.sh deleted itself along with the rest of the auth layer; copy
# it back in from the ORIGINAL checkout (not git-show, just a plain file
# copy) to prove a second run on an already-stripped tree refuses loudly
# and deletes nothing further.
cp "$ORIG/bin/remove-auth.sh" bin/remove-auth.sh
chmod +x bin/remove-auth.sh
before=$(find . -type f | sort)
if refusal_output=$(./bin/remove-auth.sh 2>&1 >/dev/null); then
  fail "remove-auth.sh should refuse an already-stripped tree"
fi
echo "$refusal_output" | grep -q "Aborting" || fail "Refusal did not print an Aborting message"
after=$(find . -type f | sort)
# The restored script itself is the only expected diff; nothing else must move.
diff <(echo "$before") <(echo "$after") | grep -v 'bin/remove-auth.sh' | grep -q . \
  && fail "Refused run deleted or changed files besides the restored script"
rm -f bin/remove-auth.sh

echo "==> Order interaction: rename THEN remove"
git -C "$ORIG" archive HEAD | tar -x -C "$TMP2"
(
  cd "$TMP2"
  bin/rename.sh wombat_app --keep
  bin/remove-auth.sh
  if grep -riE 'passkey|webauthn|user_auth' lib/ test/ config/ 2>/dev/null; then
    echo "Leftovers after rename-then-remove" >&2
    exit 1
  fi
  mise trust >/dev/null 2>&1 || true
  mise exec -- mix deps.get
  mise exec -- mix compile --warnings-as-errors
)

echo "==> Done"
