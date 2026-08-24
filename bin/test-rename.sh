#!/usr/bin/env bash
#
# End-to-end test for bin/rename.sh.
#
# Exports the committed tree (git archive HEAD), renames it to wombat_app,
# and proves the result is a clean, working application:
#   - no leftover template name variants anywhere
#   - files/dirs renamed, rename.sh self-deleted, symlinks intact
#   - mix deps.get + compile --warnings-as-errors + mix test all pass
#
# Needs Postgres (uses PG* env vars if set; creates a wombat_app role).
# Run from anywhere: bin/test-rename.sh
#
set -euo pipefail

NAME="wombat_app"
PASCAL="WombatApp"
KEBAB="wombat-app"

cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
cleanup() {
  status=$?
  psql -d postgres -c "DROP DATABASE IF EXISTS ${NAME}_dev" >/dev/null 2>&1 || true
  psql -d postgres -c "DROP DATABASE IF EXISTS ${NAME}_test" >/dev/null 2>&1 || true
  rm -rf "$TMP"
  if [ $status -eq 0 ]; then echo "PASS: rename e2e"; else echo "FAIL: rename e2e (status $status)"; fi
  exit $status
}
trap cleanup EXIT

echo "==> Exporting committed tree to $TMP"
git archive HEAD | tar -x -C "$TMP"
cd "$TMP"

echo "==> Running bin/rename.sh $NAME"
bin/rename.sh "$NAME"

echo "==> Checking for leftover template names"
leftovers=$(grep -riE --exclude=test-rename.sh "template[_-]phoenix|templatephoenix" . || true)
if [ -n "$leftovers" ]; then
  echo "FAIL: leftover template names:" >&2
  echo "$leftovers" >&2
  exit 1
fi

echo "==> Checking renamed paths and structure"
for path in lib/${NAME}.ex lib/${NAME}_web.ex lib/${NAME} lib/${NAME}_web \
  lib/${NAME}/health.ex lib/${NAME}_web/telemetry.ex; do
  [ -e "$path" ] || { echo "FAIL: expected $path to exist" >&2; exit 1; }
done
[ ! -e bin/rename.sh ] || { echo "FAIL: bin/rename.sh should self-delete" >&2; exit 1; }
grep -q "$KEBAB" assets/package.json || { echo "FAIL: assets/package.json not renamed" >&2; exit 1; }
grep -q "$PASCAL" mix.exs || { echo "FAIL: mix.exs module not renamed" >&2; exit 1; }

echo "==> Checking symlinks survived the rename"
[ -L CLAUDE.md ] || { echo "FAIL: CLAUDE.md is no longer a symlink" >&2; exit 1; }
for link in .claude/skills/*; do
  [ -L "$link" ] || { echo "FAIL: $link is no longer a symlink" >&2; exit 1; }
  [ -e "$link" ] || { echo "FAIL: $link is a dangling symlink" >&2; exit 1; }
done

echo "==> Ensuring Postgres role ${NAME} exists"
psql -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${NAME}'" | grep -q 1 ||
  psql -d postgres -c "CREATE ROLE ${NAME} WITH LOGIN CREATEDB PASSWORD '${NAME}'"

echo "==> Building and testing the renamed app"
mise trust >/dev/null 2>&1 || true
mise exec -- mix deps.get
mise exec -- mix compile --warnings-as-errors
mise exec -- mix test

echo "==> Done"
