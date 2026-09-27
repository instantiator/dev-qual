#!/usr/bin/env bash
# Tests the session-start git hooks offer that a user-scope install makes in
# each repository lacking dev-qual's hooks.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$TEST_DIR/lib/assert.sh"

HOOK="$REPO_ROOT/scripts/agent-hook.sh"

# A temp HOME with an enabled user-scope install pointing at this checkout
HOME="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-home.XXXXXX")"
CLEANUP="$CLEANUP $HOME"
export HOME
unset XDG_CONFIG_HOME CLAUDE_PROJECT_DIR
mkdir -p "$HOME/.config/dev-qual"
printf 'SCOPE=user\nTIER=local\nPLATFORMS=claude\nHOOKS=no\nCHECKOUT=%s\nENABLED=1\n' "$REPO_ROOT" \
  >"$HOME/.config/dev-qual/config.env"

# Run the user-scope session-start hook from inside a repo: session_start <repo>
session_start() {
  (cd "$1" && bash "$HOOK" session-start --scope user </dev/null)
}

# A repo with no hooks is offered the default install
BARE="$(cd "$(mk_tmp_repo)" && pwd -P)"
OUT="$(session_start "$BARE")"
assert_contains "$OUT" "not quality-gated" "a repo without hooks gets the offer"
assert_contains "$OUT" "setup-hooks.sh --project $BARE\`" "the offer names this repo, without --copy"
assert_contains "$OUT" "devqual.hooks declined" "the offer says how to decline"

# Declining silences the offer
git -C "$BARE" config devqual.hooks declined
OUT="$(session_start "$BARE")"
assert_not_contains "$OUT" "not quality-gated" "a declined repo is not offered again"

# Hooks installed via core.hooksPath: no offer
INSTALLED="$(mk_tmp_repo)"
bash "$REPO_ROOT/scripts/setup-hooks.sh" --project "$INSTALLED" >/dev/null
OUT="$(session_start "$INSTALLED")"
assert_not_contains "$OUT" "not quality-gated" "core.hooksPath install is recognised"

# Hooks installed by copy: no offer. setup-hooks.sh runs from elsewhere, as
# it would for a user, so the copy must still land in this repo's hooks.
COPIED="$(mk_tmp_repo)"
(cd "$HOME" && bash "$REPO_ROOT/scripts/setup-hooks.sh" --project "$COPIED" --copy >/dev/null)
assert_file "$COPIED/.git/hooks/pre-commit" "--copy installs into the target repo, not the cwd"
OUT="$(session_start "$COPIED")"
assert_not_contains "$OUT" "not quality-gated" "copied hooks are recognised"

# A repo with its own hooks is offered --copy
OWN="$(mk_tmp_repo)"
printf '#!/bin/sh\nexit 0\n' >"$OWN/.git/hooks/commit-msg"
OUT="$(session_start "$OWN")"
assert_contains "$OUT" "--copy" "a repo with its own hooks is offered --copy"

# A repo using another hooks manager is told to call the gate from it
MANAGED="$(mk_tmp_repo)"
git -C "$MANAGED" config core.hooksPath .husky
OUT="$(session_start "$MANAGED")"
assert_contains "$OUT" "core.hooksPath=.husky" "another hooks manager is named"
assert_not_contains "$OUT" "setup-hooks.sh" "no setup command that would displace it"

# A project-scope install governs its own repo: the user hook stays quiet
PROJECT="$(mk_tmp_repo)"
printf 'SCOPE=project\nENABLED=1\n' >"$PROJECT/.dev-qual.env"
OUT="$(session_start "$PROJECT")"
assert_not_contains "$OUT" "not quality-gated" "a project-scope install is left alone"

# Disabled user install: no offer
sed -i.bak 's/^ENABLED=1/ENABLED=0/' "$HOME/.config/dev-qual/config.env"
OUT="$(session_start "$(mk_tmp_repo)")"
assert_not_contains "$OUT" "not quality-gated" "a disabled install makes no offer"

finish
