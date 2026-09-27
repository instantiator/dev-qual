#!/usr/bin/env bash
# dev-qual's own unit test runner: tests the scripts in this repo, not a
# consumer project. Follows the scripts/run-<suite>-tests.sh convention, so
# both `scripts/run-tests.sh unit` and `npm test` reach it.
#
# Discovers test files under any directory named `tests` (skipping .git,
# node_modules, dist, prompts, and tests/lib or tests/fixtures) and runs each
# by its naming convention:
#   test_*.sh       (not test_*.cs.sh) -> bash <file>
#   *.test.mjs                         -> node --test <file>   (needs node)
#   test_*.py                          -> python3 -m unittest  (needs python3)
#   test_*.cs.sh                       -> bash <file>          (needs dotnet)
#
# Usage: run-unit-tests.sh [--strict] [--filter <substring>]
#   --strict           a SKIP (missing toolchain) counts as failure
#   --filter <string>  only run test files whose path contains <string>
# Exit code: 1 if any test FAILs (or, with --strict, any test SKIPs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

STRICT=0; FILTER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --filter) FILTER="${2:?--filter needs a substring}"; shift ;;
    --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

cd "$REPO_ROOT"

# Find candidate test files under any `tests` directory, excluding
# infrastructure paths and shared helper/fixture directories
FILES="$(find . \
  -not -path './.git/*' -not -path './node_modules/*' \
  -not -path './dist/*' -not -path './prompts/*' \
  -path '*/tests/*' -not -path '*/tests/lib/*' -not -path '*/tests/fixtures/*' \
  \( -name 'test_*.sh' -o -name '*.test.mjs' -o -name 'test_*.py' \) \
  | sort)"

if [ -n "$FILTER" ]; then
  FILES="$(echo "$FILES" | grep -F "$FILTER" || true)"
fi

if [ -z "$FILES" ]; then
  echo "run-unit-tests: no test files found under any tests/ directory."
  exit 0
fi

SKIPPED=0

# Run one test file per its naming convention: run_one <file>
run_one() {
  local f="$1" rel cmd
  rel="${f#./}"
  case "$f" in
    *test_*.cs.sh)
      if ! has_cmd dotnet; then
        record_result "$rel" SKIP "install dotnet (mac: brew install dotnet-sdk)"
        SKIPPED=1
        return 0
      fi
      cmd="bash $f"
      if bash "$f"; then record_result "$rel" PASS; else record_result "$rel" FAIL "re-run: $cmd"; fi
      ;;
    *test_*.sh)
      cmd="bash $f"
      if bash "$f"; then record_result "$rel" PASS; else record_result "$rel" FAIL "re-run: $cmd"; fi
      ;;
    *.test.mjs)
      if ! has_cmd node; then
        record_result "$rel" SKIP "install node"
        SKIPPED=1
        return 0
      fi
      cmd="node --test $f"
      if node --test "$f"; then record_result "$rel" PASS; else record_result "$rel" FAIL "re-run: $cmd"; fi
      ;;
    *test_*.py)
      if ! has_cmd python3; then
        record_result "$rel" SKIP "install python3"
        SKIPPED=1
        return 0
      fi
      local dir base
      dir="$(dirname "$f")"
      base="$(basename "$f" .py)"
      cmd="(cd $dir && python3 -m unittest $base)"
      if (cd "$dir" && python3 -m unittest "$base"); then
        record_result "$rel" PASS
      else
        record_result "$rel" FAIL "re-run: $cmd"
      fi
      ;;
  esac
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  run_one "$f"
done <<EOF
$FILES
EOF

RESULT=0
report_results || RESULT=$?

if [ "$STRICT" = 1 ] && [ "$SKIPPED" = 1 ]; then
  exit 1
fi
exit "$RESULT"
