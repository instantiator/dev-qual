#!/usr/bin/env bash
# Tests for agent-hook.sh's stop event, and plan-status.sh directly. The
# post-edit and session-start cases live in test_install.sh already.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# A temp project with this checkout symlinked in as its dev-qual submodule
# would be, and a state file wired up as install.sh would leave it, plus one
# committed clean shell script: mk_hook_project
mk_hook_project() {
  local dir
  dir="$(mk_tmp_repo)"
  ln -s "$REPO_ROOT" "$dir/dev-qual"
  cat >"$dir/.dev-qual.env" <<EOF
SCOPE=project
TIER=local
PLATFORMS=claude
HOOKS=no
CHECKOUT=dev-qual
ENABLED=1
EOF
  printf '#!/usr/bin/env bash\necho hello\n' >"$dir/good.sh"
  git -C "$dir" add .dev-qual.env good.sh
  git -C "$dir" commit -qm "initial"
  echo "$dir"
}

# Run agent-hook.sh stop in a project, feeding it the given JSON stdin
run_stop() {
  local dir="$1" json="$2"
  CLAUDE_PROJECT_DIR="$dir" bash "$REPO_ROOT/scripts/agent-hook.sh" stop --scope project <<<"$json"
}

# --- 1. docs-only changes never trigger the gate ---
PROJ1="$(mk_hook_project)"
echo "notes" >"$PROJ1/README.md"
mkdir -p "$PROJ1/docs"
echo "notes" >"$PROJ1/docs/x.txt"
CODE=0
OUT="$(run_stop "$PROJ1" '{"stop_hook_active":false}' 2>&1)" || CODE=$?
assert_eq 0 "$CODE" "stop: docs-only changes exit 0"
assert_eq "" "$OUT" "stop: docs-only changes print nothing"

# --- 2. a shellcheck-failing code change blocks once ---
PROJ2="$(mk_hook_project)"
# shellcheck disable=SC2016 # literal script content, not an expansion here
printf '#!/usr/bin/env bash\necho $1\n' >"$PROJ2/good.sh"
CODE=0
ERR="$(run_stop "$PROJ2" '{"stop_hook_active":false}' 2>&1 1>/dev/null)" || CODE=$?
assert_eq 2 "$CODE" "stop: shellcheck-failing change exits 2"
assert_contains "$ERR" "shellcheck" "stop: failure output mentions shellcheck"
assert_contains "$ERR" "dev-qual stop gate" "stop: failure output has the header"

# --- 3. stop_hook_active:true never blocks, even with the same bad change ---
CODE=0
run_stop "$PROJ2" '{"stop_hook_active": true}' >/dev/null 2>&1 || CODE=$?
assert_eq 0 "$CODE" "stop: stop_hook_active true always exits 0"

# --- 4. clean code change + an active plan with an unchecked stage blocks ---
PROJ4="$(mk_hook_project)"
echo "# tweak" >>"$PROJ4/good.sh"
mkdir -p "$PROJ4/docs/plans"
cat >"$PROJ4/docs/plans/p.md" <<'EOF'
---
status: active
---
# Plan

- [x] Stage 1: done already
- [ ] Stage 2: not done yet
EOF
CODE=0
ERR4="$(run_stop "$PROJ4" '{"stop_hook_active":false}' 2>&1 1>/dev/null)" || CODE=$?
assert_eq 2 "$CODE" "stop: unfinished plan stage exits 2"
assert_contains "$ERR4" "Stage 2" "stop: lists the unchecked stage"
assert_not_contains "$ERR4" "Stage 1: done already" "stop: does not list the checked stage"

# --- 5. same plan marked done: no block ---
sed -i.bak 's/status: active/status: done/' "$PROJ4/docs/plans/p.md"
CODE=0
run_stop "$PROJ4" '{"stop_hook_active":false}' >/dev/null 2>&1 || CODE=$?
assert_eq 0 "$CODE" "stop: plan status done exits 0"

# --- 6. ENABLED=0 skips the gate entirely ---
PROJ6="$(mk_hook_project)"
# shellcheck disable=SC2016 # literal script content, not an expansion here
printf '#!/usr/bin/env bash\necho $1\n' >"$PROJ6/good.sh"
sed -i.bak 's/ENABLED=1/ENABLED=0/' "$PROJ6/.dev-qual.env"
CODE=0
run_stop "$PROJ6" '{"stop_hook_active":false}' >/dev/null 2>&1 || CODE=$?
assert_eq 0 "$CODE" "stop: ENABLED=0 exits 0"

# --- 7. plan-status.sh directly ---
NOPLANS="$(mk_tmp_repo)"
CODE=0
OUT7="$(bash "$REPO_ROOT/scripts/plan-status.sh" --project "$NOPLANS")" || CODE=$?
assert_eq 0 "$CODE" "plan-status: no docs/plans dir exits 0"
assert_eq "" "$OUT7" "plan-status: no docs/plans dir prints nothing"

WITHPLAN="$(mk_tmp_repo)"
mkdir -p "$WITHPLAN/docs/plans"
cat >"$WITHPLAN/docs/plans/p.md" <<'EOF'
---
status: active
---
- [ ] Stage 2: not done yet
EOF
CODE=0
OUT8="$(bash "$REPO_ROOT/scripts/plan-status.sh" --project "$WITHPLAN")" || CODE=$?
assert_eq 1 "$CODE" "plan-status: active plan with unchecked stage exits 1"
assert_contains "$OUT8" "Stage 2" "plan-status: lists the unchecked stage"

finish
