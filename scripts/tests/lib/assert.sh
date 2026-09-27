#!/usr/bin/env bash
# Tiny assertion helpers for dev-qual's own tests: no framework, no bats.
# Source this file; do not execute it directly.

PASS_COUNT=0
FAIL_COUNT=0

# Paths registered by mk_tmp_repo, removed by the EXIT trap below
CLEANUP=""

cleanup_tmp_dirs() {
  local dir
  for dir in $CLEANUP; do
    rm -rf "$dir"
  done
}
trap cleanup_tmp_dirs EXIT

# assert_eq <expected> <actual> <message>
assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [ "$expected" = "$actual" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $message" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# assert_contains <haystack> <needle> <message>
assert_contains() {
  local haystack="$1" needle="$2" message="$3"
  if [ "${haystack#*"$needle"}" != "$haystack" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $message" >&2
    echo "  expected to find: $needle" >&2
    echo "  in: $haystack" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# assert_not_contains <haystack> <needle> <message>
assert_not_contains() {
  local haystack="$1" needle="$2" message="$3"
  if [ "${haystack#*"$needle"}" = "$haystack" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $message" >&2
    echo "  expected NOT to find: $needle" >&2
    echo "  in: $haystack" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# assert_file <path> <message>
assert_file() {
  local path="$1" message="$2"
  if [ -e "$path" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $message" >&2
    echo "  missing: $path" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# assert_exit <expected-code> <message> <command...>
assert_exit() {
  local expected="$1" message="$2" actual
  shift 2
  actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$expected" = "$actual" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $message" >&2
    echo "  expected exit: $expected" >&2
    echo "  actual exit:   $actual" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# mk_tmp_repo: creates a git-initialised temp repo, echoes its path, and
# registers it for removal when the test process exits
mk_tmp_repo() {
  local dir
  dir="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" config user.name "dev-qual tests"
  git -C "$dir" config user.email "tests@dev-qual.local"
  git -C "$dir" config commit.gpgsign false
  CLEANUP="$CLEANUP $dir"
  echo "$dir"
}

# finish: print the summary and exit 1 if anything failed
finish() {
  echo "$PASS_COUNT passed, $FAIL_COUNT failed"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
  fi
  exit 0
}
