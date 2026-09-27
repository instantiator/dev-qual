#!/usr/bin/env bash
# Tests for scripts/toggle.sh: enable/disable/status round-tripping an
# install at both scopes, and that a copied+edited hook survives disable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# A temp project with this checkout symlinked in as its dev-qual submodule
# would be, so relative paths look like a real install: mk_tmp_project
mk_tmp_project() {
  local dir
  dir="$(mk_tmp_repo)"
  ln -s "$REPO_ROOT" "$dir/dev-qual"
  echo "$dir"
}

# A checksum listing of every file under a directory (excluding the checkout
# itself and .git), for before/after comparisons across toggle actions
tree_checksum() {
  find "$1" -type f -not -path '*/.git/*' -not -path "$1/dev-qual/*" | sort | xargs -I{} shasum {} 2>/dev/null
}

# assert_absent <path> <message>: the path must not exist (file or symlink)
assert_absent() {
  local path="$1" message="$2"
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $message" >&2
    echo "  still present: $path" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# --- 1. project scope: install, disable, status, enable round-trip ---
PROJ="$(mk_tmp_project)"
bash "$PROJ/dev-qual/install.sh" --project "$PROJ" --yes --tier local \
  --platforms claude,opencode --hooks yes >/dev/null
AFTER_INSTALL="$(tree_checksum "$PROJ"; git -C "$PROJ" config core.hooksPath)"

bash "$PROJ/dev-qual/scripts/toggle.sh" disable --project "$PROJ" >/dev/null
assert_absent "$PROJ/CLAUDE.md" "disable (project): CLAUDE.md removed (block was its whole content)"
assert_absent "$PROJ/AGENTS.md" "disable (project): AGENTS.md removed (blocks were its whole content)"
assert_absent "$PROJ/.claude/skills/adr" "disable (project): skill symlink removed"
assert_not_contains "$(cat "$PROJ/.claude/settings.json")" "agent-hook.sh" "disable (project): no agent-hook.sh in settings.json"
assert_eq "" "$(git -C "$PROJ" config core.hooksPath || true)" "disable (project): core.hooksPath unset"
assert_contains "$(cat "$PROJ/.dev-qual.env")" "ENABLED=0" "disable (project): state file records ENABLED=0"

STATUS_OUT="$(bash "$PROJ/dev-qual/scripts/toggle.sh" status --project "$PROJ")"
STATUS_CODE=0
bash "$PROJ/dev-qual/scripts/toggle.sh" status --project "$PROJ" >/dev/null || STATUS_CODE=$?
assert_contains "$STATUS_OUT" "disabled" "status (disabled): reports disabled"
assert_eq 0 "$STATUS_CODE" "status (disabled): exits 0"

bash "$PROJ/dev-qual/scripts/toggle.sh" enable --project "$PROJ" >/dev/null
AFTER_ENABLE="$(tree_checksum "$PROJ"; git -C "$PROJ" config core.hooksPath)"
assert_eq "$AFTER_INSTALL" "$AFTER_ENABLE" "enable (project): tree matches the post-install snapshot"
assert_contains "$(cat "$PROJ/.dev-qual.env")" "ENABLED=1" "enable (project): state file records ENABLED=1"

# --- 2. a copied (not symlinked) hook that was edited survives disable ---
PROJ2="$(mk_tmp_project)"
bash "$PROJ2/dev-qual/install.sh" --project "$PROJ2" --yes --tier local \
  --platforms claude --hooks no >/dev/null
bash "$PROJ2/dev-qual/scripts/setup-hooks.sh" --project "$PROJ2" --copy >/dev/null
GIT_HOOKS2="$(git -C "$PROJ2" rev-parse --git-path hooks)"
printf '#!/usr/bin/env bash\necho edited\n' >>"$PROJ2/$GIT_HOOKS2/pre-commit"
DISABLE_OUT2="$(bash "$PROJ2/dev-qual/scripts/toggle.sh" disable --project "$PROJ2" 2>&1)"
assert_file "$PROJ2/$GIT_HOOKS2/pre-commit" "disable (copied+edited hook): pre-commit left in place"
assert_contains "$DISABLE_OUT2" "differs" "disable (copied+edited hook): warns about the edited hook"

# --- 3. user scope: install, disable, status, enable round-trip ---
HOME3="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $HOME3"
env -u XDG_CONFIG_HOME HOME="$HOME3" \
  bash "$REPO_ROOT/install.sh" --user --yes --tier remote --platforms claude,opencode >/dev/null
AFTER_INSTALL3="$(tree_checksum "$HOME3")"

env -u XDG_CONFIG_HOME HOME="$HOME3" bash "$REPO_ROOT/scripts/toggle.sh" disable --user >/dev/null
assert_absent "$HOME3/.claude/CLAUDE.md" "disable (user): CLAUDE.md removed entirely"
assert_absent "$HOME3/.config/opencode/AGENTS.md" "disable (user): opencode AGENTS.md removed entirely"
assert_absent "$HOME3/.claude/skills/adr" "disable (user): skill symlink removed"
assert_contains "$(cat "$HOME3/.config/dev-qual/config.env")" "ENABLED=0" "disable (user): state file records ENABLED=0"

STATUS_CODE3=0
STATUS_OUT3="$(env -u XDG_CONFIG_HOME HOME="$HOME3" bash "$REPO_ROOT/scripts/toggle.sh" status --user)" \
  || STATUS_CODE3=$?
assert_contains "$STATUS_OUT3" "disabled" "status (user, disabled): reports disabled"
assert_eq 0 "$STATUS_CODE3" "status (user, disabled): exits 0"

env -u XDG_CONFIG_HOME HOME="$HOME3" bash "$REPO_ROOT/scripts/toggle.sh" enable --user >/dev/null
AFTER_ENABLE3="$(tree_checksum "$HOME3")"
assert_eq "$AFTER_INSTALL3" "$AFTER_ENABLE3" "enable (user): tree matches the post-install snapshot"
assert_contains "$(cat "$HOME3/.config/dev-qual/config.env")" "ENABLED=1" "enable (user): state file records ENABLED=1"

# --- 4. not-installed cases exit 2 ---
NOTINSTALLED="$(mk_tmp_repo)"
assert_exit 2 "toggle.sh status: not installed exits 2" \
  bash "$REPO_ROOT/scripts/toggle.sh" status --project "$NOTINSTALLED"

finish
