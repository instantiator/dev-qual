#!/usr/bin/env bash
# Reports how a project's (or the user's) installed dev-qual files differ
# from this checkout — the drift that builds up after `git submodule update`.
#
# PASS = matches this checkout. FAIL = differs (upstream moved, or you
# customised it). SKIP = not installed, so nothing to compare.
#
# Usage: check-install.sh [--project <dir> | --user]
# Exit code: 1 if anything differs, else 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PROJECT=""; SCOPE="project"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --user) SCOPE="user" ;;
    --help|-h) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ "$SCOPE" = "project" ]; then
  # Default to the repo this checkout sits inside, matching install.sh
  [ -n "$PROJECT" ] || PROJECT="$(cd "$REPO/.." && pwd)"
  AGENTS="$PROJECT/AGENTS.md"
  CLAUDE_MD="$PROJECT/CLAUDE.md"
  SKILLS_DIR="$PROJECT/.claude/skills"
  SETTINGS="$PROJECT/.claude/settings.json"
  echo "check-install.sh — comparing $PROJECT (project scope) against $REPO"
else
  AGENTS="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/AGENTS.md"
  CLAUDE_MD="$HOME/.claude/CLAUDE.md"
  SKILLS_DIR="$HOME/.claude/skills"
  SETTINGS="$HOME/.claude/settings.json"
  echo "check-install.sh — comparing user scope ($HOME) against $REPO"
fi

# 1. The AGENTS.md tier entry block, against every tier's rendered content
#    for this scope (we don't record which tier was chosen elsewhere)
if [ ! -f "$AGENTS" ]; then
  record_result "AGENTS.md" SKIP "not installed — run install.sh"
elif ! grep -qE '<!-- dev-(qual|environment):start -->' "$AGENTS"; then
  record_result "AGENTS.md" SKIP "no dev-qual block — run install.sh"
else
  # dev-environment is the pre-rename marker: a block still using it will not
  # match either tier file, so it is reported as drift to be re-installed.
  installed="$(block_between "$AGENTS" '<!-- dev-(qual|environment):start -->' '<!-- dev-(qual|environment):end -->')"
  matched=""
  for tier in local remote; do
    rendered="$(render_entry "$REPO/agents-files/$tier/AGENTS.md" "$SCOPE" "$REPO")"
    if [ "$installed" = "$rendered" ]; then
      matched="$tier"
    fi
  done
  if [ -n "$matched" ]; then
    record_result "AGENTS.md" PASS
    echo "   tier: $matched"
  else
    record_result "AGENTS.md" FAIL "block differs from both tier files — diff against $REPO/agents-files/*/AGENTS.md, keep your edits, then re-run install.sh"
  fi
fi

# 2. The OpenCode skills routing block: every current skill must be listed
if [ -f "$AGENTS" ] && grep -qE '<!-- dev-(qual|environment):skills:start -->' "$AGENTS"; then
  missing=""
  while read -r line; do
    name="${line#- [}"; name="${name%%]*}"
    if [ "$SCOPE" = "user" ]; then
      expected="$REPO/skills/$name/SKILL.md"
    else
      expected="skills/$name/SKILL.md"
    fi
    grep -q "$expected" "$AGENTS" || missing="$missing $name"
  done <<EOF
$(grep '^- \[' "$REPO/skills/index.md")
EOF
  if [ -z "$missing" ]; then
    record_result "AGENTS.md:skills" PASS
  else
    record_result "AGENTS.md:skills" FAIL "missing skills:$missing — re-run adapters/opencode/install.sh"
  fi
else
  record_result "AGENTS.md:skills" SKIP "no skills routing block (OpenCode adapter not installed)"
fi

# 3. CLAUDE.md — compare the marked block against the rendered template
if [ "$SCOPE" = "project" ] && [ ! -d "$PROJECT/.claude" ]; then
  record_result "CLAUDE.md" SKIP "Claude Code adapter not installed"
elif [ ! -f "$CLAUDE_MD" ]; then
  record_result "CLAUDE.md" FAIL "missing — run adapters/claude-code/install.sh"
elif ! grep -qE '<!-- dev-(qual|environment):start -->' "$CLAUDE_MD"; then
  record_result "CLAUDE.md" FAIL "no dev-qual block — re-run adapters/claude-code/install.sh"
else
  installed="$(block_between "$CLAUDE_MD" '<!-- dev-(qual|environment):start -->' '<!-- dev-(qual|environment):end -->')"
  rendered="$(render_entry "$REPO/agents-files/remote/CLAUDE.md" "$SCOPE" "$REPO")"
  if [ "$installed" = "$rendered" ]; then
    record_result "CLAUDE.md" PASS
  else
    record_result "CLAUDE.md" FAIL "block differs — diff against $REPO/agents-files/remote/CLAUDE.md and merge what you want to keep"
  fi
fi

# 4. Skills. Symlinks into this checkout are always current; a real directory
#    or a broken link is a copy that has stopped tracking upstream.
if [ ! -d "$SKILLS_DIR" ]; then
  record_result "skills" SKIP "Claude Code adapter not installed"
