#!/usr/bin/env bash
# Installs the dev-qual git hooks (pre-commit, pre-push) into a project,
# by pointing core.hooksPath at this repo's hooks directory. Idempotent.
#
# Usage: setup-hooks.sh [--project <dir>] [--copy]
#   --copy  copy hooks into .git/hooks instead of setting core.hooksPath
#           (use when the project has its own hooks to keep)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/hooks"

PROJECT="."; COPY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --copy) COPY=1 ;;
    --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

if ! git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "$PROJECT is not a git repository" >&2
  exit 1
fi

if [ "$COPY" = 1 ]; then
  # Absolute: --git-path is relative to the project, not to this script's cwd
  GIT_HOOKS="$(git -C "$PROJECT" rev-parse --path-format=absolute --git-path hooks)"
  mkdir -p "$GIT_HOOKS"
  for hook in "$HOOKS_DIR"/*; do
    cp "$hook" "$GIT_HOOKS/$(basename "$hook")"
    chmod +x "$GIT_HOOKS/$(basename "$hook")"
    echo "Copied $(basename "$hook") -> $GIT_HOOKS/"
  done
else
  git -C "$PROJECT" config core.hooksPath "$HOOKS_DIR"
  echo "Set core.hooksPath -> $HOOKS_DIR"
  echo "Note: git now ignores $PROJECT/.git/hooks — use --copy instead if the project has its own hooks."
fi

echo "Installed: pre-commit (check.sh --fast), pre-push (full check.sh)."
