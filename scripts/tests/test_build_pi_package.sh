#!/usr/bin/env bash
# Tests for scripts/build-pi-package.sh: a real build's tarball contents,
# and that a broken manifest fails the build before npm pack ever runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

command -v node >/dev/null 2>&1 || { echo "node not found — skipping"; exit 0; }

# --- 1. a real build succeeds and its tarball has the expected shape ---
OUT1="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $OUT1"
bash "$REPO_ROOT/scripts/build-pi-package.sh" --out "$OUT1" >/dev/null
TARBALL="$(find "$OUT1" -name '*.tgz')"
assert_file "$TARBALL" "build-pi-package.sh writes a tarball into --out"
LISTING="$(tar -tzf "$TARBALL")"
assert_contains "$LISTING" "package/adapters/pi/extension.mjs" "tarball has the pi extension"
assert_contains "$LISTING" "package/skills/plan-work/SKILL.md" "tarball has a skill"
assert_contains "$LISTING" "package/scripts/check.sh" "tarball has check.sh"
assert_contains "$LISTING" "package/agents-files/remote/AGENTS.md" "tarball has the remote tier file"
assert_not_contains "$LISTING" "/tests/" "tarball excludes every tests/ directory"

# --- 2. a package.json with a missing pi.extensions path fails the build,
#        on a throwaway copy of the repo (never edit the real package.json) ---
COPY="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $COPY"
cp -R "$REPO_ROOT"/. "$COPY"/
rm -rf "$COPY/.git"
node -e '
  const fs = require("fs");
  const pkgPath = process.argv[1];
  const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
  pkg.pi.extensions = ["./adapters/pi/does-not-exist.mjs"];
  fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
' "$COPY/package.json"
OUT2="$(mktemp -d "${TMPDIR:-/tmp}/dev-qual-test.XXXXXX")"
CLEANUP="$CLEANUP $OUT2"
assert_exit 1 "a missing pi.extensions path fails the build" \
  bash "$COPY/scripts/build-pi-package.sh" --out "$OUT2"

finish
