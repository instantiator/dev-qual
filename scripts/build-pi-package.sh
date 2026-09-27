#!/usr/bin/env bash
# Builds an installable pi package tarball from this checkout: validates
# package.json's `pi.extensions`/`pi.skills` paths, runs `npm pack`, and
# checks the resulting tarball's contents. First step towards `npm publish`
# (not run here).
#
# Usage: build-pi-package.sh [--out <dir>]
#   --out <dir>  where to write the tarball (default: dist/)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

OUT="dist"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="${2:?--out needs a directory}"; shift ;;
    --help|-h) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

command -v node >/dev/null 2>&1 || { echo "node is required" >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }

# 1. Validate every declared extension/skill path exists, and each skill
#    directory holds at least one SKILL.md.
node -e '
  const fs = require("fs");
  const path = require("path");
  const repo = process.argv[1];
  const pkg = JSON.parse(fs.readFileSync(path.join(repo, "package.json"), "utf8"));
  const pi = pkg.pi || {};
  let ok = true;
  for (const ext of pi.extensions || []) {
    if (!fs.existsSync(path.join(repo, ext))) {
      console.error("Missing pi.extensions entry: " + ext);
      ok = false;
    }
  }
  for (const skillsDir of pi.skills || []) {
    const abs = path.join(repo, skillsDir);
    if (!fs.existsSync(abs)) {
      console.error("Missing pi.skills entry: " + skillsDir);
      ok = false;
      continue;
    }
    const hasSkillMd = fs.readdirSync(abs, { withFileTypes: true })
      .some((entry) => entry.isDirectory() && fs.existsSync(path.join(abs, entry.name, "SKILL.md")));
    if (!hasSkillMd) {
      console.error("No SKILL.md files found under pi.skills entry: " + skillsDir);
      ok = false;
    }
  }
  process.exit(ok ? 0 : 1);
' "$REPO"
echo "pi package manifest paths OK"

# 2. Build the tarball.
TARBALL="$(cd "$REPO" && npm pack --silent --pack-destination "$OUT")"
TARBALL="$OUT/$TARBALL"
echo "Built $TARBALL"

# 3. Check its contents: the key files are present, and no test paths leaked in.
LISTING="$(tar -tzf "$TARBALL")"
for expect in \
  package/adapters/pi/extension.mjs \
  package/skills/plan-work/SKILL.md \
  package/scripts/check.sh \
  package/agents-files/remote/AGENTS.md; do
  echo "$LISTING" | grep -qx "$expect" || { echo "Tarball is missing $expect" >&2; exit 1; }
done
if echo "$LISTING" | grep -q '/tests/'; then
  echo "Tarball contains a /tests/ path — check package.json's \"files\" exclusions" >&2
  exit 1
fi
echo "Tarball contents OK"

echo ""
echo "Install locally with:   pi install $TARBALL"
echo "Or from this checkout:  pi install $REPO"
echo "Publish later with:     npm publish"
