#!/usr/bin/env bash
# Tests for install.sh, the platform adapters, agent-hook.sh, and
# check-install.sh working together across project and user scope.
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

# A checksum listing of every file under a directory, for idempotency checks
tree_checksum() {
  find "$1" -type f -not -path '*/.git/*' | sort | xargs -I{} shasum {} 2>/dev/null
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

# --- 1. project scope install ---
PROJ1="$(mk_tmp_project)"
OUT="$(bash "$PROJ1/dev-qual/install.sh" --project "$PROJ1" --yes --tier local --platforms claude,opencode --hooks no 2>&1)"
assert_eq 1 "$(grep -c 'dev-qual:start -->' "$PROJ1/AGENTS.md")" "one dev-qual block in AGENTS.md"
assert_eq 1 "$(grep -c 'dev-qual:skills:start -->' "$PROJ1/AGENTS.md")" "one dev-qual:skills block in AGENTS.md"
assert_eq 1 "$(grep -c 'dev-qual:start -->' "$PROJ1/CLAUDE.md")" "one dev-qual block in CLAUDE.md"
assert_eq 1 "$(grep -cx '@AGENTS.md' "$PROJ1/CLAUDE.md")" "project scope: CLAUDE.md imports AGENTS.md"
assert_file "$PROJ1/.claude/skills/adr" ".claude/skills/adr symlink exists"
if [ -L "$PROJ1/.claude/skills/adr" ]; then PASS_COUNT=$((PASS_COUNT + 1)); else
  echo "FAIL: adr skill is a symlink" >&2; FAIL_COUNT=$((FAIL_COUNT + 1))
fi
assert_eq 3 "$(grep -c 'agent-hook.sh' "$PROJ1/.claude/settings.json")" "three agent-hook.sh commands in settings.json"
# shellcheck disable=SC2016 # literal text to search for, not an expansion
assert_contains "$(cat "$PROJ1/.claude/settings.json")" '$CLAUDE_PROJECT_DIR' "hook commands use \$CLAUDE_PROJECT_DIR"
assert_contains "$(cat "$PROJ1/.dev-qual.env")" "SCOPE=project" "state file records project scope"
assert_contains "$(cat "$PROJ1/.dev-qual.env")" "CHECKOUT=dev-qual" "state file records the relative checkout path"
assert_not_contains "$OUT" "FAIL" "install run reports no failures"

# --- 2. re-running changes nothing ---
BEFORE="$(tree_checksum "$PROJ1")"
bash "$PROJ1/dev-qual/install.sh" --project "$PROJ1" --yes --tier local --platforms claude,opencode --hooks no >/dev/null
AFTER="$(tree_checksum "$PROJ1")"
assert_eq "$BEFORE" "$AFTER" "re-running the same install is a no-op"

# --- 2b. a hand-set PLANS_GLOB (spaces and all) survives a re-install ---
PROJ2B="$(mk_tmp_project)"
bash "$PROJ2B/dev-qual/install.sh" --project "$PROJ2B" --yes --tier local --platforms claude --hooks no >/dev/null
printf '%s\n' "PLANS_GLOB='docs/prompts/phase 04 - x/*.plan*.md'" >>"$PROJ2B/.dev-qual.env"
bash "$PROJ2B/dev-qual/install.sh" --project "$PROJ2B" --yes --tier local --platforms claude --hooks no >/dev/null
# shellcheck source=/dev/null
assert_eq 'docs/prompts/phase 04 - x/*.plan*.md' "$(. "$PROJ2B/.dev-qual.env"; printf '%s' "$PLANS_GLOB")" "re-install keeps PLANS_GLOB"

# --- 3. --from-config reproduces the tree from a clean project ---
PROJ3="$(mk_tmp_project)"
cp "$PROJ1/.dev-qual.env" "$PROJ3/.dev-qual.env"
bash "$PROJ3/dev-qual/install.sh" --project "$PROJ3" --from-config >/dev/null
assert_eq 1 "$(grep -c 'dev-qual:start -->' "$PROJ3/AGENTS.md")" "--from-config: one dev-qual block in AGENTS.md"
assert_eq 1 "$(grep -c 'dev-qual:skills:start -->' "$PROJ3/AGENTS.md")" "--from-config: one dev-qual:skills block"
assert_file "$PROJ3/.claude/skills/adr" "--from-config: adr skill symlinked"
assert_eq "$(cat "$PROJ1/AGENTS.md")" "$(cat "$PROJ3/AGENTS.md")" "--from-config: AGENTS.md matches the original install"

# --- 4. CLAUDE.md migration ---
PROJ4A="$(mk_tmp_project)"
cp "$REPO_ROOT/agents-files/remote/CLAUDE.md" "$PROJ4A/CLAUDE.md"
bash "$PROJ4A/dev-qual/adapters/claude-code/install.sh" --project "$PROJ4A" --yes >/dev/null
assert_eq 1 "$(grep -c 'dev-qual:start -->' "$PROJ4A/CLAUDE.md")" "byte-identical CLAUDE.md: migrated to exactly one block"
assert_not_contains "$(cat "$PROJ4A/CLAUDE.md")" "NOTE:" "byte-identical CLAUDE.md: no duplicate-content NOTE written into the file"

PROJ4B="$(mk_tmp_project)"
echo "# My custom notes, keep me" >"$PROJ4B/CLAUDE.md"
bash "$PROJ4B/dev-qual/adapters/claude-code/install.sh" --project "$PROJ4B" --yes >/dev/null
assert_contains "$(cat "$PROJ4B/CLAUDE.md")" "My custom notes, keep me" "custom CLAUDE.md: custom text kept"
assert_eq 1 "$(grep -c 'dev-qual:start -->' "$PROJ4B/CLAUDE.md")" "custom CLAUDE.md: block appended"

# --- 5. old static hook migration, unrelated hook kept ---
PROJ5="$(mk_tmp_project)"
mkdir -p "$PROJ5/.claude"
cat >"$PROJ5/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [{"type":"command","command":"bash dev-qual/scripts/check.sh --fast"}] },
      { "matcher": "Bash", "hooks": [{"type":"command","command":"echo unrelated"}] }
    ]
  }
}
EOF
bash "$PROJ5/dev-qual/adapters/claude-code/install.sh" --project "$PROJ5" --yes >/dev/null
SETTINGS5="$(cat "$PROJ5/.claude/settings.json")"
assert_not_contains "$SETTINGS5" "dev-qual/scripts/check.sh --fast" "old static hook is removed"
assert_contains "$SETTINGS5" "agent-hook.sh" "new agent-hook.sh hook is present"
assert_contains "$SETTINGS5" "echo unrelated" "unrelated hook entry is kept"

