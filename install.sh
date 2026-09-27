#!/usr/bin/env bash
# Interactive installer: wires dev-qual guidance, skills, and hooks
# into a target project (project scope) or into your home directory
# (user scope). Re-runnable; merges rather than clobbers. Records the
# choices made in a state file so `--from-config` can reproduce them.
#
# Usage: install.sh [--project <dir>] [--user] [--scope project|user]
#                    [--tier local|remote] [--platforms <list>]
#                    [--hooks yes|no] [--yes] [--from-config]
#   --project <dir>    target repo (project scope; default: parent of this checkout)
#   --user              shorthand for --scope user
#   --scope             project (default) or user
#   --tier               agent tier for AGENTS.md: local (small-context) or remote
#   --platforms          comma-separated: claude,opencode or none
#   --hooks yes|no       install git hooks (project scope only)
#   --yes                accept defaults for anything not given (non-interactive)
#   --from-config        read all answers from the scope's state file (non-interactive)
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=scripts/lib/common.sh
. "$REPO/scripts/lib/common.sh"

PROJECT=""; SCOPE=""; TIER=""; PLATFORMS=""; HOOKS=""; ASSUME_YES=0; FROM_CONFIG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift ;;
    --user) SCOPE="user" ;;
    --scope) SCOPE="${2:?}"; shift ;;
    --tier) TIER="${2:?}"; shift ;;
    --platforms) PLATFORMS="${2:?}"; shift ;;
    --hooks) HOOKS="${2:?}"; shift ;;
    --yes) ASSUME_YES=1 ;;
    --from-config) FROM_CONFIG=1 ;;
    --help|-h) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
# --from-config is non-interactive: every unset answer takes its default,
# then gets overridden by whatever the state file has.
[ "$FROM_CONFIG" = 1 ] && ASSUME_YES=1

# Ask a question unless the answer was provided or --yes chose the default:
# ask <current-value> <prompt> <default> -> echoes the answer
ask() {
  local current="$1" prompt="$2" default="$3" answer
  if [ -n "$current" ]; then echo "$current"; return; fi
  if [ "$ASSUME_YES" = 1 ]; then echo "$default"; return; fi
  read -r -p "$prompt [$default]: " answer </dev/tty
  echo "${answer:-$default}"
}

