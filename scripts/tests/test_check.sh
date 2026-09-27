#!/usr/bin/env bash
# Tests for check.sh's file discovery.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# --- 1. a tree big enough that `find | grep -q` would die of SIGPIPE still
#        gets its markdown stage (PASS, FAIL, or SKIP when markdownlint is
#        absent — but never silently dropped) ---
PROJ="$(mk_tmp_repo)"
mkdir -p "$PROJ/docs"
for i in $(seq 1 2000); do
  echo "# Doc $i" >"$PROJ/docs/a-long-file-name-to-fill-the-pipe-buffer-quickly-$i.md"
done
OUT="$(bash "$REPO_ROOT/scripts/check.sh" --fast --project "$PROJ" 2>&1 || true)"
assert_contains "$(echo "$OUT" | sed -n '/== Results/,$p')" "markdownlint" "markdownlint stage runs in a large tree"

finish