# --- 6. user scope install ---
HOME6="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $HOME6"
OUT6="$(env -u XDG_CONFIG_HOME HOME="$HOME6" \
  bash "$REPO_ROOT/install.sh" --user --yes --tier remote --platforms claude,opencode 2>&1)"
CLAUDE_MD6="$HOME6/.claude/CLAUDE.md"
OPENCODE_AGENTS6="$HOME6/.config/opencode/AGENTS.md"
assert_contains "$(cat "$CLAUDE_MD6")" "$REPO_ROOT" "user scope: CLAUDE.md has the absolute checkout path"
assert_not_contains "$(cat "$CLAUDE_MD6")" '`dev-qual/' "user scope: CLAUDE.md has no bare dev-qual/ paths"
assert_eq 1 "$(grep -cx "@$REPO_ROOT/agents-files/remote/AGENTS.md" "$CLAUDE_MD6")" "user scope: CLAUDE.md imports the checkout's remote AGENTS.md"
assert_eq 0 "$(grep -cx '@AGENTS.md' "$CLAUDE_MD6" || true)" "user scope: no bare @AGENTS.md import"
assert_eq 1 "$(grep -c 'dev-qual:start -->' "$OPENCODE_AGENTS6")" "user scope: opencode AGENTS.md has the tier block"
assert_eq 1 "$(grep -c 'dev-qual:skills:start -->' "$OPENCODE_AGENTS6")" "user scope: opencode AGENTS.md has the skills block"
assert_contains "$(cat "$OPENCODE_AGENTS6")" "$REPO_ROOT/skills" "user scope: opencode skills paths are absolute"
assert_file "$HOME6/.claude/skills/adr" "user scope: adr skill symlinked"
assert_file "$HOME6/.config/dev-qual/config.env" "user scope: state file written"
assert_contains "$(cat "$HOME6/.config/dev-qual/config.env")" "SCOPE=user" "user scope: state file records user scope"
assert_not_contains "$OUT6" "FAIL" "user scope install reports no failures"
assert_absent "$REPO_ROOT/.dev-qual.env" "user scope install wrote nothing into this checkout"

# --- 7. check-install.sh passes right after install, at each scope
#        (git hooks included, since check-install.sh expects them) ---
PROJ7="$(mk_tmp_project)"
bash "$PROJ7/dev-qual/install.sh" --project "$PROJ7" --yes --tier local --platforms claude,opencode --hooks yes >/dev/null
assert_exit 0 "check-install.sh passes for the project-scope install" \
  bash "$PROJ7/dev-qual/scripts/check-install.sh" --project "$PROJ7"
