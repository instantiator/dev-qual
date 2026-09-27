#!/usr/bin/env bash
# Lints this repository's own documentation: frontmatter presence, size
# budgets, index/description sync, and dead relative links.
# Run from anywhere; it locates the repo relative to itself.
#
# Usage: lint-docs.sh
# Exit code: 1 if any problem is found, else 0.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROBLEMS=0

problem() {
  echo "PROBLEM: $1"
  PROBLEMS=$((PROBLEMS + 1))
}

# Extract a frontmatter field value: fm_field <file> <field>
fm_field() {
  awk -v field="$2" '
    /^---$/ { n++; next }
    n == 1 && $0 ~ "^" field ":" { sub("^" field ":[ ]*", ""); print; exit }
    n >= 2 { exit }
  ' "$1"
}

# Line budget per frontmatter type
budget_for_type() {
  case "$1" in
    index) echo 40 ;;
    standard) echo 60 ;;
    process|reference) echo 80 ;;
    skill) echo 100 ;;
    *) echo 0 ;;
  esac
}

# The index.md expected to list a given doc (empty for root indexes)
index_for() {
  local file="$1" rel="${1#"$REPO"/}"
  case "$rel" in
    guidance/index.md|skills/index.md) echo "" ;;
    guidance/*/index.md) echo "$REPO/guidance/index.md" ;;
    guidance/languages/*/*.md) echo "$REPO/guidance/languages/index.md" ;;
    skills/*/SKILL.md) echo "$REPO/skills/index.md" ;;
    *) echo "$(dirname "$file")/index.md" ;;
  esac
}

# Check all relative links in a file resolve to existing paths
check_links() {
  local file="$1" dir link target
  dir="$(dirname "$file")"
  # Extract (...) targets of markdown links, drop external links and pure anchors
  # grep exits 1 on files with no links; that's fine, not an error
  { grep -oE '\]\([^)]+\)' "$file" 2>/dev/null || true; } | sed 's/^](//; s/)$//' | while read -r link; do
    case "$link" in
      http://*|https://*|"#"*|mailto:*) continue ;;
    esac
    target="$dir/${link%%#*}"
    if [ ! -e "$target" ]; then
      echo "PROBLEM: $file — dead link: $link"
    fi
  done
}

# Governed docs: everything under guidance/ and skills/ (whichever exist)
SCAN_DIRS=""
for d in "$REPO/guidance" "$REPO/skills"; do
  [ -d "$d" ] && SCAN_DIRS="$SCAN_DIRS $d"
done
# shellcheck disable=SC2086
DOCS="$(find $SCAN_DIRS -name '*.md' -not -path '*/tools/*' | sort)"

for file in $DOCS; do
  lines="$(wc -l <"$file" | tr -d ' ')"
  type="$(fm_field "$file" type)"
  desc="$(fm_field "$file" description)"

  # Frontmatter must exist with the routing fields
  if [ -z "$type" ] || [ -z "$desc" ] || [ -z "$(fm_field "$file" title)" ]; then
    problem "$file — missing frontmatter (type/title/description)"
    continue
  fi

  # Size budget by type
  budget="$(budget_for_type "$type")"
  if [ "$budget" = 0 ]; then
    problem "$file — unknown type '$type'"
  elif [ "$lines" -gt "$budget" ]; then
    problem "$file — $lines lines exceeds the $budget-line budget for type '$type'"
  fi

  # The doc's description must appear verbatim in its index (routing sync)
  index="$(index_for "$file")"
  if [ -n "$index" ]; then
    if [ ! -f "$index" ]; then
      problem "$file — expected index $index does not exist"
    elif ! grep -qF "$desc" "$index"; then
      problem "$file — description not found in $index (keep them identical)"
    fi
  fi
done

# Dead-link check across governed docs (subshell output, so count via wc)
LINK_PROBLEMS="$(for f in $DOCS; do check_links "$f"; done)"
if [ -n "$LINK_PROBLEMS" ]; then
  echo "$LINK_PROBLEMS"
  PROBLEMS=$((PROBLEMS + $(echo "$LINK_PROBLEMS" | wc -l | tr -d ' ')))
fi

# Entry files: no frontmatter required, but the 30-line budget is hard
for file in "$REPO"/agents-files/*/*.md; do
  [ -e "$file" ] || continue
  lines="$(wc -l <"$file" | tr -d ' ')"
  if [ "$lines" -gt 30 ]; then
    problem "$file — $lines lines exceeds the 30-line budget for entry files"
  fi
done

echo ""
if [ "$PROBLEMS" = 0 ]; then
  echo "lint-docs: OK — all governed docs have frontmatter, fit their budgets, and link cleanly."
else
  echo "lint-docs: $PROBLEMS problem(s) found."
  exit 1
fi
