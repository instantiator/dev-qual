#!/usr/bin/env bash
# Integration test for Baseline.props/Baseline.targets: actually builds a
# real classlib and a real xunit project against the baseline, rather than
# just checking check-baseline.cs's own detection logic. This is what
# caught the two defects unit tests missed: an invalid XML comment, and the
# IsTestProject exemption never applying because Directory.Build.props is
# imported before the property is set.
#
# Needs dotnet and network (for `dotnet new`'s first restore). If either
# `dotnet new` template isn't installed or restore fails offline, prints a
# SKIP reason and exits 0 so offline runs still pass; CI has network.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../../../../../scripts/tests/lib/assert.sh
. "$REPO_ROOT/scripts/tests/lib/assert.sh"

TOOLS_DIR="$REPO_ROOT/guidance/languages/csharp/tools"

skip() {
  echo "SKIP: $1" >&2
  exit 0
}

command -v dotnet >/dev/null 2>&1 || skip "dotnet not installed"

WORK="$(mktemp -d)"
CLEANUP="$CLEANUP $WORK"
cd "$WORK"

# Two real projects importing the baseline by absolute path, wired up via
# Directory.Build.props/.targets exactly as a consumer project would.
if ! dotnet new classlib -n SampleLib -o SampleLib --force >tmp_new_classlib.log 2>&1; then
  skip "dotnet new classlib failed (offline?): $(tail -5 tmp_new_classlib.log 2>/dev/null || true)"
fi
if ! dotnet new xunit -n SampleTests -o SampleTests --force >tmp_new_xunit.log 2>&1; then
  skip "dotnet new xunit failed (offline?): $(tail -5 tmp_new_xunit.log 2>/dev/null || true)"
fi

cat > Directory.Build.props <<EOF
<Project>
  <Import Project="$TOOLS_DIR/Baseline.props" />
</Project>
EOF
cat > Directory.Build.targets <<EOF
<Project>
  <Import Project="$TOOLS_DIR/Baseline.targets" />
</Project>
EOF

if ! dotnet restore SampleLib >tmp_restore_lib.log 2>&1; then
  skip "restore failed (offline?): $(tail -5 tmp_restore_lib.log 2>/dev/null || true)"
fi

# (a) classlib build FAILS with CS1591 when a public class lacks `///`
OUT="$(dotnet build SampleLib --no-restore 2>&1)" && CODE=0 || CODE=$?
assert_eq "1" "$CODE" "classlib without a doc comment fails to build"
assert_contains "$OUT" "CS1591" "classlib build failure is the missing-doc-comment rule"

# (a) ... and passes once the public class has one
cat > SampleLib/Class1.cs <<'EOF'
namespace SampleLib;

/// <summary>Sample class, documented so CS1591 does not fire.</summary>
public class Class1
{
}
EOF
OUT="$(dotnet build SampleLib --no-restore 2>&1)" && CODE=0 || CODE=$?
assert_eq "0" "$CODE" "classlib with a doc comment builds"

# (b) the xunit project builds without `///` comments (the exemption works)
OUT="$(dotnet build SampleTests 2>&1)" && CODE=0 || CODE=$?
assert_eq "0" "$CODE" "xunit test project builds without doc comments (IsTestProject exemption)"

# (c) Nullable is enabled on the classlib via the baseline
NULLABLE="$(dotnet msbuild SampleLib -getProperty:Nullable 2>/dev/null)"
assert_eq "enable" "$NULLABLE" "classlib has Nullable=enable from the baseline"

finish
