#!/usr/bin/env bash
# Tests for scripts/stale-docs.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/assert.sh
. "$SCRIPT_DIR/lib/assert.sh"

# Test: a modified src/util.sh, and README.md mentions util.sh → hit reported with correct line number
TMP="$(mk_tmp_repo)"
mkdir -p "$TMP/src"
echo "# Test" > "$TMP/README.md"
echo "See src/util.sh for details" >> "$TMP/README.md"
echo "util_func() { echo hi; }" > "$TMP/src/util.sh"
git -C "$TMP" add .
git -C "$TMP" commit -q -m "initial"

# Modify src/util.sh
echo "new_line() { echo hello; }" >> "$TMP/src/util.sh"
git -C "$TMP" add "$TMP/src/util.sh"

# Run script and check output
OUTPUT="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP" 2>&1)"
assert_contains "$OUTPUT" "README.md:2 — mentions util.sh" "hit reported with correct line number"

# Test: a deleted lib/old.py mentioned by path in docs/guide.md → hit
TMP2="$(mk_tmp_repo)"
mkdir -p "$TMP2/lib"
mkdir -p "$TMP2/docs"
echo "See lib/old.py" > "$TMP2/docs/guide.md"
echo "def old_func(): pass" > "$TMP2/lib/old.py"
git -C "$TMP2" add .
git -C "$TMP2" commit -q -m "initial"

# Delete lib/old.py
rm "$TMP2/lib/old.py"

OUTPUT2="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP2" 2>&1)"
assert_contains "$OUTPUT2" "docs/guide.md" "deleted file mentioned in docs is detected"
assert_contains "$OUTPUT2" "lib/old.py" "the deleted file path is what we search for"

# Test: a renamed file - the OLD name is searched
TMP3="$(mk_tmp_repo)"
mkdir -p "$TMP3/src"
mkdir -p "$TMP3/docs"
echo "See src/old_name.js" > "$TMP3/docs/README.md"
echo "function MyFunc() {}" > "$TMP3/src/old_name.js"
git -C "$TMP3" add .
git -C "$TMP3" commit -q -m "initial"

# Rename file
mv "$TMP3/src/old_name.js" "$TMP3/src/new_name.js"

OUTPUT3="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP3" 2>&1)"
assert_contains "$OUTPUT3" "old_name.js" "renamed file's old name is searched in docs"

# Test: a removed def compute_total( line in a .py file, a doc mentioning compute_total → hit
TMP4="$(mk_tmp_repo)"
mkdir -p "$TMP4/lib"
mkdir -p "$TMP4/docs"
echo "See compute_total function" > "$TMP4/docs/api.md"
cat > "$TMP4/lib/calc.py" <<'EOF'
def compute_total(items):
    return sum(items)
EOF
git -C "$TMP4" add .
git -C "$TMP4" commit -q -m "initial"

# Modify lib/calc.py to remove compute_total function
cat > "$TMP4/lib/calc.py" <<'EOF'
def compute_sum(items):
    return sum(items)
EOF

OUTPUT4="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP4" 2>&1)"
assert_contains "$OUTPUT4" "compute_total" "removed function name is found in docs"

# Test: a removed short name (def ab()) - NOT searched (< 4 chars)
TMP5="$(mk_tmp_repo)"
mkdir -p "$TMP5/lib"
mkdir -p "$TMP5/docs"
echo "See ab function and cdef_x function" > "$TMP5/docs/api.md"
cat > "$TMP5/lib/util.py" <<'EOF'
def ab():
    pass
def cdef_x():
    pass
EOF
git -C "$TMP5" add .
git -C "$TMP5" commit -q -m "initial"

# Modify to remove both functions
cat > "$TMP5/lib/util.py" <<'EOF'
def xyz():
    pass
EOF

OUTPUT5="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP5" 2>&1)"
assert_not_contains "$OUTPUT5" "mentions ab" "short function name (< 4 chars) is not searched"
assert_contains "$OUTPUT5" "mentions cdef_x" "longer function name is searched"

# Test: --base <sha> of an earlier commit picks up committed changes since then
TMP6="$(mk_tmp_repo)"
mkdir -p "$TMP6/src"
mkdir -p "$TMP6/docs"
echo "Use main.sh" > "$TMP6/docs/guide.md"
echo "old code" > "$TMP6/src/main.sh"
git -C "$TMP6" add .
git -C "$TMP6" commit -q -m "commit1"
FIRST_SHA="$(git -C "$TMP6" rev-parse HEAD)"

# Add a second commit that modifies main.sh
echo "new code" >> "$TMP6/src/main.sh"
git -C "$TMP6" add .
git -C "$TMP6" commit -q -m "commit2"

# Compare against the first commit - should see main.sh as modified
OUTPUT6="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP6" --base "$FIRST_SHA" 2>&1)"
assert_contains "$OUTPUT6" "main.sh" "changed file is detected when using --base"

# Test: no mentions → the "no docs mention" message and exit 0
TMP7="$(mk_tmp_repo)"
mkdir -p "$TMP7/src"
mkdir -p "$TMP7/docs"
echo "Some docs" > "$TMP7/docs/guide.md"
echo "code here" > "$TMP7/src/code.sh"
git -C "$TMP7" add .
git -C "$TMP7" commit -q -m "initial"

# Modify a file that isn't mentioned anywhere
echo "new stuff" >> "$TMP7/src/code.sh"

OUTPUT7="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP7" 2>&1)"
assert_contains "$OUTPUT7" "no docs mention the changed files" "no-matches message is shown"
assert_exit 0 "exit 0 when no mentions found" \
  bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP7"

# Test: not a git repo → exit 2
NOT_GIT="/tmp/not-a-git-repo-$$"
mkdir -p "$NOT_GIT"
CODE=0; bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$NOT_GIT" >/dev/null 2>&1 || CODE=$?
assert_eq 2 "$CODE" "exit 2 when not a git repo"
rm -rf "$NOT_GIT"

# Test: --help produces usage
HELP_OUTPUT="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --help 2>&1)"
assert_contains "$HELP_OUTPUT" "Usage:" "help includes Usage line"
assert_contains "$HELP_OUTPUT" "stale-docs.sh" "help mentions script name"

# A removed plain-word name (def existing) is not searched: it matches prose
TMP8="$(mk_tmp_repo)"
mkdir -p "$TMP8/lib"
printf 'def existing():\n    pass\n' > "$TMP8/lib/words.py"
echo "The existing behaviour is unchanged." > "$TMP8/README.md"
git -C "$TMP8" add . && git -C "$TMP8" commit -qm init
printf '# emptied\n' > "$TMP8/lib/words.py"
OUTPUT8="$(bash "$REPO_ROOT/scripts/stale-docs.sh" --project "$TMP8")"
assert_not_contains "$OUTPUT8" "mentions existing" "plain lowercase words are not searched"

finish