assert_exit 0 "check-install.sh passes for the user-scope install" \
  env -u XDG_CONFIG_HOME HOME="$HOME6" bash "$REPO_ROOT/scripts/check-install.sh" --user

# --- 8. adapter --remove leaves no dev-qual traces, keeps unrelated content ---
bash "$PROJ5/dev-qual/adapters/claude-code/install.sh" --project "$PROJ5" --remove
assert_absent "$PROJ5/CLAUDE.md" "remove (claude, project): CLAUDE.md removed (the block was its whole content)"
assert_absent "$PROJ5/.claude/skills/adr" "remove (claude, project): adr symlink removed"
assert_not_contains "$(cat "$PROJ5/.claude/settings.json")" "agent-hook.sh" "remove (claude, project): hook entries gone"
assert_contains "$(cat "$PROJ5/.claude/settings.json")" "echo unrelated" "remove (claude, project): unrelated hook kept"

bash "$PROJ1/dev-qual/adapters/opencode/install.sh" --project "$PROJ1" --remove
assert_not_contains "$(cat "$PROJ1/AGENTS.md")" "dev-qual:skills:start" "remove (opencode, project): skills block gone"
assert_contains "$(cat "$PROJ1/AGENTS.md")" "dev-qual:start" "remove (opencode, project): tier block untouched (it's install.sh's job)"

env -u XDG_CONFIG_HOME HOME="$HOME6" bash "$REPO_ROOT/adapters/claude-code/install.sh" --user --remove
assert_absent "$CLAUDE_MD6" "remove (claude, user): CLAUDE.md removed entirely (block was the whole file)"
assert_absent "$HOME6/.claude/skills/adr" "remove (claude, user): adr symlink removed"

env -u XDG_CONFIG_HOME HOME="$HOME6" bash "$REPO_ROOT/adapters/opencode/install.sh" --user --remove
assert_absent "$OPENCODE_AGENTS6" "remove (opencode, user): AGENTS.md removed entirely (both blocks were the whole file)"

# --- 9. agent-hook.sh post-edit ---
HOOKREPO="$(mk_tmp_repo)"
cat >"$HOOKREPO/.dev-qual.env" <<EOF
SCOPE=project
TIER=local
PLATFORMS=claude
HOOKS=no
CHECKOUT=$REPO_ROOT
ENABLED=1
EOF

cat >"$HOOKREPO/bad.sh" <<'EOF'
#!/usr/bin/env bash
echo $1
EOF
CODE=0
BADOUT="$(CLAUDE_PROJECT_DIR="$HOOKREPO" bash "$REPO_ROOT/scripts/agent-hook.sh" post-edit --scope project 2>&1 </dev/null)" || CODE=$?
assert_eq 2 "$CODE" "agent-hook.sh post-edit: exits 2 on a shellcheck finding"
assert_contains "$BADOUT" "bad.sh" "agent-hook.sh post-edit: failure output names the bad file"

rm -f "$HOOKREPO/bad.sh"
CLEAN_STDOUT_FILE="$(mktemp)"
CODE=0
CLAUDE_PROJECT_DIR="$HOOKREPO" bash "$REPO_ROOT/scripts/agent-hook.sh" post-edit --scope project \
  >"$CLEAN_STDOUT_FILE" 2>/dev/null </dev/null || CODE=$?
assert_eq 0 "$CODE" "agent-hook.sh post-edit: exits 0 on a clean project"
assert_eq "" "$(cat "$CLEAN_STDOUT_FILE")" "agent-hook.sh post-edit: no stdout on success"
rm -f "$CLEAN_STDOUT_FILE"

sed -i.bak 's/ENABLED=1/ENABLED=0/' "$HOOKREPO/.dev-qual.env"
cat >"$HOOKREPO/bad.sh" <<'EOF'
#!/usr/bin/env bash
echo $1
EOF
CODE=0
CLAUDE_PROJECT_DIR="$HOOKREPO" bash "$REPO_ROOT/scripts/agent-hook.sh" post-edit --scope project >/dev/null 2>&1 </dev/null || CODE=$?
assert_eq 0 "$CODE" "agent-hook.sh post-edit: ENABLED=0 exits 0 without running the gate"
sed -i.bak 's/ENABLED=0/ENABLED=1/' "$HOOKREPO/.dev-qual.env"

