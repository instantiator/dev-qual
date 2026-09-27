#!/usr/bin/env bash
# Finds markdown docs that probably need updating after code changes.
# Lists candidates that mention changed files or removed declarations.
#
# Usage: stale-docs.sh [--base <ref>] [--project <dir>]
# Output: each match as <doc>:<line> — mentions <thing>, sorted and deduped.
# Exit code: 0 if complete (hits or none), 2 if bad args or not a git repo.
set -euo pipefail

BASE="HEAD"
PROJECT=""

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:?--base needs a commit ref}"; shift ;;
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --help|-h) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# Default project to current directory's git toplevel
if [ -z "$PROJECT" ]; then
  PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "stale-docs.sh: not a git repository" >&2
    exit 2
  }
fi

cd "$PROJECT"

# Ensure we have a git repo
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "stale-docs.sh: $PROJECT is not a git repository" >&2
  exit 2
fi

# Validate that the base ref exists
if ! git rev-parse "$BASE" >/dev/null 2>&1; then
  echo "stale-docs.sh: invalid base ref: $BASE" >&2
  exit 2
fi

# Collect things to search for
things=""

# Get diff output for processing
diff_status="$(git diff --name-status -M "$BASE" -- '*' 2>/dev/null || true)"

# 1. Paths and basenames of changed non-.md files (skip added files)
# We process files that are modified, deleted, or renamed (not added)
while IFS= read -r line; do
  [ -z "$line" ] && continue

  # Extract status (first char) and path
  status="${line%%	*}"
  status_char="${status:0:1}"

  # Skip added files (A)
  if [ "$status_char" = "A" ]; then
    continue
  fi

  # Extract path
  if [ "$status_char" = "R" ]; then
    # For renames, use old path (second field in "R<score> old new")
    rest="${line#R*	}"
    path="${rest%	*}"
  else
    # For other statuses, path is after the tab
    path="${line#?	}"
  fi

  # Skip .md files
  if [ "${path%.md}" = "$path" ]; then
    # Add the full path and its basename
    things="$things$path
"
    basename="${path##*/}"
    if [ "$basename" != "$path" ]; then
      things="$things$basename
"
    fi
  fi
done <<EOF
$diff_status
EOF

# 2. Extract identifier names from removed lines in non-.md file diffs
# Use git diff to find deleted lines, then extract patterns
diff_output="$(git diff -U0 "$BASE" -- ':!*.md' 2>/dev/null || true)"

# Keep a removed declaration's name if it is at least 4 chars and looks like
# code (an underscore, a digit, or an inner capital): plain lowercase words
# such as "existing" also match ordinary prose and drown the report.
extract_name() {
  local name="$1"
  case "$name" in
    *_*|*[0-9]*|?*[A-Z]*) ;;
    *) return 0 ;;
  esac
  if [ ${#name} -ge 4 ]; then
    things="$things$name
"
  fi
}

# Process lines that start with - (removed content, but not --- markers)
# Extract function/class/const names and keep if >= 4 chars
while IFS= read -r line; do
  # Skip diff markers and empty lines
  [ -z "$line" ] && continue
  [ "${line:0:3}" = "---" ] && continue
  [ "${line:0:3}" = "+++" ] && continue

  # Only process lines starting with single -
  [ "${line:0:1}" != "-" ] && continue

  # Remove the leading -
  content="${line:1}"

  # Pattern: function NAME {
  name="$(echo "$content" | grep -oE 'function [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^function //' || true)"
  extract_name "$name"

  # Pattern: NAME() {
  name="$(echo "$content" | grep -oE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)' | sed 's/()$//' || true)"
  extract_name "$name"

  # Pattern: def NAME(
  name="$(echo "$content" | grep -oE 'def [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^def //' || true)"
  extract_name "$name"

  # Pattern: class NAME
  name="$(echo "$content" | grep -oE 'class [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^class //' || true)"
  extract_name "$name"

  # Pattern: interface NAME
  name="$(echo "$content" | grep -oE 'interface [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^interface //' || true)"
  extract_name "$name"

  # Pattern: type NAME =
  name="$(echo "$content" | grep -oE 'type [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^type //' || true)"
  extract_name "$name"

  # Pattern: const NAME =
  name="$(echo "$content" | grep -oE 'const [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^const //' || true)"
  extract_name "$name"

  # Pattern: export function NAME
  name="$(echo "$content" | grep -oE 'export function [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^export function //' || true)"
  extract_name "$name"

  # Pattern: export const NAME =
  name="$(echo "$content" | grep -oE 'export const [a-zA-Z_][a-zA-Z0-9_]*' | sed 's/^export const //' || true)"
  extract_name "$name"
done <<EOF
$diff_output
EOF

# Deduplicate things
things="$(echo "$things" | grep -v '^$' | sort -u || true)"

# Find all markdown files (tracked and untracked, excluding node_modules, .git, dist)
find_markdown_files() {
  find . \
    -type f -name "*.md" \
    ! -path './node_modules/*' \
    ! -path './.git/*' \
    ! -path './dist/*' \
    2>/dev/null | sed 's|^\./||'
}

md_files="$(find_markdown_files)"

# Search for mentions in markdown files
results=""
while IFS= read -r thing; do
  [ -z "$thing" ] && continue

  while IFS= read -r md_file; do
    [ -z "$md_file" ] && continue

    # Search with grep -nF (fixed string, no regex)
    grep_output="$(grep -nF "$thing" "$md_file" 2>/dev/null || true)"

    while IFS= read -r grep_line; do
      [ -z "$grep_line" ] && continue

      # Extract line number (before first colon)
      line_num="${grep_line%%:*}"
      results="$results$md_file:$line_num — mentions $thing
"
    done <<EOF
$grep_output
EOF
  done <<EOF
$md_files
EOF
done <<EOF
$things
EOF

# Sort and deduplicate results
results="$(echo "$results" | grep -v '^$' | sort -u || true)"

# Print results or message
if [ -z "$results" ]; then
  echo "stale-docs: no docs mention the changed files or removed declarations."
  exit 0
else
  echo "$results"
  exit 0
fi
