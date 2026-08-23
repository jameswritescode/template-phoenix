#!/usr/bin/env bash
#
# Rename this template to your project's name.
#
#   bin/rename.sh my_cool_app          # renames and deletes this script
#   bin/rename.sh my_cool_app --keep   # renames and keeps this script
#
set -euo pipefail

OLD_SNAKE="template_phoenix"
OLD_PASCAL="TemplatePhoenix"
OLD_KEBAB="template-phoenix"

KEEP=0
NAME=""
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    -*) echo "Unknown option: $arg" >&2; exit 1 ;;
    *) NAME="$arg" ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "Usage: bin/rename.sh <new_app_name> [--keep]" >&2
  echo "  new_app_name must be snake_case, e.g. my_cool_app" >&2
  exit 1
fi

if ! [[ "$NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "Error: '$NAME' is not snake_case (lowercase letters, digits, underscores; must start with a letter)" >&2
  exit 1
fi

SNAKE="$NAME"
PASCAL=$(printf '%s' "$SNAKE" | awk -F_ '{for (i = 1; i <= NF; i++) printf "%s%s", toupper(substr($i, 1, 1)), substr($i, 2)}')
KEBAB="${SNAKE//_/-}"

cd "$(dirname "$0")/.."

# BSD (macOS) and GNU sed disagree on -i syntax.
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

# 1. Replace occurrences inside files.
grep -rl \
  --exclude-dir=.git \
  --exclude-dir=_build \
  --exclude-dir=deps \
  --exclude-dir=node_modules \
  --exclude-dir=.elixir_ls \
  -e "$OLD_SNAKE" -e "$OLD_PASCAL" -e "$OLD_KEBAB" . 2>/dev/null \
  | grep -v 'bin/rename\.sh' \
  | while IFS= read -r f; do
      sedi -e "s/$OLD_PASCAL/$PASCAL/g" -e "s/$OLD_SNAKE/$SNAKE/g" -e "s/$OLD_KEBAB/$KEBAB/g" "$f"
    done

# 2. Rename files and directories (deepest paths first).
find . \( -path ./.git -o -path ./_build -o -path ./deps -o -path '*/node_modules' \) -prune \
  -o -name "*${OLD_SNAKE}*" -print \
  | sort -r \
  | while IFS= read -r p; do
      base=$(basename "$p")
      mv "$p" "$(dirname "$p")/${base//$OLD_SNAKE/$SNAKE}"
    done

echo "Renamed: $OLD_SNAKE -> $SNAKE, $OLD_PASCAL -> $PASCAL, $OLD_KEBAB -> $KEBAB"

if [ "$KEEP" -eq 0 ]; then
  rm -- bin/rename.sh
  echo "Removed bin/rename.sh (use --keep to retain it)"
fi

echo "Done. Review with: git status && git diff"
