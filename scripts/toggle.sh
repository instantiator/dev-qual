#!/usr/bin/env bash
# Enables, disables, or reports the status of an existing dev-qual install,
# without touching the state file's recorded choices (tier/platforms/hooks)
# so a later enable reproduces exactly what was installed before.
#
# Usage: toggle.sh <enable|disable|status> [--project <dir> | --user]
#   --project <dir>  target repo (project scope; default: parent of this checkout)
#   --user            operate on the user-scope install instead
# Exit code: 2 if not installed; for status, check-install.sh's code when
#            enabled, else 0; for enable/disable, install.sh's/0.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$REPO/scripts/lib/common.sh"

ACTION=""; PROJECT=""; SCOPE="project"
while [ $# -gt 0 ]; do
  case "$1" in
    enable|disable|status) ACTION="$1" ;;
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --user) SCOPE="user" ;;
    --help|-h) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$ACTION" ] || { echo "Usage: toggle.sh <enable|disable|status> [--project <dir> | --user]" >&2; exit 2; }

if [ "$SCOPE" = "project" ]; then
  [ -n "$PROJECT" ] || PROJECT="$(cd "$REPO/.." && pwd)"
  [ -d "$PROJECT" ] || { echo "Project directory not found: $PROJECT" >&2; exit 2; }
  PROJECT="$(cd "$PROJECT" && pwd)"
fi

STATE_FILE="$(state_file_for "$SCOPE" "$PROJECT")"
[ -f "$STATE_FILE" ] || { echo "not installed — run install.sh" >&2; exit 2; }
# shellcheck disable=SC1090
. "$STATE_FILE"

# Undo everything install.sh wired for this scope, keeping the state file
# itself so `enable` can reproduce the same install.
do_disable() {
  if [ "$SCOPE" = "project" ]; then
    remove_block "$PROJECT/AGENTS.md" "dev-qual"
    case ",$PLATFORMS," in
      *,claude,*) bash "$REPO/adapters/claude-code/install.sh" --project "$PROJECT" --remove ;;
    esac
    case ",$PLATFORMS," in
      *,opencode,*) bash "$REPO/adapters/opencode/install.sh" --project "$PROJECT" --remove ;;
    esac
    undo_git_hooks
  else
    case ",$PLATFORMS," in
      *,claude,*) bash "$REPO/adapters/claude-code/install.sh" --user --remove ;;
    esac
    case ",$PLATFORMS," in
      *,opencode,*) bash "$REPO/adapters/opencode/install.sh" --user --remove ;;
    esac
  fi
  sed -i.bak 's/^ENABLED=.*/ENABLED=0/' "$STATE_FILE"
  rm -f "$STATE_FILE.bak"
  echo "Disabled dev-qual ($SCOPE scope). State kept at $STATE_FILE — run 'toggle.sh enable' to restore."
}

# Undo setup-hooks.sh: unset core.hooksPath if it points here, else remove
# any copied hook that's still byte-identical to this checkout's (warn and
# leave one that was edited).
undo_git_hooks() {
  git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1 || return 0
  local hooks_path
  hooks_path="$(git -C "$PROJECT" config core.hooksPath || true)"
  if [ "$hooks_path" = "$REPO/scripts/hooks" ]; then
    git -C "$PROJECT" config --unset core.hooksPath
    return 0
  fi
  local git_hooks name
  git_hooks="$PROJECT/$(git -C "$PROJECT" rev-parse --git-path hooks)"
  for hook in "$REPO"/scripts/hooks/*; do
    name="$(basename "$hook")"
    [ -f "$git_hooks/$name" ] || continue
    if diff -q "$hook" "$git_hooks/$name" >/dev/null 2>&1; then
      rm -f "$git_hooks/$name"
    else
      echo "Warning: $git_hooks/$name differs from $hook — left in place (looks edited)." >&2
    fi
  done
}

# Re-run install.sh from the state file: it rewires everything and rewrites
# the state file with ENABLED=1.
do_enable() {
  if [ "$SCOPE" = "project" ]; then
    bash "$REPO/install.sh" --from-config --project "$PROJECT"
  else
    bash "$REPO/install.sh" --from-config --user
  fi
}

# Print the state file's recorded choices, then (when enabled) delegate to
# check-install.sh for drift detail.
do_status() {
  echo "Scope: $SCOPE"
  echo "Enabled: $ENABLED"
  echo "Tier: $TIER"
  echo "Platforms: $PLATFORMS"
  if [ "$ENABLED" != "1" ]; then
    echo "dev-qual is disabled for this scope — skipping check-install.sh."
    return 0
  fi
  if [ "$SCOPE" = "project" ]; then
    bash "$REPO/scripts/check-install.sh" --project "$PROJECT"
  else
    bash "$REPO/scripts/check-install.sh" --user
  fi
}

case "$ACTION" in
  disable) do_disable ;;
  enable) do_enable ;;
  status) do_status ;;
esac
