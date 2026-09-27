#!/usr/bin/env bash
# Turns each stack's vulnerability audit into a ranked list of next steps,
# by running the language's own vuln-report tool from guidance/languages/.
# A stack without a tool, or without its toolchain, SKIPs with a hint.
#
# Usage: vuln-report.sh [--project <dir>]
#   --project <dir>  project directory (default: current directory)
# Exit code: 1 if any stack reports vulnerabilities (or its tool fails), else 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$SCRIPT_DIR/../guidance/languages"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

PROJECT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?--project needs a directory}"; shift ;;
    --help|-h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
PROJECT="$(cd "$PROJECT" && pwd)"

# Run one stack's report: report <stack> <required-cmd> <command...>
report() {
  local stack="$1" cmd="$2"; shift 2
  if ! has_cmd "$cmd"; then
    record_result "vulns:$stack" SKIP "install $cmd to run the report"
    return 0
  fi
  echo ""
  echo "-- vulns:$stack"
  if "$@"; then
    record_result "vulns:$stack" PASS
  else
    record_result "vulns:$stack" FAIL "apply the actions listed above, in small groups (skills/deps-audit)"
  fi
}

STACKS="$(detect_stacks "$PROJECT")"
[ -n "$STACKS" ] || record_result "project" SKIP "no package.json, .csproj, or pyproject.toml found"
for stack in $STACKS; do
  case "$stack" in
    node) report node node node "$TOOLS/typescript/tools/vuln-report.mjs" --project "$PROJECT" ;;
    python) report python python3 python3 "$TOOLS/python/tools/vuln_report.py" --project "$PROJECT" ;;
    dotnet) report dotnet dotnet dotnet run "$TOOLS/csharp/tools/vuln-report.cs" -- --project "$PROJECT" ;;
  esac
done

report_results
