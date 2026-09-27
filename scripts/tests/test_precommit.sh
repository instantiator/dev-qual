#!/usr/bin/env bash
# Tests that the pre-commit hook gates exactly the staged snapshot: unstaged
# or untracked changes neither block a commit nor excuse a staged problem.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$TEST_DIR/lib/assert.sh"

# Literal script fixtures: the $1 must not expand here
# shellcheck disable=SC2016
CLEAN='#!/usr/bin/env bash
echo "$1"
'
# shellcheck disable=SC2016
BROKEN='#!/usr/bin/env bash
echo $1
'

# A repo using this checkout's hooks, with one clean committed script
REPO="$(mk_tmp_repo)"
git -C "$REPO" config core.hooksPath "$REPO_ROOT/scripts/hooks"
printf '%s' "$CLEAN" >"$REPO/a.sh"
printf '%s' "$CLEAN" >"$REPO/b.sh"
git -C "$REPO" add a.sh b.sh
git -C "$REPO" commit -qm init

# Commit and report its exit code: commit_exit <message>
commit_exit() {
  local code=0
  git -C "$REPO" commit -qm "$1" >/dev/null 2>&1 || code=$?
  echo "$code"
}

# An unstaged broken edit does not block committing a clean staged change
printf '%s' "$BROKEN" >"$REPO/b.sh"
printf '%s\n' "$CLEAN" >"$REPO/a.sh"
git -C "$REPO" add a.sh
assert_eq 0 "$(commit_exit "clean staged, broken unstaged")" "unstaged breakage does not block the commit"
git -C "$REPO" checkout -q -- b.sh

# A staged broken file is blocked even when the working tree has fixed it
printf '%s' "$BROKEN" >"$REPO/a.sh"
git -C "$REPO" add a.sh
printf '%s' "$CLEAN" >"$REPO/a.sh"
assert_eq 1 "$(commit_exit "broken staged, fixed unstaged")" "a staged problem is not excused by an unstaged fix"
git -C "$REPO" checkout -q HEAD -- a.sh

# An untracked broken file is not part of the commit, so it does not block it
printf '%s' "$BROKEN" >"$REPO/untracked.sh"
printf '%s\n\n' "$CLEAN" >"$REPO/a.sh"
git -C "$REPO" add a.sh
assert_eq 0 "$(commit_exit "untracked breakage")" "untracked files are not gated"
rm -f "$REPO/untracked.sh"

# The working tree is left exactly as it was
printf '%s' "$BROKEN" >"$REPO/b.sh"
BEFORE="$(git -C "$REPO" status --porcelain; shasum "$REPO/b.sh")"
printf '%s\n\n\n' "$CLEAN" >"$REPO/a.sh"
git -C "$REPO" add a.sh
commit_exit "leave tree alone" >/dev/null
AFTER="$(git -C "$REPO" status --porcelain; shasum "$REPO/b.sh")"
assert_eq "$BEFORE" "$AFTER" "unstaged work is untouched by the hook"
git -C "$REPO" checkout -q -- b.sh

# Untracked tooling (node_modules) is still available to the project's lint script
NODE_REPO="$(mk_tmp_repo)"
git -C "$NODE_REPO" config core.hooksPath "$REPO_ROOT/scripts/hooks"
printf 'node_modules/\n' >"$NODE_REPO/.gitignore"
printf '{ "name": "t", "private": true, "scripts": { "lint": "node node_modules/fake-lint/index.js" } }\n' \
  >"$NODE_REPO/package.json"
mkdir -p "$NODE_REPO/node_modules/fake-lint"
printf 'process.exit(0);\n' >"$NODE_REPO/node_modules/fake-lint/index.js"
git -C "$NODE_REPO" add .gitignore package.json
code=0
git -C "$NODE_REPO" commit -qm "lint via node_modules" >/dev/null 2>&1 || code=$?
assert_eq 0 "$code" "lint scripts can use the working tree's node_modules"

# A monorepo: lint needs a workspace's own node_modules and a file inside a
# submodule, neither of which is tracked, so both must reach the snapshot
MONO="$(mk_tmp_repo)"
git -C "$MONO" config core.hooksPath "$REPO_ROOT/scripts/hooks"
mkdir -p "$MONO/pkg/node_modules/dep" "$MONO/sub"
touch "$MONO/pkg/node_modules/dep/marker" "$MONO/sub/marker"
printf 'node_modules\nsub/\n' >"$MONO/.gitignore"
printf '[submodule "sub"]\n\tpath = sub\n\turl = x\n' >"$MONO/.gitmodules"
printf '{"scripts":{"lint":"test -f pkg/node_modules/dep/marker && test -f sub/marker"}}\n' >"$MONO/package.json"
echo "{}" >"$MONO/pkg/package.json"
git -C "$MONO" add .
CODE=0
git -C "$MONO" commit -qm mono >/dev/null 2>&1 || CODE=$?
assert_eq 0 "$CODE" "nested node_modules and submodule checkouts are linked into the snapshot"

finish
