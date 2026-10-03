#!/usr/bin/env bash
#
# Drop a partition's dev and test databases (template_phoenix_dev_<partition>
# and template_phoenix_test_<partition>). Worktrunk's pre-remove hook runs this
# on worktree removal; run it by hand when tearing down without worktrunk.
#
#   bin/drop-partition.sh <partition>
#
# The partition is passed explicitly via env(1), which overrides any .env pin,
# so the drop targets exactly the named partition even if .env was edited or
# deleted. An empty name would target the shared databases, so anything that
# isn't a snake_case name is refused rather than defaulted.
set -euo pipefail

PARTITION="${1:-}"

if [ $# -ne 1 ] || ! [[ "$PARTITION" =~ ^[a-z0-9][a-z0-9_]*$ ]]; then
  echo "Usage: bin/drop-partition.sh <partition>" >&2
  echo "  partition must be snake_case (e.g. my_branch); an empty name is refused" >&2
  echo "  because it would target the shared dev/test databases" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

mise exec -- env DB_PARTITION="$PARTITION" mix ecto.drop
mise exec -- env MIX_ENV=test MIX_TEST_PARTITION="$PARTITION" mix ecto.drop
