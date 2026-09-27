#!/usr/bin/env bash
# The quality gate. Detects every stack in the project, then runs:
#   format check -> lint -> typecheck -> lint-baseline adoption -> build
#   -> unit tests -> aislop scan
# plus shellcheck, actionlint, and markdownlint wherever those files exist,
# and prints a PASS/FAIL/SKIP table with a fix-hint per failure.
# Missing tools SKIP with an install hint; the gate never crashes on absence.
# Submodules (dev-qual among them) are not linted: each is its own repo's job.
#
# Usage: check.sh [--fast|--comprehensive] [--fix] [--suite <name>] [--project <dir>]
#   --fast           format + lint + typecheck only (used by the pre-commit hook)
#   --comprehensive  the full gate plus every test suite and a security audit
#   --fix            apply formatters/autofixes before checking
#   --suite <name>   additionally run one test suite via run-tests.sh
#   --project <dir>  project directory (default: current directory)
# Exit code: 0 only when no stage FAILs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LANG_TOOLS="$SCRIPT_DIR/../guidance/languages"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

FAST=0; COMPREHENSIVE=0; FIX=0; SUITE=""; PROJECT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) FAST=1 ;;
    --comprehensive) COMPREHENSIVE=1 ;;
    --fix) FIX=1 ;;
    --suite) SUITE="${2:?--suite needs a name}"; shift ;;
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --help|-h)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
if [ "$FAST" = 1 ] && [ "$COMPREHENSIVE" = 1 ]; then
  echo "--fast and --comprehensive are mutually exclusive" >&2; exit 2
fi

cd "$PROJECT"
# Submodules and this checkout belong to other repos, so list_files skips them.
# Starts non-empty: bash 3.2 errors on an empty array under set -u.
EXCLUDES=(-not -path './.git/*')
while IFS= read -r p; do
  [ -n "$p" ] && EXCLUDES+=(-not -path "./$p/*")
done <<<"$(ignored_paths . "$(cd "$SCRIPT_DIR/.." && pwd)")"
STACKS="$(detect_stacks .)"
MODE="full"
if [ "$FAST" = 1 ]; then MODE="fast"; fi
if [ "$COMPREHENSIVE" = 1 ]; then MODE="comprehensive"; fi
echo "check.sh — stacks: $(echo "${STACKS:-none}" | tr '\n' ' ')($MODE mode)"

# Prepended to each stack's stage names, so a polyglot repo's results table says
# which toolchain produced each line. Empty when only one stack is present.
STAGE_PREFIX=""

# Run one stage and record the outcome: run_stage <name> <hint-on-fail> <command...>
run_stage() {
  local name="$1" hint="$2"; shift 2
  echo ""
  echo "-- $name: $*"
  if "$@"; then
    record_result "$name" PASS
  else
    record_result "$name" FAIL "$hint"
  fi
}

# List the project's files matching a name pattern, skipping build output,
# virtualenvs, and EXCLUDES: list_files <find-name-pattern>
list_files() {
  find . -name "$1" \
    -not -path './node_modules/*' \
    -not -path './.venv/*' -not -path './venv/*' \
    -not -path './bin/*' -not -path './obj/*' \
    "${EXCLUDES[@]}"
}

# Report whether the project extends a language's dev-qual lint baseline:
# check_baseline <label> <required-cmd> <checker...>. Not adopting it is a
# SKIP with the exact lines to add, never a FAIL, so existing projects pass.
check_baseline() {
  local label="$1" cmd="$2" out rc=0
  shift 2
  if ! has_cmd "$cmd"; then return 0; fi
  out="$("$@" --project . 2>&1)" || rc=$?
  case "$rc" in
    0) record_result "${STAGE_PREFIX}baseline" PASS ;;
    1) echo ""; echo "$out"
       record_result "${STAGE_PREFIX}baseline" SKIP "optional: extend dev-qual's $label baseline (lines above)" ;;
    *) echo ""; echo "$out"
       record_result "${STAGE_PREFIX}baseline" FAIL "the $label baseline checker failed (output above)" ;;
  esac
}

# True if list_files would match anything
has_files() {
  list_files "$1" | grep -q .
}

