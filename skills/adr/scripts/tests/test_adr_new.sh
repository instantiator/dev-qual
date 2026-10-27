#!/usr/bin/env bash
# Tests for skills/adr/scripts/adr-new.sh: numbering continues past ADRs
# whose zero-padded numbers aren't valid octal (0008, 0009).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../../../scripts/tests/lib/assert.sh
. "$REPO_ROOT/scripts/tests/lib/assert.sh"

ADR_NEW="$REPO_ROOT/skills/adr/scripts/adr-new.sh"

# --- 1. the first ADR is 0001 ---
PROJ="$(mk_tmp_repo)"
bash "$ADR_NEW" "First choice" --project "$PROJ" >/dev/null
assert_file "$PROJ/docs/ADRs/0001-first-choice.md" "first ADR is numbered 0001"

# --- 2. after 0008 comes 0009, and after 0009 comes 0010 ---
touch "$PROJ/docs/ADRs/0008-eighth.md"
bash "$ADR_NEW" "Ninth" --project "$PROJ" >/dev/null
assert_file "$PROJ/docs/ADRs/0009-ninth.md" "after 0008 comes 0009"
bash "$ADR_NEW" "Tenth" --project "$PROJ" >/dev/null
assert_file "$PROJ/docs/ADRs/0010-tenth.md" "after 0009 comes 0010"
assert_contains "$(cat "$PROJ/docs/ADRs/0010-tenth.md")" "# ADR 0010: Tenth" "heading carries the number"

finish
