#!/usr/bin/env bash
# pi adapter: installs (or removes) this checkout as a pi package via
# `pi install <path>`. Local-path packages are "loaded from the resolved
# path without copying" (pi's packages.md), so this points pi straight at
# the checkout — no files are copied here, and scripts/upgrade.sh's normal
# `git pull`/submodule update covers pi the same way it covers everything
# else in this repo.
#
# Usage: install.sh [--project <dir> | --user] [--remove]
#   --project <dir>  target repo (project scope; writes .pi/settings.json
#                     there via `pi install --local`)
#   --user            install into the user's ~/.pi/agent/settings.json
#   --remove          undo (`pi remove <checkout>`)
# If `pi` isn't on PATH, prints the command to run later and exits 0 — pi
# may simply not be installed yet, which isn't a failure of this installer.
set -euo pipefail

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ADAPTER_DIR/../.." && pwd)"

PROJECT=""; USER_SCOPE=0; REMOVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift ;;
    --user) USER_SCOPE=1 ;;
    --remove) REMOVE=1 ;;
    --help|-h) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$USER_SCOPE" = 1 ]; then
  SCOPE="user"
else
  [ -n "$PROJECT" ] || { echo "--project is required (or use --user)" >&2; exit 2; }
  [ -d "$PROJECT" ] || { echo "Project directory not found: $PROJECT" >&2; exit 2; }
  PROJECT="$(cd "$PROJECT" && pwd)"
  SCOPE="project"
fi

# Build the exact `pi install`/`pi remove` command for this scope, so it can
# either be run now or printed for the user to run once pi is installed.
if [ "$SCOPE" = "project" ]; then
  INSTALL_CMD=(pi install "$REPO" --local)
  REMOVE_CMD=(pi remove "$REPO" --local)
  RUN_DIR="$PROJECT"
else
  INSTALL_CMD=(pi install "$REPO")
  REMOVE_CMD=(pi remove "$REPO")
  RUN_DIR="$PWD"
fi

if ! command -v pi >/dev/null 2>&1; then
  if [ "$REMOVE" = 1 ]; then
    echo "pi not found on PATH — nothing to remove. If pi is installed later, run:"
    echo "  ${REMOVE_CMD[*]}"
  else
    echo "pi not found on PATH — install it from https://github.com/badlogic/pi-mono, then run:"
    echo "  (cd $RUN_DIR && ${INSTALL_CMD[*]})"
  fi
  exit 0
fi

if [ "$REMOVE" = 1 ]; then
  (cd "$RUN_DIR" && "${REMOVE_CMD[@]}")
  echo "Removed pi adapter ($SCOPE scope)."
else
  (cd "$RUN_DIR" && "${INSTALL_CMD[@]}")
  echo "Installed pi adapter ($SCOPE scope): $REPO"
fi