else
  stale=""; absent=""
  for skill in "$REPO"/skills/*/; do
    name="$(basename "$skill")"
    if [ ! -e "$SKILLS_DIR/$name" ] && [ ! -L "$SKILLS_DIR/$name" ]; then
      absent="$absent $name"
    elif [ ! -L "$SKILLS_DIR/$name" ] || [ ! -d "$SKILLS_DIR/$name" ]; then
      stale="$stale $name"
    fi
  done
  if [ -z "$stale" ] && [ -z "$absent" ]; then
    record_result "skills" PASS
  else
    record_result "skills" FAIL "re-run adapters/claude-code/install.sh —${absent:+ not installed:$absent}${stale:+ not a working symlink:$stale}"
  fi
fi

# 5. The dev-qual agent hooks in settings.json
if [ ! -f "$SETTINGS" ]; then
  record_result "settings.json" SKIP "no settings.json (agent hooks are optional)"
elif grep -q 'agent-hook.sh' "$SETTINGS"; then
  record_result "settings.json" PASS
else
  record_result "settings.json" FAIL "agent hooks absent — re-run adapters/claude-code/install.sh to add them"
fi

# 6. Git hooks (project scope only — hooks are per repo, not per user)
if [ "$SCOPE" = "user" ]; then
  : # nothing to check
elif ! git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
  record_result "git-hooks" SKIP "$PROJECT is not a git repository"
elif [ "$(state_value "$(state_file_for project "$PROJECT")" HOOKS)" = "no" ]; then
  record_result "git-hooks" SKIP "not chosen at install (HOOKS=no in .dev-qual.env)"
else
  HOOKS_PATH="$(git -C "$PROJECT" config core.hooksPath || true)"
  if [ "$HOOKS_PATH" = "$REPO/scripts/hooks" ]; then
    record_result "git-hooks" PASS
    echo "   core.hooksPath -> this checkout, so hooks are always current"
  else
    GIT_HOOKS="$PROJECT/$(git -C "$PROJECT" rev-parse --git-path hooks)"
    differing=""
    for hook in "$REPO"/scripts/hooks/*; do
      name="$(basename "$hook")"
      if [ ! -f "$GIT_HOOKS/$name" ]; then
        differing="$differing $name(absent)"
      elif ! diff -q "$hook" "$GIT_HOOKS/$name" >/dev/null 2>&1; then
        differing="$differing $name"
      fi
    done
    if [ -z "$differing" ]; then
      record_result "git-hooks" PASS
    else
      record_result "git-hooks" FAIL "copied hooks differ:$differing — re-run setup-hooks.sh --copy, or diff them first if you edited them"
    fi
  fi
fi

# 7. pi package install — SKIP if pi wasn't chosen, or isn't on PATH; else
#    inspect its settings file directly (never run `pi`) for this checkout.
STATE_FILE="$(state_file_for "$SCOPE" "$PROJECT")"
PLATFORMS="$(state_value "$STATE_FILE" PLATFORMS)"
case ",$PLATFORMS," in
  *,pi,*)
    if ! has_cmd pi; then
      record_result "pi" SKIP "pi not on PATH — install from https://github.com/badlogic/pi-mono"
    else
      if [ "$SCOPE" = "project" ]; then
        PI_SETTINGS="$PROJECT/.pi/settings.json"
      else
        PI_SETTINGS="$HOME/.pi/agent/settings.json"
      fi
      if [ ! -f "$PI_SETTINGS" ]; then
        record_result "pi" FAIL "no $PI_SETTINGS — re-run adapters/pi/install.sh"
      elif node -e '
          // pi records local packages relative to its settings directory
          // (and may store an entry as { source }), so resolve before comparing.
          const fs = require("fs"), path = require("path");
          const [settingsPath, checkout] = process.argv.slice(1);
          const packages = JSON.parse(fs.readFileSync(settingsPath, "utf8")).packages || [];
          const real = (p) => { try { return fs.realpathSync(p); } catch { return p; } };
          const want = real(checkout);
          const found = packages.some((entry) => {
            const source = typeof entry === "string" ? entry : entry && entry.source;
            return typeof source === "string"
              && real(path.resolve(path.dirname(settingsPath), source)) === want;
          });
          process.exit(found ? 0 : 1);
        ' "$PI_SETTINGS" "$REPO"; then
        record_result "pi" PASS
      else
        record_result "pi" FAIL "$PI_SETTINGS does not reference $REPO — re-run adapters/pi/install.sh"
      fi
    fi
    ;;
  *) record_result "pi" SKIP "pi not in PLATFORMS" ;;
esac

# 7b. The .prettierignore submodules block, against the project's submodules now
if [ "$SCOPE" = "project" ] && uses_prettier "$PROJECT"; then
  installed="$(block_between "$PROJECT/.prettierignore" '<!-- dev-qual:submodules:start -->' '<!-- dev-qual:submodules:end -->' 2>/dev/null || true)"
  if [ "$installed" = "$(ignored_paths "$PROJECT" "$REPO")" ]; then
    record_result ".prettierignore" PASS
  else
    record_result ".prettierignore" FAIL "submodules block is missing or stale — re-run install.sh --from-config"
  fi
fi

# 8. The state file itself
if [ -f "$STATE_FILE" ]; then
  record_result "state file" PASS
else
  record_result "state file" FAIL "run install.sh"
fi

echo ""
report_results
