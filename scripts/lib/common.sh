#!/usr/bin/env bash
# Shared helpers for dev-qual scripts: project-type detection,
# tool checks, and PASS/FAIL/SKIP result reporting.
# Source this file; do not execute it directly.

# Colour codes (disabled when not a terminal)
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_RESET=""
fi

# True if a command exists on PATH
has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Detect every stack present from marker files, one name per line.
#
# Prints any of "node", "dotnet", "python" — a polyglot repo prints several,
# a repo with no recognised markers prints nothing.
detect_stacks() {
  local dir="${1:-.}"
  if [ -f "$dir/package.json" ]; then
    echo "node"
  fi
  if ls "$dir"/*.sln >/dev/null 2>&1 || ls "$dir"/*.csproj >/dev/null 2>&1 \
    || ls "$dir"/*/*.csproj >/dev/null 2>&1; then
    echo "dotnet"
  fi
  if [ -f "$dir/pyproject.toml" ] || [ -f "$dir/setup.py" ] \
    || [ -f "$dir/requirements.txt" ]; then
    echo "python"
  fi
  return 0
}

# Detect the primary project type: the first stack found, or "unknown".
#
# NB. Kept for callers that handle one stack at a time (run-tests.sh,
# check-prereqs.sh); check.sh uses detect_stacks instead.
detect_project_type() {
  local first
  first="$(detect_stacks "${1:-.}" | head -n 1)"
  echo "${first:-unknown}"
}

# True if package.json in $1 declares an npm script named $2
npm_has_script() {
  local dir="$1" name="$2"
  [ -f "$dir/package.json" ] || return 1
  if has_cmd node; then
    node -e "process.exit(((require('$dir/package.json').scripts||{})['$name'])?0:1)" 2>/dev/null
  else
    # Fallback without node: crude but adequate for a presence check
    grep -q "\"$name\"[[:space:]]*:" "$dir/package.json"
  fi
}

# Result accumulators (parallel arrays: bash 3.2 has no associative arrays)
RESULT_NAMES=()
RESULT_STATES=()
RESULT_HINTS=()

