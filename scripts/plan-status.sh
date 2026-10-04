#!/usr/bin/env bash
# Reports unfinished stages of every active plan. Plans are the files
# matching PLANS_GLOB (relative to the project; from the environment, else
# the project's .dev-qual.env, else docs/plans/*.md). A plan with YAML
# frontmatter is active when it has `status: active`; a plan without
# frontmatter is always active. An unfinished stage is a `- [ ]` line,
# optionally as a markdown heading (`### - [ ] 2. ...`).
#
# Usage: plan-status.sh [--project <dir>]
#   --project <dir>  project directory (default: its git toplevel, or cwd)
# Exit code: 1 if any unchecked stage was printed, else 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PROJECT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --help|-h) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ "$PROJECT" = "." ]; then
  PROJECT="$(git -C . rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
PLANS_GLOB="${PLANS_GLOB:-$(state_value "$PROJECT/.dev-qual.env" PLANS_GLOB)}"
PLANS_GLOB="${PLANS_GLOB:-docs/plans/*.md}"

# True if a plan is active: no frontmatter, or frontmatter with status: active
is_active() {
  awk '
    NR == 1 && !/^---$/ { print "yes"; exit }
    /^---$/ { n++; next }
    n == 1 && /^status:[ \t]*active[ \t]*$/ { print "yes"; exit }
    n >= 2 { exit }
  ' "$1"
}

FOUND=0
# Split only on newlines, so the glob may contain spaces and still expands.
OLD_IFS="$IFS"; IFS=$'\n'
# shellcheck disable=SC2206 # deliberate glob expansion of PLANS_GLOB
PLANS=($PROJECT/$PLANS_GLOB)
IFS="$OLD_IFS"
for plan in "${PLANS[@]}"; do
  [ -e "$plan" ] || continue
  [ "$(is_active "$plan")" = "yes" ] || continue
  UNCHECKED="$(grep -E '^[[:space:]]*(#+[[:space:]]+)?- \[ \]' "$plan" || true)"
  [ -n "$UNCHECKED" ] || continue
  echo "$plan"
  while IFS= read -r stage; do
    echo "  $stage"
  done <<EOF
$UNCHECKED
EOF
  FOUND=1
done

[ "$FOUND" = 0 ]
