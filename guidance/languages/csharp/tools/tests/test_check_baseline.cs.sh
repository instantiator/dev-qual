#!/usr/bin/env bash
# Tests for check-baseline.cs: dev-qual's C# baseline adoption checker.
# Needs dotnet; discovered by run-unit-tests.sh via the test_*.cs.sh suffix.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../../../../scripts/tests/lib/assert.sh
. "$REPO_ROOT/scripts/tests/lib/assert.sh"

TOOLS_DIR="$REPO_ROOT/guidance/languages/csharp/tools"
TOOL="$TOOLS_DIR/check-baseline.cs"
BASELINE_PATH="$TOOLS_DIR/Baseline.props"
BASELINE_TARGETS_PATH="$TOOLS_DIR/Baseline.targets"

# run_check <dir> [args...]: runs check-baseline.cs, echoing "<exit> <stdout>"
run_check() {
  local dir="$1" out code
  shift
  out="$(dotnet run --file "$TOOL" -- --project "$dir" "$@" 2>&1)" && code=0 || code=$?
  printf '%s\x1e%s' "$code" "$out"
}

# --- not a dotnet project: no sln/slnx/csproj at top level or one down ---
DIR1="$(mktemp -d)"
RESULT="$(run_check "$DIR1")"
CODE="${RESULT%%$'\x1e'*}"; OUT="${RESULT#*$'\x1e'}"
assert_eq "0" "$CODE" "not-a-dotnet-project exits 0"
assert_contains "$OUT" "not a dotnet project" "not-a-dotnet-project message"

# --- dotnet project, no Directory.Build.props at all ---
DIR2="$(mktemp -d)"
touch "$DIR2/App.csproj"
RESULT="$(run_check "$DIR2")"
CODE="${RESULT%%$'\x1e'*}"; OUT="${RESULT#*$'\x1e'}"
assert_eq "1" "$CODE" "no Directory.Build.props exits 1"
assert_contains "$OUT" "No Directory.Build.props found" "no Directory.Build.props message"
assert_contains "$OUT" "<Import Project=" "no Directory.Build.props prints an Import line"
assert_contains "$OUT" "$BASELINE_PATH" "no Directory.Build.props suggests the absolute baseline path"

# --- dotnet project, one level down ---
DIR2B="$(mktemp -d)"
mkdir "$DIR2B/src"
touch "$DIR2B/src/App.csproj"
RESULT="$(run_check "$DIR2B")"
CODE="${RESULT%%$'\x1e'*}"; OUT="${RESULT#*$'\x1e'}"
assert_eq "1" "$CODE" "project one level down is still recognised (exit 1, not 0)"

# --- Directory.Build.props exists but does not adopt the baseline ---
DIR3="$(mktemp -d)"
touch "$DIR3/App.csproj"
printf '<Project></Project>\n' > "$DIR3/Directory.Build.props"
RESULT="$(run_check "$DIR3")"
CODE="${RESULT%%$'\x1e'*}"; OUT="${RESULT#*$'\x1e'}"
assert_eq "1" "$CODE" "non-adopting Directory.Build.props exits 1"
assert_contains "$OUT" "does not adopt the dev-qual baseline" "non-adopting message"
assert_contains "$OUT" "$BASELINE_PATH" "non-adopting suggestion names the absolute baseline path"

# --- props-only adopted, Directory.Build.targets missing: exit 1, prints the targets import ---
DIR4A="$(mktemp -d)"
touch "$DIR4A/App.csproj"
printf '<Project><Import Project="anything/Baseline.props" /></Project>\n' > "$DIR4A/Directory.Build.props"
RESULT="$(run_check "$DIR4A")"
CODE="${RESULT%%$'\x1e'*}"; OUT="${RESULT#*$'\x1e'}"
assert_eq "1" "$CODE" "props adopted but targets missing exits 1"
assert_contains "$OUT" "No Directory.Build.targets found" "missing-targets message"
assert_contains "$OUT" "$BASELINE_TARGETS_PATH" "missing-targets suggestion names the absolute Baseline.targets path"

