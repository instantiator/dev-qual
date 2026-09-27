#!/usr/bin/env bash
# Non-blocking check for whether this checkout is behind its upstream.
# Runs at every agent session start, so it must never prompt or fetch
# synchronously: it compares against whatever origin/HEAD (or origin/main)
# was last fetched, and kicks off a background fetch when that's stale —
# so a fresh upstream commit is only reported at the NEXT session. That
# trade-off is what keeps this fast and safe to run unattended.
#
# Usage: check-updates.sh [--quiet]
#   --quiet  print nothing when there is no update (still reports one)
# Exit code: always 0 (2 on bad arguments).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) QUIET=1 ;;
    --help|-h) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# No git work tree, or no origin remote: nothing to compare against.
if ! git -C "$REPO" rev-parse --show-toplevel >/dev/null 2>&1 \
    || ! git -C "$REPO" remote get-url origin >/dev/null 2>&1; then
  [ "$QUIET" = 1 ] || echo "no upstream to compare against"
  exit 0
fi

# Prefer origin/HEAD (the remote's default branch); fall back to origin/main.
UPSTREAM=""
if git -C "$REPO" rev-parse --verify -q origin/HEAD >/dev/null; then
  UPSTREAM="origin/HEAD"
elif git -C "$REPO" rev-parse --verify -q origin/main >/dev/null; then
  UPSTREAM="origin/main"
fi
if [ -z "$UPSTREAM" ]; then
  [ "$QUIET" = 1 ] || echo "no upstream to compare against"
  exit 0
fi

BEHIND="$(git -C "$REPO" rev-list --count HEAD.."$UPSTREAM" 2>/dev/null || echo 0)"
if [ "$BEHIND" -gt 0 ]; then
  UPGRADE="$REPO/scripts/upgrade.sh"
  # Guess --user: only when the user-scope state file's CHECKOUT is this
  # checkout, and no project-scope .dev-qual.env in the current git
  # toplevel points here instead. Simple heuristic, ok to be wrong either way.
  FLAG=""
  USER_STATE="${XDG_CONFIG_HOME:-$HOME/.config}/dev-qual/config.env"
  if [ -f "$USER_STATE" ]; then
    CHECKOUT=""
    # shellcheck disable=SC1090
    . "$USER_STATE"
    USER_CHECKOUT="$CHECKOUT"
    PROJECT_TOPLEVEL="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null || true)"
    PROJECT_POINTS_HERE=0
    if [ -n "$PROJECT_TOPLEVEL" ] && [ -f "$PROJECT_TOPLEVEL/.dev-qual.env" ]; then
      CHECKOUT=""
      # shellcheck disable=SC1090,SC1091
      . "$PROJECT_TOPLEVEL/.dev-qual.env"
      [ "$(cd "$PROJECT_TOPLEVEL/$CHECKOUT" 2>/dev/null && pwd)" = "$REPO" ] && PROJECT_POINTS_HERE=1
    fi
    if [ "$USER_CHECKOUT" = "$REPO" ] && [ "$PROJECT_POINTS_HERE" = 0 ]; then
      FLAG=" --user"
    fi
  fi
  echo "dev-qual update available: $BEHIND new commit(s) upstream. Offer the user: $UPGRADE$FLAG"
elif [ "$QUIET" != 1 ]; then
  echo "dev-qual is up to date"
fi

# Refresh in the background when the last fetch was over a day ago, so the
# NEXT run sees current data — never block this one on a network call.
GIT_DIR="$(git -C "$REPO" rev-parse --absolute-git-dir)"
STAMP="$GIT_DIR/dev-qual-last-fetch"
if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mmin +1440 2>/dev/null)" ]; then
  touch "$STAMP"
  ( git -C "$REPO" fetch --quiet origin >/dev/null 2>&1 & )
fi

exit 0
