#!/usr/bin/env bash
# Agent hook dispatcher: routes a Claude Code (or other agent platform) hook
# event to the right dev-qual action, honouring whichever install (project
# or user) governs. Wired into settings.json by adapters/claude-code/install.sh.
#
# Usage: agent-hook.sh <post-edit|session-start|stop> [--scope project|user]
# Exit code: 2 if post-edit's check fails (its output goes to stderr, which
#            Claude Code feeds back to the model); 0 otherwise.
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
    --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$EVENT" ] || { echo "Usage: agent-hook.sh <post-edit|session-start|stop> [--scope project|user]" >&2; exit 2; }

# Hooks always get stdin closed by Claude Code; guard defensively so a
# manual/interactive invocation never blocks on it.
[ -t 0 ] || cat >/dev/null

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
    # Reserved for a later stage.
    exit 0
    ;;
  stop)
    # Reserved for a later stage.
    exit 0
    ;;
esac