check_node() {
  if [ "$FIX" = 1 ]; then
    npm_has_script . format && run_stage "${STAGE_PREFIX}format-fix" "review formatter output" npm run format
    npm_has_script . lint && run_stage "${STAGE_PREFIX}lint-fix" "review lint output" npm run lint
  fi
  # Format check (only when a dedicated check script exists; else lint covers it)
  if npm_has_script . "format:check"; then
    run_stage "${STAGE_PREFIX}format" "run: npm run format" npm run format:check
  else
    record_result "${STAGE_PREFIX}format" SKIP "no format:check script; assuming lint covers formatting"
  fi
  # Lint (prefer a non-mutating script)
  if npm_has_script . "lint:check"; then
    run_stage "${STAGE_PREFIX}lint" "run: npm run lint" npm run lint:check
  elif npm_has_script . lint; then
    run_stage "${STAGE_PREFIX}lint" "fix reported lint problems" npm run lint
  else
    record_result "${STAGE_PREFIX}lint" SKIP "add a lint script (see guidance/languages/typescript/typescript.md)"
  fi
  # Typecheck
  if npm_has_script . typecheck; then
    run_stage "${STAGE_PREFIX}typecheck" "fix reported type errors" npm run typecheck
  elif [ -f tsconfig.json ]; then
    run_stage "${STAGE_PREFIX}typecheck" "fix reported type errors" npx --no-install tsc --noEmit
  else
    record_result "${STAGE_PREFIX}typecheck" SKIP "no typecheck script or tsconfig.json"
  fi
  check_baseline eslint node node "$LANG_TOOLS/typescript/tools/check-baseline.mjs"
  [ "$FAST" = 1 ] && return 0
  if npm_has_script . build; then
    run_stage "${STAGE_PREFIX}build" "fix build errors/warnings" npm run build
  else
    record_result "${STAGE_PREFIX}build" SKIP "no build script"
  fi
  if npm_has_script . test; then
    run_stage "${STAGE_PREFIX}unit-tests" "fix failing tests" npm test
  else
    record_result "${STAGE_PREFIX}unit-tests" SKIP "no test script (see guidance/standards/testing.md)"
  fi
  return 0
}

check_dotnet() {
  if ! has_cmd dotnet; then
    record_result "${STAGE_PREFIX}dotnet" SKIP "install the .NET SDK (mac: brew install dotnet-sdk)"
    return 0
  fi
  if [ "$FIX" = 1 ]; then
    run_stage "${STAGE_PREFIX}format-fix" "review formatter output" dotnet format
  fi
  run_stage "${STAGE_PREFIX}format" "run: dotnet format" dotnet format --verify-no-changes
  check_baseline msbuild dotnet dotnet run --file "$LANG_TOOLS/csharp/tools/check-baseline.cs" --
  [ "$FAST" = 1 ] && return 0
  # Analyzers run within the build, so build doubles as lint
  run_stage "${STAGE_PREFIX}build" "fix build errors/warnings" dotnet build --nologo
  run_stage "${STAGE_PREFIX}unit-tests" "fix failing tests" dotnet test --nologo
  return 0
}

check_python() {
  if ! has_cmd ruff; then
    record_result "${STAGE_PREFIX}ruff" SKIP "install ruff (pip install ruff, or: brew install ruff)"
  else
    if [ "$FIX" = 1 ]; then
      run_stage "${STAGE_PREFIX}format-fix" "review formatter output" ruff format .
      run_stage "${STAGE_PREFIX}lint-fix" "review lint output" ruff check --fix .
    fi
    run_stage "${STAGE_PREFIX}format" "run: ruff format ." ruff format --check .
    run_stage "${STAGE_PREFIX}lint" "fix reported problems (ruff check --fix . handles the easy ones)" ruff check .
  fi
  # mypy is only useful once configured; without config, say so rather than
  # failing a project that never opted into type checking
  if ! has_cmd mypy; then
    record_result "${STAGE_PREFIX}typecheck" SKIP "install mypy (pip install mypy)"
  elif grep -q '^\[tool\.mypy\]' pyproject.toml 2>/dev/null \
    || [ -f mypy.ini ] || [ -f .mypy.ini ]; then
    run_stage "${STAGE_PREFIX}typecheck" "fix reported type errors" mypy .
  else
    record_result "${STAGE_PREFIX}typecheck" SKIP "add [tool.mypy] to pyproject.toml (see guidance/languages/python/python.md)"
  fi
  check_baseline ruff python3 python3 "$LANG_TOOLS/python/tools/check_baseline.py"
  [ "$FAST" = 1 ] && return 0
  if ! has_cmd pytest; then
    record_result "${STAGE_PREFIX}unit-tests" SKIP "install pytest (pip install pytest)"
  elif has_files 'test_*.py' || has_files '*_test.py'; then
    run_stage "${STAGE_PREFIX}unit-tests" "fix failing tests" pytest
  else
    record_result "${STAGE_PREFIX}unit-tests" SKIP "no test files found (see guidance/standards/testing.md)"
  fi
  return 0
}

audit_node() {
  # npm audit reads the lockfile; without one there is nothing to audit
  if [ ! -f package-lock.json ] && [ ! -f npm-shrinkwrap.json ]; then
    record_result "audit:node" SKIP "no package-lock.json to audit: commit your lockfile (npm i --package-lock-only)"
    return 0
  fi
  run_stage "audit:node" "run: $SCRIPT_DIR/vuln-report.sh for ranked next steps" \
    npm audit --audit-level=high
}

