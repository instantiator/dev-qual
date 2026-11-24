#!/usr/bin/env bash
# Scaffolds a new ADR in <project>/docs/ADRs/ with the next free number.
# Usage: adr-new.sh "Title of the decision" [--project <dir>]
set -euo pipefail

TITLE="${1:-}"
if [ -z "$TITLE" ] || [ "$TITLE" = "--help" ]; then
  sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'
  [ -n "$TITLE" ]; exit $?
fi
shift
PROJECT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

ADR_DIR="$PROJECT/docs/ADRs"
mkdir -p "$ADR_DIR"

# Next number: highest existing NNNN prefix + 1
LAST="$(find "$ADR_DIR" -name '[0-9][0-9][0-9][0-9]-*.md' | sed 's|.*/||; s|-.*||' | sort -n | tail -1)"
# 10# reads the number as decimal: bash would read 0008 and 0009 as invalid octal
NEXT=$(printf '%04d' $(( 10#${LAST:-0} + 1 )))

# Slug: lowercase, alphanumerics and hyphens only
SLUG="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-//; s/-$//')"
FILE="$ADR_DIR/$NEXT-$SLUG.md"

cat >"$FILE" <<EOF
# ADR $NEXT: $TITLE

- Status: Proposed
- Date: $(date +%Y-%m-%d)

## Context

What problem are we solving, and under what constraints?

## Options considered

1. **Option A** — trade-offs
2. **Option B** — trade-offs

## Decision

What we chose and why.

## Consequences

What this makes easier, and what it makes harder.
EOF

echo "Created $FILE"
echo "Next: fill it in, then add it to docs/index.md."
