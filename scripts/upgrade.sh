#!/usr/bin/env bash
# Updates this checkout to its upstream (submodule bump or plain pull), then
# re-runs the installer and check-install.sh against the new version.
#
# Usage: upgrade.sh [--project <dir> | --user]
#   --project <dir>  target repo (project scope; default: parent of this checkout)
#   --user            operate on the user-scope install instead
# Exit code: 2 if not installed; else check-install.sh's exit code.
set -euo pipefail

# `git pull`/submodule update below can rewrite this very file mid-run; bash
# reads scripts incrementally, so the whole body lives in main() and is
# fully parsed before anything executes.
main() {
  local REPO PROJECT="" SCOPE="project"
  REPO="$(cd "$(dirname "$0")/.." && pwd)"
  # shellcheck source-path=SCRIPTDIR
  # shellcheck source=lib/common.sh
  . "$REPO/scripts/lib/common.sh"

  while [ $# -gt 0 ]; do
    case "$1" in
      --project) PROJECT="${2:?--project needs a directory}"; shift ;;
      --user) SCOPE="user" ;;
      --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
    shift
  done

  if [ "$SCOPE" = "project" ]; then
    [ -n "$PROJECT" ] || PROJECT="$(cd "$REPO/.." && pwd)"
    [ -d "$PROJECT" ] || { echo "Project directory not found: $PROJECT" >&2; exit 2; }
    PROJECT="$(cd "$PROJECT" && pwd)"
  fi

  local STATE_FILE
  STATE_FILE="$(state_file_for "$SCOPE" "$PROJECT")"
  [ -f "$STATE_FILE" ] || { echo "not installed — run install.sh" >&2; exit 2; }
  local CHECKOUT=""
  # shellcheck disable=SC1090
  . "$STATE_FILE"

  local CHECKOUT_DIR
  if [ "$SCOPE" = "user" ]; then
    CHECKOUT_DIR="$CHECKOUT"
  else
    CHECKOUT_DIR="$PROJECT/$CHECKOUT"
  fi
  CHECKOUT_DIR="$(cd "$CHECKOUT_DIR" && pwd)"

  local OLD_SHA
  OLD_SHA="$(git -C "$CHECKOUT_DIR" rev-parse --short HEAD)"

  if [ "$SCOPE" = "project" ] && git -C "$PROJECT" submodule status -- "$CHECKOUT" 2>/dev/null | grep -q .; then
    git -C "$PROJECT" submodule update --remote -- "$CHECKOUT"
    echo "Updated submodule $CHECKOUT — commit the new pointer in $PROJECT once you're happy with it."
  else
    git -C "$CHECKOUT_DIR" pull --ff-only
  fi

  local NEW_SHA
  NEW_SHA="$(git -C "$CHECKOUT_DIR" rev-parse --short HEAD)"
  echo "dev-qual: $OLD_SHA -> $NEW_SHA"

  if [ "$SCOPE" = "project" ]; then
    bash "$CHECKOUT_DIR/install.sh" --from-config --project "$PROJECT"
    bash "$CHECKOUT_DIR/scripts/check-install.sh" --project "$PROJECT"
  else
    bash "$CHECKOUT_DIR/install.sh" --from-config --user
    bash "$CHECKOUT_DIR/scripts/check-install.sh" --user
  fi
}

main "$@"; exit