# Record one stage result: record_result <name> <PASS|FAIL|SKIP> [hint]
record_result() {
  RESULT_NAMES[${#RESULT_NAMES[@]}]="$1"
  RESULT_STATES[${#RESULT_STATES[@]}]="$2"
  RESULT_HINTS[${#RESULT_HINTS[@]}]="${3:-}"
}

# Print the content between a pair of marker patterns:
# block_between <file> <start-regex> <end-regex>
block_between() {
  awk -v s="$2" -v e="$3" '
    $0 ~ e { inside = 0 }
    inside { print }
    $0 ~ s { inside = 1 }
  ' "$1"
}

# Merge a marked block into a file, replacing any previous block with the
# same marker (or the pre-rename "dev-environment" variant of it) in place
# — so a file holding several different marker blocks keeps their order
# stable across re-runs — or appending one if the marker is new: merge_block
# <target> <marker> <content-file> [comment-prefix]. The prefix (e.g. "#")
# goes before each marker line, for files where HTML comments aren't
# comments. Creates the target's parent directory.
# If the target already exists with unrelated content (no dev-qual marker
# of any kind), the block is appended and a NOTE is printed so the merge
# gets reviewed.
merge_block() {
  local target="$1" marker="$2" source="$3" prefix="${4:+$4 }" tmp tmp2 legacy newblock placeholder
  mkdir -p "$(dirname "$target")"
  legacy="${marker/dev-qual/dev-environment}"
  newblock="$(mktemp)"
  { echo "$prefix<!-- $marker:start -->"; cat "$source"; echo "$prefix<!-- $marker:end -->"; } >"$newblock"

  if [ -f "$target" ] && grep -qE "<!-- ($marker|$legacy):start -->" "$target"; then
    # Replace the block in place: swap it for a placeholder line, then
    # expand the placeholder into the new block's content.
    placeholder="@@DEV_QUAL_BLOCK@@"
    tmp="$(mktemp)"
    awk -v s="<!-- ($marker|$legacy):start -->" -v e="<!-- ($marker|$legacy):end -->" -v ph="$placeholder" '
      $0 ~ s { print ph; skip=1; next }
      $0 ~ e { skip=0; next }
      !skip { print }
    ' "$target" >"$tmp"
    tmp2="$(mktemp)"
    awk -v ph="$placeholder" -v newfile="$newblock" '
      $0 == ph { while ((getline line < newfile) > 0) print line; next }
      { print }
    ' "$tmp" >"$tmp2"
    mv "$tmp2" "$target"
    rm -f "$tmp"
  elif [ -f "$target" ]; then
    tmp="$(mktemp)"
    cp "$target" "$tmp"
    printf '\n' >>"$tmp"
    if ! grep -qE '<!-- dev-(qual|environment)' "$target"; then
      echo "NOTE: $target existed — the $marker block was appended. Review the merge."
    fi
    cat "$newblock" >>"$tmp"
    mv "$tmp" "$target"
  else
    cp "$newblock" "$target"
  fi
  rm -f "$newblock"
  echo "Merged into $target"
}

# Print the paths inside a project that belong to other repositories, one per
# line: every submodule, plus the dev-qual checkout when it sits inside the
# project without being one. Their files are linted by their own repos, not
# the project's: ignored_paths <project> <checkout-abs>
ignored_paths() {
  local project checkout="$2"
  project="$(cd "$1" && pwd)"
  {
    if [ -f "$project/.gitmodules" ]; then
      git config --file "$project/.gitmodules" --get-regexp '\.path$' | cut -d' ' -f2- || true
    fi
    case "$checkout" in "$project"/*) echo "${checkout#"$project"/}" ;; esac
  } | sort -u
}

# True if the project formats with Prettier (a dependency or an ignore file)
uses_prettier() {
  [ -f "$1/.prettierignore" ] || grep -q '"prettier"' "$1/package.json" 2>/dev/null
}

# Delete a marked block (current and pre-rename dev-environment variants):
# remove_block <file> <marker>. If the file is left empty/whitespace-only,
# the file itself is deleted.
remove_block() {
  local file="$1" marker="$2" legacy tmp
  [ -f "$file" ] || return 0
  legacy="${marker/dev-qual/dev-environment}"
  tmp="$(mktemp)"
  awk -v s="<!-- ($marker|$legacy):start -->" -v e="<!-- ($marker|$legacy):end -->" \
    '$0 ~ s{skip=1; next} $0 ~ e{skip=0; next} !skip{print}' "$file" >"$tmp"
  if [ -z "$(tr -d '[:space:]' <"$tmp")" ]; then
    rm -f "$tmp" "$file"
  else
    mv "$tmp" "$file"
  fi
}

# Render an entry file for a scope: render_entry <source-file> <scope>
# <checkout-abs>. Project scope prints the file unchanged. User scope
# rewrites the "dev-qual/ is in this repo..." sentence to point at the
# absolute checkout, then rewrites every other dev-qual/ path the same way.
render_entry() {
  local source="$1" scope="$2" checkout_abs="$3" content old new placeholder
  content="$(cat "$source")"
  if [ "$scope" != "user" ]; then
    printf '%s\n' "$content"
    return
  fi
  # shellcheck disable=SC2016 # literal text to match, not an expansion
  old='`dev-qual/` is in this repo (or clone <https://github.com/instantiator/dev-qual> to a temporary location once per session).'
  new="dev-qual is installed at \`$checkout_abs\`: read every \`dev-qual/\` path in its docs as \`$checkout_abs/\`."
  placeholder="@@DEV_QUAL_SENTENCE@@"
  content="${content/"$old"/$placeholder}"
  content="${content//dev-qual\//$checkout_abs/}"
  content="${content/"$placeholder"/$new}"
  printf '%s\n' "$content"
}

# Print one KEY's value from a state file, or nothing if either is absent,
# without sourcing it into the caller: state_value <file> <key>
state_value() {
  [ -f "$1" ] || return 0
  # shellcheck disable=SC1090
  (. "$1"; eval "printf '%s' \"\${$2:-}\"")
}

# Print the state file path for a scope: state_file_for <scope> [project]
state_file_for() {
  local scope="$1" project="${2:-}"
  if [ "$scope" = "user" ]; then
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/dev-qual/config.env"
  else
    : "${project:?state_file_for: project scope needs a project dir}"
    echo "$project/.dev-qual.env"
  fi
}

# Print the result table; return 1 if any stage FAILed
report_results() {
  local i state colour failed=0
  echo ""
  echo "== Results =="
  i=0
  while [ "$i" -lt "${#RESULT_NAMES[@]}" ]; do
    state="${RESULT_STATES[$i]}"
    case "$state" in
      PASS) colour="$C_GREEN" ;;
      FAIL) colour="$C_RED"; failed=1 ;;
      *)    colour="$C_YELLOW" ;;
    esac
    if [ -n "${RESULT_HINTS[$i]}" ]; then
      printf "%s%-4s%s %-18s — %s\n" "$colour" "$state" "$C_RESET" "${RESULT_NAMES[$i]}" "${RESULT_HINTS[$i]}"
    else
      printf "%s%-4s%s %s\n" "$colour" "$state" "$C_RESET" "${RESULT_NAMES[$i]}"
    fi
    i=$((i + 1))
  done
  return "$failed"
}
