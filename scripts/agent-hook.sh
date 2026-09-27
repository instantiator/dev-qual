#!/usr/bin/env bash
# Agent hook dispatcher: routes a Claude Code (or other agent platform) hook
# event to the right dev-qual action, honouring whichever install (project
# or user) governs. Wired into settings.json by adapters/claude-code/install.sh.
#
# post-edit:     runs the fast quality gate after every edit.
# session-start: prints a non-blocking "is there an update?" line.
# stop:          when code (not just docs) changed, blocks once on a failing
#                fast gate or unfinished plan stages; never blocks twice in
#                a row (honours Claude Code's stop_hook_active).
#
# Usage: agent-hook.sh <post-edit|session-start|stop> [--scope project|user]
# Exit code: 2 if post-edit's check fails, or stop's gate fails (either way
#            the output goes to stderr, which Claude Code feeds back to the
#            model); 0 otherwise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

EVENT=""; SCOPE="project"
while [ $# -gt 0 ]; do
  case "$1" in
    post-edit|session-start|stop) EVENT="$1" ;;
    --scope) SCOPE="${2:?--scope needs project or user}"; shift ;;
    --help|-h) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$EVENT" ] || { echo "Usage: agent-hook.sh <post-edit|session-start|stop> [--scope project|user]" >&2; exit 2; }

# Hooks always get stdin closed by Claude Code; guard defensively so a
# manual/interactive invocation never blocks on it. stop needs the JSON
# payload (for stop_hook_active); other events just drain and discard it.
INPUT=""
[ -t 0 ] || INPUT="$(cat)"

# Locate the project root: CLAUDE_PROJECT_DIR (set by Claude Code), else the
# git toplevel of the current directory, else the current directory itself.
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
if git -C "$DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git -C "$DIR" rev-parse --show-toplevel)"
else
  ROOT="$DIR"
fi
PROJECT_CONFIG="$ROOT/.dev-qual.env"

# Work out which config governs. A user-scope hook backs off entirely when
# the project has its own install, so the gate doesn't run twice.
if [ "$SCOPE" = "user" ]; then
  [ -f "$PROJECT_CONFIG" ] && exit 0
  GOVERNING="$(state_file_for user)"
else
  GOVERNING="$PROJECT_CONFIG"
fi
[ -f "$GOVERNING" ] || exit 0

ENABLED="1"
# shellcheck disable=SC1090
. "$GOVERNING"
[ "$ENABLED" = "1" ] || exit 0

case "$EVENT" in
  post-edit)
    # Run the fast gate; on failure, its output must reach stderr with exit
    # 2 so Claude Code's PostToolUse hook shows it to the model.
    if OUTPUT="$(bash "$SCRIPT_DIR/check.sh" --fast --project "$ROOT" 2>&1)"; then
      exit 0
    fi
    echo "$OUTPUT" >&2
    exit 2
    ;;
  session-start)
    # Non-blocking update check; its stdout becomes Claude Code's
    # SessionStart context, so let it through and never fail the event.
    bash "$SCRIPT_DIR/check-updates.sh" --quiet || true
    exit 0
    ;;
  stop)
    # Never block twice in a row: Claude Code sets stop_hook_active on the
    # re-invocation after a block, so let that one through unconditionally.
    echo "$INPUT" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

    # Only gate when actual code (not just docs) changed. A path counts as
    # docs when it's Markdown or under docs/; renames are judged by their
    # new path, and quoted porcelain paths are unquoted loosely.
    CODE_CHANGED=0
    if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      STATUS="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        path="${line:3}"
        case "$path" in *" -> "*) path="${path#*-> }" ;; esac
        path="${path%\"}"; path="${path#\"}"
        case "$path" in
          *.md|docs/*) ;;
          *) CODE_CHANGED=1 ;;
        esac
      done <<EOF
$STATUS
EOF
    fi
    [ "$CODE_CHANGED" = 1 ] || exit 0

    FAST_OK=1
    FAST_OUT="$(bash "$SCRIPT_DIR/check.sh" --fast --project "$ROOT" 2>&1)" || FAST_OK=0
    PLAN_OK=1
    PLAN_OUT="$(bash "$SCRIPT_DIR/plan-status.sh" --project "$ROOT" 2>&1)" || PLAN_OK=0
    [ "$FAST_OK" = 1 ] && [ "$PLAN_OK" = 1 ] && exit 0

    echo "dev-qual stop gate: fix these before finishing, or tell the user why they remain." >&2
    if [ "$FAST_OK" = 0 ]; then
      echo "$FAST_OUT" | sed -n '/== Results ==/,$p' >&2
    fi
    if [ "$PLAN_OK" = 0 ]; then
      echo "Unfinished plan stages:" >&2
      echo "$PLAN_OUT" >&2
    fi
    exit 2
    ;;
esac
