#!/usr/bin/env bash
# Tests for scripts/check-updates.sh against a synthetic upstream: a bare
# "origin" repo plus a clone carrying a copy of the WORKING TREE's
# check-updates.sh (so uncommitted edits are what's tested), at the same
# scripts/check-updates.sh path check-updates.sh expects relative to itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# Build a bare "origin" plus a clone with check-updates.sh installed at the
# same relative path, one initial commit: mk_synthetic_upstream
mk_synthetic_upstream() {
  local bare clone
  bare="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  CLEANUP="$CLEANUP $bare"
  git init -q --bare "$bare"
  clone="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  CLEANUP="$CLEANUP $clone"
  git clone -q "$bare" "$clone"
  git -C "$clone" config user.name "dev-qual tests"
  git -C "$clone" config user.email "tests@dev-qual.local"
  git -C "$clone" config commit.gpgsign false
  mkdir -p "$clone/scripts"
  cp "$REPO_ROOT/scripts/check-updates.sh" "$clone/scripts/check-updates.sh"
  git -C "$clone" add scripts/check-updates.sh
  git -C "$clone" commit -q -m "initial"
  git -C "$clone" push -q origin HEAD
  (cd "$clone" && pwd)
}

# --- 1. up to date, --quiet prints nothing, exit 0 ---
CLONE1="$(mk_synthetic_upstream)"
CODE1=0
OUT1="$(bash "$CLONE1/scripts/check-updates.sh" --quiet)" || CODE1=$?
assert_eq "" "$OUT1" "up to date, --quiet: no output"
assert_eq 0 "$CODE1" "up to date, --quiet: exit 0"

# --- 2. upstream has 2 new commits, fetched: reports the count ---
CLONE2="$(mk_synthetic_upstream)"
BARE2="$(git -C "$CLONE2" remote get-url origin)"
PUSHER2="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $PUSHER2"
git clone -q "$BARE2" "$PUSHER2"
git -C "$PUSHER2" config user.name "dev-qual tests"
git -C "$PUSHER2" config user.email "tests@dev-qual.local"
git -C "$PUSHER2" config commit.gpgsign false
echo "one" >>"$PUSHER2/scripts/check-updates.sh"
git -C "$PUSHER2" commit -qam "upstream commit 1"
echo "two" >>"$PUSHER2/scripts/check-updates.sh"
git -C "$PUSHER2" commit -qam "upstream commit 2"
git -C "$PUSHER2" push -q origin HEAD
git -C "$CLONE2" fetch -q origin
OUT2="$(bash "$CLONE2/scripts/check-updates.sh")"
assert_contains "$OUT2" "dev-qual update available: 2 new commit(s) upstream." "2 new commits: reports the count"
assert_contains "$OUT2" "$CLONE2/scripts/upgrade.sh" "2 new commits: offers upgrade.sh in this checkout"

# --- 3. no origin remote: --quiet prints nothing, exit 0 ---
CLONE3="$(mk_tmp_repo)"
mkdir -p "$CLONE3/scripts"
cp "$REPO_ROOT/scripts/check-updates.sh" "$CLONE3/scripts/check-updates.sh"
git -C "$CLONE3" add scripts/check-updates.sh
git -C "$CLONE3" commit -qm "initial"
CODE3=0
OUT3="$(bash "$CLONE3/scripts/check-updates.sh" --quiet)" || CODE3=$?
assert_eq "" "$OUT3" "no origin remote, --quiet: no output"
assert_eq 0 "$CODE3" "no origin remote, --quiet: exit 0"

# --- 4. stale timestamp triggers a background fetch attempt ---
CLONE4="$(mk_synthetic_upstream)"
GIT_DIR4="$(git -C "$CLONE4" rev-parse --absolute-git-dir)"
STAMP4="$GIT_DIR4/dev-qual-last-fetch"
touch -t 202001010000 "$STAMP4"
bash "$CLONE4/scripts/check-updates.sh" --quiet >/dev/null
assert_file "$STAMP4" "stale timestamp: refresh stamp file exists after running"

finish