# Print $1 relative to $2 when it is nested under it, else print it as-is.
rel_path() {
  case "$1" in
    "$2"/*) echo "${1#"$2"/}" ;;
    "$2") echo "." ;;
    *) echo "$1" ;;
  esac
}

# 1. Scope
SCOPE="$(ask "$SCOPE" "Install scope — project or user?" "project")"
case "$SCOPE" in project|user) ;; *) echo "Scope must be 'project' or 'user'" >&2; exit 2 ;; esac

# 2. Target project (project scope only; default: the repo this checkout sits inside)
if [ "$SCOPE" = "project" ]; then
  DEFAULT_PROJECT="$(cd "$REPO/.." && pwd)"
  PROJECT="$(ask "$PROJECT" "Install into which project directory?" "$DEFAULT_PROJECT")"
  [ -d "$PROJECT" ] || { echo "Project directory not found: $PROJECT" >&2; exit 2; }
  PROJECT="$(cd "$PROJECT" && pwd)"  # canonicalise so CHECKOUT's relative path is exact
  if ! git -C "$PROJECT" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Warning: $PROJECT is not a git repository — hooks cannot be installed." >&2
  fi
  echo "Target: $PROJECT"
fi

STATE_FILE="$(state_file_for "$SCOPE" "$PROJECT")"
if [ "$FROM_CONFIG" = 1 ]; then
  [ -f "$STATE_FILE" ] || { echo "--from-config: no state file at $STATE_FILE" >&2; exit 2; }
  # shellcheck disable=SC1090
  . "$STATE_FILE"
fi

# 3. Tier for the AGENTS.md entry file
TIER="$(ask "$TIER" "Agent tier for AGENTS.md — local (small-context) or remote?" "local")"
case "$TIER" in local|remote) ;; *) echo "Tier must be 'local' or 'remote'" >&2; exit 2 ;; esac

# 4. Platforms
PLATFORMS="$(ask "$PLATFORMS" "Agent platforms to wire up (claude,opencode or none)?" "claude,opencode")"

# 5. The tier entry block. Project scope: install.sh always owns AGENTS.md.
#    User scope: the tier block only exists for OpenCode, so the OpenCode
#    adapter (step 6) owns writing (and later, removing) it.
if [ "$SCOPE" = "project" ]; then
  ENTRY_TMP="$(mktemp)"
  render_entry "$REPO/agents-files/$TIER/AGENTS.md" "$SCOPE" "$REPO" >"$ENTRY_TMP"
  merge_block "$PROJECT/AGENTS.md" "dev-qual" "$ENTRY_TMP"
  rm -f "$ENTRY_TMP"
fi

# 6. Platform adapters
CLAUDE_ARGS=(); OPENCODE_ARGS=()
if [ "$SCOPE" = "project" ]; then
  CLAUDE_ARGS=(--project "$PROJECT")
  OPENCODE_ARGS=(--project "$PROJECT")
else
  CLAUDE_ARGS=(--user)
  OPENCODE_ARGS=(--user --tier "$TIER")
fi
[ "$ASSUME_YES" = 1 ] && CLAUDE_ARGS[${#CLAUDE_ARGS[@]}]="--yes"
case ",$PLATFORMS," in *,claude,*) bash "$REPO/adapters/claude-code/install.sh" "${CLAUDE_ARGS[@]}" ;; esac
case ",$PLATFORMS," in *,opencode,*) bash "$REPO/adapters/opencode/install.sh" "${OPENCODE_ARGS[@]}" ;; esac

# 7. Git hooks (project scope only — hooks are per repo)
if [ "$SCOPE" = "project" ]; then
  HOOKS="$(ask "$HOOKS" "Install git hooks (pre-commit/pre-push quality gate)?" "yes")"
  if [ "$HOOKS" = "yes" ]; then
    bash "$REPO/scripts/setup-hooks.sh" --project "$PROJECT"
  fi
else
  HOOKS="no"
fi

# 8. Write the state file so `--from-config` and check-install.sh can find
#    what was chosen. CHECKOUT is relative to the project for project scope,
#    absolute for user scope.
if [ "$SCOPE" = "project" ]; then
  CHECKOUT="$(rel_path "$REPO" "$PROJECT")"
else
  CHECKOUT="$REPO"
fi
mkdir -p "$(dirname "$STATE_FILE")"
{
  printf 'SCOPE=%q\n' "$SCOPE"
  printf 'TIER=%q\n' "$TIER"
  printf 'PLATFORMS=%q\n' "$PLATFORMS"
  printf 'HOOKS=%q\n' "$HOOKS"
  printf 'CHECKOUT=%q\n' "$CHECKOUT"
  printf 'ENABLED=%q\n' "1"
} >"$STATE_FILE"
echo "Wrote $STATE_FILE"

# 9. Report
echo ""
echo "== Installed ($SCOPE scope) =="
echo "- Tier: $TIER"
echo "- Platforms: $PLATFORMS"
if [ "$SCOPE" = "project" ]; then
  echo "- Git hooks: $HOOKS"
fi
echo ""
echo "Next steps:"
if [ "$SCOPE" = "project" ]; then
  echo "  1. Review $PROJECT/AGENTS.md (and CLAUDE.md if created)"
  echo "  2. Run: $REPO/scripts/check-prereqs.sh --project $PROJECT   (add --install to fetch what's missing)"
  echo "  3. Run: $REPO/scripts/check.sh --project $PROJECT"
  echo ""
  echo "Later, after updating the submodule:"
  echo "  $REPO/scripts/check-install.sh --project $PROJECT   (reports what has drifted)"
else
  echo "  1. Review $STATE_FILE"
  echo "  Git hooks are per repo: run $REPO/scripts/setup-hooks.sh --project <repo> in each repo you want gated."
  echo ""
  echo "Later, after updating the checkout:"
  echo "  $REPO/scripts/check-install.sh --user   (reports what has drifted)"
fi
