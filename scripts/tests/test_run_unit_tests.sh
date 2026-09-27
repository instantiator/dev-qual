#!/usr/bin/env bash
# Tests for scripts/run-unit-tests.sh, dev-qual's own test runner.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# Build a fake repo with the same scripts/ layout run-unit-tests.sh expects,
# so it locates itself relative to its own path and finds a "repo root" of
# just the fixture: mk_fake_repo
mk_fake_repo() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  CLEANUP="$CLEANUP $dir"
  mkdir -p "$dir/scripts/lib" "$dir/tests" "$dir/tests/lib"
  cp "$REPO_ROOT/scripts/run-unit-tests.sh" "$dir/scripts/run-unit-tests.sh"
  cp "$REPO_ROOT/scripts/lib/common.sh" "$dir/scripts/lib/common.sh"
  echo "$dir"
}

# A PATH containing only the tools run-unit-tests.sh needs, with no dotnet
mk_restricted_path() {
  local bindir tool
  bindir="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-bin.XXXXXX")"
  CLEANUP="$CLEANUP $bindir"
  for tool in bash env find sort sed grep basename dirname cat mkdir rm tr wc head; do
    ln -s "$(command -v "$tool")" "$bindir/$tool"
  done
  echo "$bindir"
}

# --- a passing test file: PASS, exit 0 ---
REPO1="$(mk_fake_repo)"
cat >"$REPO1/tests/test_ok.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
CODE=0; OUT="$(bash "$REPO1/scripts/run-unit-tests.sh" 2>&1)" || CODE=$?
assert_eq 0 "$CODE" "passing test file exits 0"
assert_contains "$OUT" "PASS" "passing test file reports PASS"
assert_contains "$OUT" "tests/test_ok.sh" "result names the repo-relative path"

# --- a failing test file: FAIL, exit 1 ---
REPO2="$(mk_fake_repo)"
cat >"$REPO2/tests/test_bad.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
CODE=0; OUT="$(bash "$REPO2/scripts/run-unit-tests.sh" 2>&1)" || CODE=$?
assert_eq 1 "$CODE" "failing test file exits 1"
assert_contains "$OUT" "FAIL" "failing test file reports FAIL"
assert_contains "$OUT" "re-run:" "failing test file's result includes a re-run hint"

# --- a .cs.sh test with dotnet absent: SKIP, exit 0; --strict: exit 1 ---
REPO3="$(mk_fake_repo)"
cat >"$REPO3/tests/test_x.cs.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
RESTRICTED_PATH="$(mk_restricted_path)"
CODE=0; OUT="$(PATH="$RESTRICTED_PATH" bash "$REPO3/scripts/run-unit-tests.sh" 2>&1)" || CODE=$?
assert_eq 0 "$CODE" "cs.sh test skips (not fails) without dotnet"
assert_contains "$OUT" "SKIP" "cs.sh test reports SKIP without dotnet"
assert_exit 1 "--strict fails the run when a test was skipped" \
  env PATH="$RESTRICTED_PATH" bash "$REPO3/scripts/run-unit-tests.sh" --strict

# --- files under tests/lib/ are not run ---
REPO4="$(mk_fake_repo)"
cat >"$REPO4/tests/lib/test_helper.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
CODE=0; OUT="$(bash "$REPO4/scripts/run-unit-tests.sh" 2>&1)" || CODE=$?
assert_eq 0 "$CODE" "tests/lib/ files are ignored, so the run still passes"
assert_not_contains "$OUT" "tests/lib/test_helper.sh" "tests/lib/ file is not listed as a result"

# --- --filter narrows the set ---
REPO5="$(mk_fake_repo)"
cat >"$REPO5/tests/test_one.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$REPO5/tests/test_two.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
CODE=0; OUT="$(bash "$REPO5/scripts/run-unit-tests.sh" --filter test_one 2>&1)" || CODE=$?
assert_eq 0 "$CODE" "--filter run exits 0"
assert_contains "$OUT" "test_one.sh" "--filter keeps the matching file"
assert_not_contains "$OUT" "test_two.sh" "--filter excludes the non-matching file"

finish