# dotnet list package --vulnerable exits 0 even when it finds vulnerabilities,
# so the report is inspected rather than the exit code trusted
audit_dotnet() {
  local out
  echo ""
  echo "-- audit:dotnet: dotnet list package --vulnerable"
  out="$(dotnet list package --vulnerable 2>&1)" || true
  echo "$out"
  if echo "$out" | grep -q 'has the following vulnerable packages'; then
    record_result "audit:dotnet" FAIL "run: $SCRIPT_DIR/vuln-report.sh for ranked next steps"
  else
    record_result "audit:dotnet" PASS
  fi
}

audit_python() {
  if has_cmd pip-audit; then
    run_stage "audit:python" "run: $SCRIPT_DIR/vuln-report.sh for ranked next steps" pip-audit
  else
    record_result "audit:python" SKIP "install pip-audit (pip install pip-audit)"
  fi
}

# Per-stack checks
if [ -z "$STACKS" ]; then
  record_result "project" SKIP "no package.json, .csproj, or pyproject.toml found; running generic checks only"
fi
STACK_COUNT="$(echo "$STACKS" | grep -c . || true)"
for stack in $STACKS; do
  if [ "$STACK_COUNT" -gt 1 ]; then STAGE_PREFIX="$stack:"; fi
  case "$stack" in
    node) check_node ;;
    dotnet) check_dotnet ;;
    python) check_python ;;
  esac
done
STAGE_PREFIX=""

# Generic stages, whatever the stack
if has_files '*.sh'; then
  if has_cmd shellcheck; then
    # Word-splitting the file list is intended here
    # shellcheck disable=SC2046
    run_stage "shellcheck" "fix shellcheck findings" shellcheck $(list_files '*.sh')
  else
    record_result "shellcheck" SKIP "install shellcheck (mac: brew install shellcheck)"
  fi
fi

WORKFLOW_DIRS=""
for d in .github/workflows .gitea/workflows; do
  [ -d "$d" ] && WORKFLOW_DIRS="$WORKFLOW_DIRS $d"
done
if [ -n "$WORKFLOW_DIRS" ]; then
  if has_cmd actionlint; then
    # List every workflow file explicitly: given any args, actionlint stops
    # auto-discovering .github/workflows, and it never looks in .gitea/
    # shellcheck disable=SC2086
    WORKFLOW_ARGS="$(find $WORKFLOW_DIRS -name '*.yml' -o -name '*.yaml')"
    # Word-splitting the collected args is intended here
    # shellcheck disable=SC2086
    run_stage "actionlint" "fix actionlint findings (see guidance/ci/github-actions.md)" actionlint $WORKFLOW_ARGS
  else
    record_result "actionlint" SKIP "install actionlint (mac: brew install actionlint)"
  fi
fi

if has_files '*.md'; then
  if has_cmd markdownlint; then
    # The project's own config wins. Where it has none, use the config shipped
    # here, which switches off the stylistic rules this guidance disagrees with.
    MD_ARGS=""
    if ! ls .markdownlint.json .markdownlint.jsonc .markdownlint.yaml .markdownlintrc \
      >/dev/null 2>&1; then
      MD_ARGS="--config $SCRIPT_DIR/../configs/markdownlint.json"
    fi
    # Word-splitting both the config flag and the file list is intended here
    # shellcheck disable=SC2046,SC2086
    run_stage "markdownlint" "fix reported markdown problems" \
      markdownlint $MD_ARGS $(list_files '*.md')
  else
    record_result "markdownlint" SKIP "install markdownlint (npm i -g markdownlint-cli)"
  fi
fi

# aislop covers 8 languages, so it runs for any stack — not just node
if [ "$FAST" = 0 ]; then
  if npx --yes aislop@latest --version >/dev/null 2>&1; then
    # With a project config, use the ci command (score threshold, ratchetable);
    # bare scan exits non-zero on any finding, including warnings-only.
    if [ -f .aislop/config.yml ]; then
      run_stage "aislop" "fix reported slop (see guidance/standards/pitfalls.md); preview mechanical fixes: npx aislop fix --safe --dry-run" npx --yes aislop@latest ci
    else
      run_stage "aislop" "fix reported slop (see guidance/standards/pitfalls.md); preview mechanical fixes: npx aislop fix --safe --dry-run" npx --yes aislop@latest scan
    fi
  else
    record_result "aislop" SKIP "optional: npm i -D aislop, or npx aislop scan"
  fi
fi

# Comprehensive mode: every test suite, then a security audit per stack
if [ "$COMPREHENSIVE" = 1 ]; then
  run_stage "all-suites" "fix the failing suite" "$SCRIPT_DIR/run-tests.sh" all
  for stack in $STACKS; do
    case "$stack" in
      node) audit_node ;;
      dotnet) if has_cmd dotnet; then audit_dotnet; fi ;;
      python) audit_python ;;
    esac
  done
fi

# Optional extra suite
if [ -n "$SUITE" ]; then
  run_stage "suite:$SUITE" "fix failing $SUITE tests" "$SCRIPT_DIR/run-tests.sh" "$SUITE"
fi

report_results
