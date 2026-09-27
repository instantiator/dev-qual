#!/usr/bin/env bash
# OpenCode (and other AGENTS.md-reading agents) adapter: injects the skills
# routing block into AGENTS.md — for a project, or (with --user) into the
# user's global OpenCode config. At user scope, the tier entry block only
# exists for OpenCode, so this adapter also owns writing and removing it
# (project scope's tier block is install.sh's job, in the project AGENTS.md).
#
# Usage: install.sh (--project <dir> | --user) [--tier local|remote] [--remove]
#   --project <dir>  target repo
#   --user            install into $XDG_CONFIG_HOME/opencode instead
#   --tier            required with --user (install only): which tier block to write
#   --remove          undo this adapter's install (leaves unrelated content)
set -euo pipefail

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ADAPTER_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../scripts/lib/common.sh
. "$REPO/scripts/lib/common.sh"

PROJECT=""; USER_SCOPE=0; TIER=""; REMOVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift ;;
    --user) USER_SCOPE=1 ;;
    --tier) TIER="${2:?}"; shift ;;
    --remove) REMOVE=1 ;;
    --help|-h) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$USER_SCOPE" = 1 ]; then
  SCOPE="user"
  TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"
  SKILL_PATH_PREFIX="$REPO/skills/"
else
  [ -n "$PROJECT" ] || { echo "--project is required (or use --user)" >&2; exit 2; }
  SCOPE="project"
  TARGET="$PROJECT/AGENTS.md"
  SKILL_PATH_PREFIX="dev-qual/skills/"
fi

if [ "$REMOVE" = 1 ]; then
  remove_block "$TARGET" "dev-qual:skills"
  # The tier block only lives here for user scope; project scope's tier
  # block belongs to install.sh and is left alone.
  [ "$SCOPE" = "user" ] && remove_block "$TARGET" "dev-qual"
  echo "Removed OpenCode adapter ($SCOPE scope)."
  exit 0
fi

# User scope: also write the tier entry block (project scope leaves this to
# install.sh, since it targets the same AGENTS.md file there).
if [ "$SCOPE" = "user" ]; then
  [ -n "$TIER" ] || { echo "--tier is required with --user" >&2; exit 2; }
  case "$TIER" in local|remote) ;; *) echo "Tier must be 'local' or 'remote'" >&2; exit 2 ;; esac
  ENTRY_TMP="$(mktemp)"
  render_entry "$REPO/agents-files/$TIER/AGENTS.md" "$SCOPE" "$REPO" >"$ENTRY_TMP"
  merge_block "$TARGET" "dev-qual" "$ENTRY_TMP"
  rm -f "$ENTRY_TMP"
fi

# Skills routing block, generated from skills/index.md
SKILLS_TMP="$(mktemp)"
{
  echo ''
  echo '## Skills (multi-step task playbooks)'
  echo ''
  echo 'Match the task against a trigger below, then follow that SKILL.md literally.'
  echo ''
  grep '^- \[' "$REPO/skills/index.md" | sed "s|(\\(.*\\))|($SKILL_PATH_PREFIX\\1)|"
} >"$SKILLS_TMP"
merge_block "$TARGET" "dev-qual:skills" "$SKILLS_TMP"
rm -f "$SKILLS_TMP"
