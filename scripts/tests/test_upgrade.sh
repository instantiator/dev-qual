#!/usr/bin/env bash
# Tests for scripts/upgrade.sh against a synthetic dev-qual upstream built
# from this checkout's working tree, at both scopes: project (installed as
# a git submodule) and user (a plain clone).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# Local submodule/clone URLs need this to be allowed explicitly; set via env
# vars (not global config) so only this test's git calls (and upgrade.sh's,
# which inherits the environment) are affected.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=protocol.file.allow
export GIT_CONFIG_VALUE_0=always

# Build a synthetic dev-qual upstream from the working tree (uncommitted
# changes included), as a bare repo any number of clones can pull from:
# mk_dq_upstream -> echoes the bare repo's path
mk_dq_upstream() {
  local work bare
  work="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  CLEANUP="$CLEANUP $work"
  rsync -a --exclude=.git --exclude=prompts --exclude=dist --exclude=node_modules \
    "$REPO_ROOT/" "$work/"
  git -C "$work" init -q
  git -C "$work" config user.name "dev-qual tests"
  git -C "$work" config user.email "tests@dev-qual.local"
  git -C "$work" config commit.gpgsign false
  git -C "$work" add -A
  git -C "$work" commit -q -m "synthetic upstream"
  bare="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  CLEANUP="$CLEANUP $bare"
  git clone -q --bare "$work" "$bare"
  echo "$bare"
}

# Push a marker commit to the bare upstream via a throwaway clone, so a
# subsequent upgrade has something new to pull: push_marker_commit <bare>
push_marker_commit() {
  local bare="$1" work
  work="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
  CLEANUP="$CLEANUP $work"
  git clone -q "$bare" "$work"
  git -C "$work" config user.name "dev-qual tests"
  git -C "$work" config user.email "tests@dev-qual.local"
  git -C "$work" config commit.gpgsign false
  echo "<!-- upgrade-test marker -->" >>"$work/skills/adr/SKILL.md"
  git -C "$work" commit -qam "upstream marker commit"
  git -C "$work" push -q origin HEAD
}

# --- 1. project scope: dev-qual installed as a submodule ---
BARE1="$(mk_dq_upstream)"
PROJ1="$(mk_tmp_repo)"
git -C "$PROJ1" submodule add -q "$BARE1" dev-qual
git -C "$PROJ1" commit -qam "add dev-qual submodule"
bash "$PROJ1/dev-qual/install.sh" --project "$PROJ1" --yes --platforms claude --hooks no >/dev/null

push_marker_commit "$BARE1"

UPGRADE_CODE1=0
bash "$PROJ1/dev-qual/scripts/upgrade.sh" --project "$PROJ1" >/dev/null 2>&1 || UPGRADE_CODE1=$?
assert_eq 0 "$UPGRADE_CODE1" "upgrade (project, submodule): exits 0"
assert_contains "$(cat "$PROJ1/dev-qual/skills/adr/SKILL.md")" "upgrade-test marker" "upgrade (project, submodule): submodule has the new upstream commit"
assert_exit 0 "upgrade (project, submodule): check-install passes afterwards" \
  bash "$PROJ1/dev-qual/scripts/check-install.sh" --project "$PROJ1"

# --- 2. user scope: dev-qual is a plain clone ---
BARE2="$(mk_dq_upstream)"
HOME2="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $HOME2"
CHECKOUT2="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $CHECKOUT2"
git clone -q "$BARE2" "$CHECKOUT2/dev-qual"
BEFORE_SHA2="$(git -C "$CHECKOUT2/dev-qual" rev-parse HEAD)"
env -u XDG_CONFIG_HOME HOME="$HOME2" \
  bash "$CHECKOUT2/dev-qual/install.sh" --user --yes --platforms claude >/dev/null

push_marker_commit "$BARE2"

UPGRADE_CODE2=0
env -u XDG_CONFIG_HOME HOME="$HOME2" bash "$CHECKOUT2/dev-qual/scripts/upgrade.sh" --user >/dev/null 2>&1 \
  || UPGRADE_CODE2=$?
assert_eq 0 "$UPGRADE_CODE2" "upgrade (user, clone): exits 0"
AFTER_SHA2="$(git -C "$CHECKOUT2/dev-qual" rev-parse HEAD)"
assert_not_contains "$AFTER_SHA2" "$BEFORE_SHA2" "upgrade (user, clone): HEAD moved"
assert_contains "$(cat "$CHECKOUT2/dev-qual/skills/adr/SKILL.md")" "upgrade-test marker" "upgrade (user, clone): pulled the new upstream commit"

finish
