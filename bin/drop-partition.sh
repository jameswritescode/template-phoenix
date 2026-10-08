#!/usr/bin/env bash
#
# Drop a partition's dev and test databases (template_phoenix_dev_<partition>
# and template_phoenix_test_<partition>). Worktrunk's pre-remove hook runs this
# on worktree removal; run it by hand when tearing down without worktrunk.
#
#   bin/drop-partition.sh <partition>
#
# <partition> is the suffix (e.g. my_branch), as pinned in DB_PARTITION — not
# the full database name. Worktrunk's sanitize_db can produce a leading
# underscore (a branch like 123-fix becomes _123_fix_xyz), so that is valid.
#
# Each drop pins MIX_ENV and its partition explicitly via env(1), overriding
# any .env pin or inherited MIX_ENV, so it targets exactly the named
# partition. An empty name would target the shared databases, so it is
# refused rather than defaulted.
set -euo pipefail

PARTITION="${1:-}"

usage() {
  echo "Usage: bin/drop-partition.sh <partition>" >&2
  echo "  partition is the DB_PARTITION suffix: lowercase letters, digits, and" >&2
  echo "  underscores (e.g. my_branch). An empty name is refused because it" >&2
  echo "  would target the shared dev/test databases." >&2
  exit 1
}

if [ $# -ne 1 ] || ! [[ "$PARTITION" =~ ^[a-z0-9_]+$ ]]; then
  usage
fi

case "$PARTITION" in
  template_phoenix_dev_* | template_phoenix_test_*)
    echo "bin/drop-partition.sh: '$PARTITION' is a full database name." >&2
    echo "  Pass only the partition suffix, e.g. ${PARTITION#template_phoenix_*_}" >&2
    exit 1
    ;;
esac

cd "$(dirname "$0")/.."

mise exec -- env MIX_ENV=dev DB_PARTITION="$PARTITION" mix ecto.drop
mise exec -- env MIX_ENV=test MIX_TEST_PARTITION="$PARTITION" mix ecto.drop
