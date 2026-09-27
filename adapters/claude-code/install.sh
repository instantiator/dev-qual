#!/usr/bin/env bash
# Claude Code adapter: symlinks skills, merges the CLAUDE.md block, and
# manages the dev-qual agent hooks in settings.json — for a project, or
# (with --user) for the current user's global Claude Code config. This
# adapter owns everything it installs (skills symlinks, CLAUDE.md block,
# hooks); the AGENTS.md tier/skills blocks are owned by install.sh and the
# OpenCode adapter.
#
# Usage: install.sh (--project <dir> | --user) [--yes] [--remove]
#   --project <dir>  target repo
#   --user            install into $HOME/.claude instead of a project
#   --yes             accept the hooks prompt without asking
#   --remove          undo this adapter's install (leaves unrelated content)
set -euo pipefail

ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$ADAPTER_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../scripts/lib/common.sh
. "$REPO/scripts/lib/common.sh"

PROJECT=""; USER_SCOPE=0; ASSUME_YES=0; REMOVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift ;;
    --user) USER_SCOPE=1 ;;
    --yes) ASSUME_YES=1 ;;
    --remove) REMOVE=1 ;;
    --help|-h) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$USER_SCOPE" = 1 ]; then
  SCOPE="user"
  SKILLS_DIR="$HOME/.claude/skills"
  CLAUDE_MD="$HOME/.claude/CLAUDE.md"
  SETTINGS="$HOME/.claude/settings.json"
  CMD_BASE="bash $REPO/scripts/agent-hook.sh"
else
  [ -n "$PROJECT" ] || { echo "--project is required (or use --user)" >&2; exit 2; }
  [ -d "$PROJECT" ] || { echo "Project directory not found: $PROJECT" >&2; exit 2; }
  PROJECT="$(cd "$PROJECT" && pwd)"  # canonicalise so the relative hook path is exact
  SCOPE="project"
  SKILLS_DIR="$PROJECT/.claude/skills"
  CLAUDE_MD="$PROJECT/CLAUDE.md"
  SETTINGS="$PROJECT/.claude/settings.json"
  CHECKOUT_REL="${REPO#"$PROJECT"/}"
  # Literal $CLAUDE_PROJECT_DIR — expanded by Claude Code at runtime, not here.
  # shellcheck disable=SC2016 # $CLAUDE_PROJECT_DIR is literal, expanded by Claude Code at runtime
  CMD_BASE='bash "$CLAUDE_PROJECT_DIR"/'"$CHECKOUT_REL"'/scripts/agent-hook.sh'
fi

# Merge dev-qual's three hook events into settings.json, dropping any
# previous entry of ours (or the pre-rename static hook) first so re-running
# never duplicates: add_hooks <settings-file>
add_hooks() {
  local settings="$1"
  mkdir -p "$(dirname "$settings")"
  [ -f "$settings" ] || echo '{}' >"$settings"
  node -e '
    const fs = require("fs");
    const [settingsPath, cmdBase, scope] = process.argv.slice(1);
    const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
    const before = JSON.stringify(settings);
    settings.hooks = settings.hooks || {};
    const isOurs = (h) => typeof h.command === "string" && (
      h.command.includes("agent-hook.sh") ||
      h.command.includes("dev-qual/scripts/check.sh") ||
      h.command.includes("dev-environment/scripts/check.sh")
    );
    const events = [
      ["PostToolUse", "Edit|Write|MultiEdit", "post-edit"],
      ["SessionStart", null, "session-start"],
      ["Stop", null, "stop"],
    ];
    for (const [event, matcher, name] of events) {
      const existing = settings.hooks[event] || [];
      const kept = existing.filter((entry) => !(entry.hooks || []).some(isOurs));
      const command = cmdBase + " " + name + " --scope " + scope;
      const entry = matcher
        ? { matcher, hooks: [{ type: "command", command }] }
        : { hooks: [{ type: "command", command }] };
      settings.hooks[event] = kept.concat([entry]);
    }
    // Rewrite only on a real change, keeping the project formatter'"'"'s layout
    if (JSON.stringify(settings) === before) {
      console.log("dev-qual agent hooks already current in " + settingsPath);
    } else {
      fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
      console.log("Merged dev-qual agent hooks into " + settingsPath);
    }
  ' "$settings" "$CMD_BASE" "$SCOPE"
}