CODE=0
CLAUDE_PROJECT_DIR="$HOOKREPO" bash "$REPO_ROOT/scripts/agent-hook.sh" post-edit --scope user >/dev/null 2>&1 </dev/null || CODE=$?
assert_eq 0 "$CODE" "agent-hook.sh post-edit: --scope user backs off when a project .dev-qual.env exists"

# --- 10. platform pi, with pi not on PATH (true in CI and dev machines
#         alike, since pi isn't installed here): succeeds and prints the
#         manual command rather than failing the install ---
if command -v pi >/dev/null 2>&1; then
  echo "SKIP: pi test 10 — pi unexpectedly on PATH" >&2
else
  PROJ10="$(mk_tmp_project)"
  OUT10="$(bash "$PROJ10/dev-qual/install.sh" --project "$PROJ10" --yes \
    --tier local --platforms pi --hooks no 2>&1)"
  assert_not_contains "$OUT10" "FAIL" "install with platforms=pi and no pi on PATH reports no failures"
  assert_contains "$OUT10" "pi install" "install prints the manual pi install command"
fi

# --- 11. a Prettier project gets its submodules (and the checkout) in
#         .prettierignore, keeps its own entries, and check-install flags
#         the block once the submodules change ---
PROJ11="$(mk_tmp_project)"
printf '{"devDependencies":{"prettier":"^3"}}\n' >"$PROJ11/package.json"
printf 'own-entry\n' >"$PROJ11/.prettierignore"
printf '[submodule "a"]\n\tpath = vendor/a\n\turl = x\n' >"$PROJ11/.gitmodules"
bash "$PROJ11/dev-qual/install.sh" --project "$PROJ11" --yes --tier local --platforms none --hooks no >/dev/null
IGNORE11="$(cat "$PROJ11/.prettierignore")"
assert_contains "$IGNORE11" "own-entry" ".prettierignore keeps the project's own entries"
assert_contains "$IGNORE11" "vendor/a" ".prettierignore lists the submodule"
assert_contains "$IGNORE11" "# <!-- dev-qual:submodules:start -->" "block markers are # comments"
assert_eq 1 "$(grep -cx 'dev-qual' "$PROJ11/.prettierignore")" ".prettierignore lists the checkout once"
OUT11="$(bash "$PROJ11/dev-qual/scripts/check-install.sh" --project "$PROJ11" 2>&1 || true)"
assert_contains "$OUT11" "PASS .prettierignore" "check-install passes a current block"
printf '[submodule "b"]\n\tpath = vendor/b\n\turl = x\n' >>"$PROJ11/.gitmodules"
OUT11="$(bash "$PROJ11/dev-qual/scripts/check-install.sh" --project "$PROJ11" 2>&1 || true)"
assert_contains "$OUT11" "FAIL .prettierignore" "check-install flags a stale block"
bash "$PROJ11/dev-qual/install.sh" --project "$PROJ11" --from-config >/dev/null
assert_contains "$(cat "$PROJ11/.prettierignore")" "vendor/b" "re-install picks up the new submodule"

# --- 12. installer output is stable under a formatter: Markdown blocks are
#         padded as Prettier pads them, an unpadded (older) block still
#         compares as current, and a re-install leaves an already-current
#         settings.json byte-for-byte alone ---
PROJ12="$(mk_tmp_project)"
bash "$PROJ12/dev-qual/install.sh" --project "$PROJ12" --yes --tier local --platforms claude --hooks no >/dev/null
assert_eq "<!-- dev-qual:start -->|" "$(grep -A1 'dev-qual:start -->' "$PROJ12/CLAUDE.md" | paste -sd'|' -)" "blank line follows the start marker"
sed -i.bak '/dev-qual:start -->/{n;d;}' "$PROJ12/CLAUDE.md"
OUT12="$(bash "$PROJ12/dev-qual/scripts/check-install.sh" --project "$PROJ12" 2>&1 || true)"
assert_contains "$OUT12" "PASS CLAUDE.md" "an unpadded block still compares as current"
node -e 'const f=process.argv[1],fs=require("fs");const s=JSON.parse(fs.readFileSync(f));s.permissions={allow:["x"]};fs.writeFileSync(f,JSON.stringify(s)+"\n")' "$PROJ12/.claude/settings.json"
BEFORE12="$(cat "$PROJ12/.claude/settings.json")"
bash "$PROJ12/dev-qual/install.sh" --project "$PROJ12" --from-config >/dev/null
assert_eq "$BEFORE12" "$(cat "$PROJ12/.claude/settings.json")" "re-install keeps a current settings.json's layout"

finish
