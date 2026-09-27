#!/usr/bin/env bash
# Reports unfinished stages of every active plan under docs/plans/. A plan
# is active when its YAML frontmatter (between the first two --- lines) has
# `status: active`; an unfinished stage is a line matching `- [ ]`.
#
# Usage: plan-status.sh [--project <dir>]
#   --project <dir>  project directory (default: its git toplevel, or cwd)
# Exit code: 1 if any unchecked stage was printed, else 0.
set -euo pipefail

PROJECT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --help|-h) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ "$PROJECT" = "." ]; then
  PROJECT="$(git -C . rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
PLANS_DIR="$PROJECT/docs/plans"
[ -d "$PLANS_DIR" ] || exit 0

# True if a plan file's frontmatter declares status: active
is_active() {
  awk '
    /^---$/ { n++; next }
    n == 1 && /^status:[ \t]*active[ \t]*$/ { print "yes"; exit }
    n >= 2 { exit }
  ' "$1"
}

FOUND=0
for plan in "$PLANS_DIR"/*.md; do
  [ -e "$plan" ] || continue
  [ "$(is_active "$plan")" = "yes" ] || continue
  UNCHECKED="$(grep -E '^[[:space:]]*- \[ \]' "$plan" || true)"
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
