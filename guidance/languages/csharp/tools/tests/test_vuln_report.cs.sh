#!/usr/bin/env bash
# Tests for vuln-report.cs: dev-qual's ranked `dotnet list package
# --vulnerable` report. Needs dotnet; discovered by run-unit-tests.sh via
# the test_*.cs.sh suffix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../../../../scripts/tests/lib/assert.sh
. "$REPO_ROOT/scripts/tests/lib/assert.sh"

TOOLS_DIR="$REPO_ROOT/guidance/languages/csharp/tools"
TOOL="$TOOLS_DIR/vuln-report.cs"
FIXTURES="$SCRIPT_DIR/fixtures"

# --- empty report: exit 0, no packages listed ---
OUT="$(dotnet run "$TOOL" -- --input "$FIXTURES/vuln-empty.json" 2>&1)" && CODE=0 || CODE=$?
assert_eq "0" "$CODE" "empty report exits 0"
assert_contains "$OUT" "No vulnerabilities found" "empty report message"

# --- mixed report: severity ordering, direct before transitive, de-duplication ---
OUT="$(dotnet run "$TOOL" -- --input "$FIXTURES/vuln-mixed.json" 2>&1)" && CODE=0 || CODE=$?
assert_eq "1" "$CODE" "mixed report exits 1"

LINES="$(printf '%s\n' "$OUT" | grep -E '^[A-Z]+ ')"
LINE1="$(printf '%s\n' "$LINES" | sed -n '1p')"
LINE2="$(printf '%s\n' "$LINES" | sed -n '2p')"
LINE3="$(printf '%s\n' "$LINES" | sed -n '3p')"
LINE4="$(printf '%s\n' "$LINES" | sed -n '4p')"
LINE5="$(printf '%s\n' "$LINES" | sed -n '5p')"
LINE6="$(printf '%s\n' "$LINES" | sed -n '6p')"

assert_contains "$LINE1" "CRITICAL" "row 1 is the critical package"
assert_contains "$LINE1" "Minimist.Net" "row 1 is minimist"
assert_contains "$LINE2" "HIGH" "row 2 is high severity"
assert_contains "$LINE2" "BigMajor" "row 2 is the direct high package (before transitives)"
assert_contains "$LINE2" "direct" "row 2 is marked direct"
assert_contains "$LINE3" "HIGH" "row 3 is high severity"
assert_contains "$LINE3" "transitive" "row 3 is a transitive high package"
assert_contains "$LINE4" "HIGH" "row 4 is high severity"
assert_contains "$LINE4" "transitive" "row 4 is a transitive high package"
assert_contains "$LINE5" "MODERATE" "row 5 is moderate severity"
assert_contains "$LINE5" "OldThing" "row 5 is the direct moderate package"
assert_contains "$LINE6" "MODERATE" "row 6 is moderate severity"
assert_contains "$LINE6" "transitive" "row 6 is a transitive moderate package"

# DupPkg appears in two projects but only one row is printed
DUP_COUNT="$(printf '%s\n' "$OUT" | grep -c "DupPkg" || true)"
assert_eq "1" "$DUP_COUNT" "duplicate package across projects is merged into one row"

# rows show severity, package, resolved version, directness, and action
assert_contains "$OUT" "CRITICAL  Minimist.Net  1.0.0  direct  dotnet add" "critical row format"
assert_contains "$OUT" "  transitive  update the top-level package that brings it in" "transitive row action"
assert_contains "$OUT" "MAJOR bumps — ask the user first" "direct row action mentions MAJOR caveat"
assert_contains "$OUT" "guidance/standards/dependencies.md" "transitive row action links dependencies.md"

# summary line
assert_contains "$OUT" "Summary: 6 vulnerable package(s)" "summary line total"
assert_contains "$OUT" "1 critical" "summary counts critical"
assert_contains "$OUT" "3 high" "summary counts high"
assert_contains "$OUT" "2 moderate" "summary counts moderate"
assert_contains "$OUT" "skills/deps-audit" "summary points at deps-audit skill"

# --- malformed JSON exits 2 ---
OUT="$(dotnet run "$TOOL" -- --input "$FIXTURES/vuln-malformed.json" 2>&1)" && CODE=0 || CODE=$?
assert_eq "2" "$CODE" "malformed JSON exits 2"

# --- invalid args exit 2 ---
OUT="$(dotnet run "$TOOL" -- --nonsense 2>&1)" && CODE=0 || CODE=$?
assert_eq "2" "$CODE" "unknown argument exits 2"

# --- --help exits 0 and documents usage ---
OUT="$(dotnet run "$TOOL" -- --help 2>&1)" && CODE=0 || CODE=$?
assert_eq "0" "$CODE" "--help exits 0"
assert_contains "$OUT" "vuln-report" "--help mentions the tool name"
assert_contains "$OUT" "--input" "--help documents --input"

finish