# --- both halves adopted: exit 0 ---
DIR4="$(mktemp -d)"
touch "$DIR4/App.csproj"
printf '<Project><Import Project="anything/Baseline.props" /></Project>\n' > "$DIR4/Directory.Build.props"
printf '<Project><Import Project="anything/Baseline.targets" /></Project>\n' > "$DIR4/Directory.Build.targets"
RESULT="$(run_check "$DIR4")"
CODE="${RESULT%%$'\x1e'*}"; OUT="${RESULT#*$'\x1e'}"
assert_eq "0" "$CODE" "both halves adopted exits 0"
assert_contains "$OUT" "baseline: adopted" "adopted message"
assert_contains "$OUT" "$DIR4/Directory.Build.props" "adopted message names the props file"
assert_contains "$OUT" "$DIR4/Directory.Build.targets" "adopted message names the targets file"

# --- props adopted, but Directory.Build.targets is malformed XML: exit 2 ---
DIR4D="$(mktemp -d)"
touch "$DIR4D/App.csproj"
printf '<Project><Import Project="anything/Baseline.props" /></Project>\n' > "$DIR4D/Directory.Build.props"
printf '<Project><Import\n' > "$DIR4D/Directory.Build.targets"
RESULT="$(run_check "$DIR4D")"
CODE="${RESULT%%$'\x1e'*}"
assert_eq "2" "$CODE" "malformed Directory.Build.targets exits 2"

# --- baseline nested inside the project: relative import via MSBuildThisFileDirectory ---
DIR5="$(mktemp -d)"
touch "$DIR5/App.csproj"
mkdir -p "$DIR5/dev-qual/guidance/languages/csharp/tools"
cp "$BASELINE_PATH" "$DIR5/dev-qual/guidance/languages/csharp/tools/"
cp "$TOOL" "$DIR5/dev-qual/guidance/languages/csharp/tools/"
NESTED_TOOL="$DIR5/dev-qual/guidance/languages/csharp/tools/check-baseline.cs"
OUT="$(dotnet run --file "$NESTED_TOOL" -- --project "$DIR5" 2>&1)" && CODE=0 || CODE=$?
assert_eq "1" "$CODE" "nested-baseline project exits 1 (not yet adopted)"
# shellcheck disable=SC2016 # literal MSBuild property syntax, not shell expansion
assert_contains "$OUT" '$(MSBuildThisFileDirectory)dev-qual/guidance/languages/csharp/tools/Baseline.props' \
  "nested baseline suggests a relative Import path"

# --- malformed XML in Directory.Build.props exits 2 ---
DIR6="$(mktemp -d)"
touch "$DIR6/App.csproj"
printf '<Project><Import\n' > "$DIR6/Directory.Build.props"
RESULT="$(run_check "$DIR6")"
CODE="${RESULT%%$'\x1e'*}"
assert_eq "2" "$CODE" "malformed XML exits 2"

# --- invalid args exit 2 ---
OUT="$(dotnet run --file "$TOOL" -- --nonsense 2>&1)" && CODE=0 || CODE=$?
assert_eq "2" "$CODE" "unknown argument exits 2"

# --- --help exits 0 and documents usage ---
OUT="$(dotnet run --file "$TOOL" -- --help 2>&1)" && CODE=0 || CODE=$?
assert_eq "0" "$CODE" "--help exits 0"
assert_contains "$OUT" "check-baseline" "--help mentions the tool name"
assert_contains "$OUT" "--project" "--help documents --project"

# --- both baseline files are well-formed XML (a malformed comment can't recur) ---
XML_ERR="$(mktemp)"
for f in "$BASELINE_PATH" "$BASELINE_TARGETS_PATH"; do
  if python3 -c "import xml.dom.minidom, sys; xml.dom.minidom.parse(sys.argv[1])" "$f" 2>"$XML_ERR"; then
    assert_eq "0" "0" "$f is well-formed XML"
  else
    assert_eq "0" "1" "$f is well-formed XML ($(cat "$XML_ERR"))"
  fi
done
rm -f "$XML_ERR"

rm -rf "$DIR1" "$DIR2" "$DIR2B" "$DIR3" "$DIR4A" "$DIR4" "$DIR4D" "$DIR5" "$DIR6"

# Run from inside a project whose .csproj is in the cwd, as check.sh does:
# a bare `dotnet run <file>.cs` would run that project instead of the tool
CWD_PROJ="$(mktemp -d)"
printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>\n' >"$CWD_PROJ/Lib.csproj"
OUT="$(cd "$CWD_PROJ" && dotnet run --file "$TOOL" -- --project . 2>&1)" && CODE=0 || CODE=$?
assert_eq "1" "$CODE" "runs the tool, not the project in the cwd"
assert_contains "$OUT" "Baseline.props" "prints the adoption lines from inside a project dir"
rm -rf "$CWD_PROJ"

finish
