#!/usr/bin/env bash
#
# Removes the authentication layer (accounts, sessions, passkeys) from this
# template: deletes auth-owned files and strips every `auth:begin`/`auth:end`
# region from shared files. Verified end to end by bin/test-remove-auth.sh
# (also run in CI). Pass --keep to retain this script and its e2e.
#
# After running: mix setup && mix precommit
# (precommit's `deps.unlock --unused` prunes the stale wax_/argon2/mox lock
# entries; nothing reads them before that.)
set -euo pipefail

KEEP=false
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=true ;;
    *) echo "Unknown option: $arg (only --keep is supported)" >&2; exit 1 ;;
  esac
done

cd "$(dirname "$0")/.."

APP=$(sed -n 's/^ *app: :\([a-z0-9_]*\),.*/\1/p' mix.exs | head -1)
if [ -z "$APP" ]; then
  echo "Could not derive the app name from mix.exs" >&2
  exit 1
fi

DELETE_PATHS=(
  "lib/$APP/accounts.ex"
  "lib/$APP/accounts"
  "lib/${APP}_web/user_auth.ex"
  "lib/${APP}_web/controllers/user_session_controller.ex"
  "lib/${APP}_web/live/user_live"
  "test/$APP/accounts_test.exs"
  "test/$APP/accounts"
  "test/$APP/auth_markers_test.exs"
  "test/${APP}_web/user_auth_test.exs"
  "test/${APP}_web/controllers/user_session_controller_test.exs"
  "test/${APP}_web/live/user_live"
  "test/support/fixtures/accounts_fixtures.ex"
  "test/support/fake_webauthn.ex"
  "assets/js/webauthn_codec.js"
  "assets/js/hooks/passkey.js"
  "assets/test/webauthn_codec.test.js"
  ".agents/skills/remove-auth"
  ".claude/skills/remove-auth"
)

MARKED_FILES=(
  "mix.exs"
  "lib/${APP}_web/router.ex"
  "lib/${APP}_web/components/layouts.ex"
  "lib/${APP}_web/telemetry.ex"
  "assets/js/app.js"
  "test/support/conn_case.ex"
  "test/test_helper.exs"
  "config/config.exs"
  "config/test.exs"
  "AGENTS.md"
  "README.md"
  ".github/workflows/ci.yml"
)

shopt -s nullglob
MIGRATIONS=(
  priv/repo/migrations/*_create_users_auth_tables.exs
  priv/repo/migrations/*_add_users_passkeys.exs
)
shopt -u nullglob

# Pre-flight: all-or-nothing. Nothing is deleted unless everything checks out.
problems=0
for path in "${DELETE_PATHS[@]}"; do
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    echo "Missing expected auth path: $path" >&2
    problems=$((problems + 1))
  fi
done
for file in "${MARKED_FILES[@]}"; do
  if ! grep -q 'auth:begin' "$file" 2>/dev/null; then
    echo "No auth markers found in: $file" >&2
    problems=$((problems + 1))
  fi
done
if [ "${#MIGRATIONS[@]}" -ne 2 ]; then
  echo "Expected exactly 2 auth migrations, found ${#MIGRATIONS[@]}" >&2
  problems=$((problems + 1))
fi
if [ "$problems" -ne 0 ]; then
  echo "Aborting: $problems problem(s) found; nothing was deleted." >&2
  exit 1
fi

echo "==> Deleting auth-owned files"
for path in "${DELETE_PATHS[@]}"; do
  rm -rf "$path"
done
rm -f "${MIGRATIONS[@]}"

echo "==> Stripping auth-marked regions"
strip_markers() {
  local file=$1 tmp
  tmp=$(mktemp)
  awk '/auth:begin/{skip=1} /auth:end/{skip=0; next} !skip' "$file" \
    | awk 'BEGIN{blank=0} /^[[:space:]]*$/{blank++; if (blank > 1) next; print; next} {blank=0; print}' \
    > "$tmp"
  mv "$tmp" "$file"
}
for file in "${MARKED_FILES[@]}"; do
  strip_markers "$file"
done

if ! $KEEP; then
  rm -f bin/test-remove-auth.sh
  rm -f bin/remove-auth.sh
fi

cat <<'EOF'

Auth layer removed. Next steps:

  mix setup
  mix precommit   # also prunes stale wax_/argon2/mox entries from mix.lock

Review the result with: git status && git diff
EOF
