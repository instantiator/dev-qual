#!/usr/bin/env bash
# Tests for check.sh's file discovery: which files reach the linters it runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# A markdownlint stand-in that records each argument it gets, one per line
STUBS="$(mk_tmp_repo)"
cat >"$STUBS/markdownlint" <<'EOF'
#!/usr/bin/env bash
printf '[%s]\n' "$@"
EOF
chmod +x "$STUBS/markdownlint"

# run_check <project>: the gate's output, with the stub markdownlint
run_check() {
  PATH="$STUBS:$PATH" bash "$REPO_ROOT/scripts/check.sh" --fast --project "$1" 2>&1 || true
}

# --- 1. a git project: gitignored files, nested dependencies, and
#        submodules are skipped; a name with spaces arrives whole ---
PROJ="$(mk_tmp_repo)"
mkdir -p "$PROJ/docs" "$PROJ/app/node_modules/dep" "$PROJ/temp" "$PROJ/vendor/sub"
printf 'node_modules\ntemp/\n' >"$PROJ/.gitignore"
echo "# Kept" >"$PROJ/docs/a b.md"
echo "# Dep" >"$PROJ/app/node_modules/dep/README.md"
echo "# Scratch" >"$PROJ/temp/notes.md"
echo "# Sub" >"$PROJ/vendor/sub/README.md"
printf '[submodule "sub"]\n\tpath = vendor/sub\n\turl = x\n' >"$PROJ/.gitmodules"
OUT="$(run_check "$PROJ")"
assert_contains "$OUT" "[docs/a b.md]" "a file name with spaces reaches markdownlint whole"
assert_not_contains "$OUT" "node_modules/dep" "nested node_modules is skipped"
assert_not_contains "$OUT" "temp/notes.md" "gitignored files are skipped"
assert_not_contains "$OUT" "vendor/sub" "submodule files are skipped"

# --- 2. a tree big enough that `find | grep -q` would die of SIGPIPE still
#        gets its markdown stage ---
PROJ2="$(mk_tmp_repo)"
mkdir -p "$PROJ2/docs"
for i in $(seq 1 2000); do
  echo "# Doc $i" >"$PROJ2/docs/a-long-file-name-to-fill-the-pipe-buffer-quickly-$i.md"
done
assert_contains "$(run_check "$PROJ2" | sed -n '/== Results/,$p')" "markdownlint" "markdownlint stage runs in a large tree"

finish