# Remove dev-qual's hook entries (and the pre-rename static hook) from
# settings.json, dropping now-empty event arrays and hooks object:
# remove_hooks <settings-file>
remove_hooks() {
  local settings="$1"
  [ -f "$settings" ] || return 0
  node -e '
    const fs = require("fs");
    const [settingsPath] = process.argv.slice(1);
    const settings = JSON.parse(fs.readFileSync(settingsPath, "utf8"));
    if (settings.hooks) {
      const isOurs = (h) => typeof h.command === "string" && (
        h.command.includes("agent-hook.sh") ||
        h.command.includes("dev-qual/scripts/check.sh") ||
        h.command.includes("dev-environment/scripts/check.sh")
      );
      for (const event of ["PostToolUse", "SessionStart", "Stop"]) {
        if (!settings.hooks[event]) continue;
        settings.hooks[event] = settings.hooks[event]
          .map((entry) => ({ ...entry, hooks: (entry.hooks || []).filter((h) => !isOurs(h)) }))
          .filter((entry) => entry.hooks.length > 0);
        if (settings.hooks[event].length === 0) delete settings.hooks[event];
      }
      if (Object.keys(settings.hooks).length === 0) delete settings.hooks;
    }
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + "\n");
    console.log("Removed dev-qual agent hooks from " + settingsPath);
  ' "$settings"
}

if [ "$REMOVE" = 1 ]; then
  # Only drop symlinks that point into this checkout; leave anything else.
  if [ -d "$SKILLS_DIR" ]; then
    for link in "$SKILLS_DIR"/*; do
      [ -L "$link" ] || continue
      case "$(readlink "$link")" in
        "$REPO"/*) rm -f "$link" ;;
      esac
    done
  fi
  remove_block "$CLAUDE_MD" "dev-qual"
  remove_hooks "$SETTINGS"
  echo "Removed Claude Code adapter ($SCOPE scope)."
  exit 0
fi

# Symlink each skill directory into place
mkdir -p "$SKILLS_DIR"
COUNT=0
for skill in "$REPO"/skills/*/; do
  name="$(basename "$skill")"
  ln -sfn "$skill" "$SKILLS_DIR/$name"
  COUNT=$((COUNT + 1))
done
echo "Linked $COUNT skills into $SKILLS_DIR"

# CLAUDE.md: merge the block. A pre-existing file that is byte-identical to
# the raw template (the old cp-based install) is migrated cleanly, with no
# NOTE; any other pre-existing content is kept and the block appended.
ENTRY_TMP="$(mktemp)"
render_entry "$REPO/agents-files/remote/CLAUDE.md" "$SCOPE" "$REPO" >"$ENTRY_TMP"
if [ -f "$CLAUDE_MD" ] && ! grep -qE '<!-- dev-(qual|environment):start -->' "$CLAUDE_MD" \
    && diff -q "$CLAUDE_MD" "$REPO/agents-files/remote/CLAUDE.md" >/dev/null 2>&1; then
  rm -f "$CLAUDE_MD"
fi
merge_block "$CLAUDE_MD" "dev-qual" "$ENTRY_TMP"
rm -f "$ENTRY_TMP"

# Hooks: offer to install, then generate and merge via node
if [ "$ASSUME_YES" = 1 ]; then
  REPLY="y"
else
  read -r -p "Add the dev-qual agent hooks (post-edit check, ...) to $SETTINGS? [y/N]: " REPLY </dev/tty
fi
if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
  if command -v node >/dev/null 2>&1; then
    add_hooks "$SETTINGS"
  else
    echo "node not found — cannot merge hooks into $SETTINGS."
  fi
fi
