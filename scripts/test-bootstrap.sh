#!/bin/bash
# Functional tests for detect-languages.sh and build-claude-settings.sh
# Validates actual script behavior using temp directories with cleanup.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect-languages.sh"
BUILD="$SCRIPT_DIR/build-claude-settings.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_TEMPLATE="$REPO_ROOT/standards/agents/claude-code/settings.json.example"
PERMISSIONS_DIR="$REPO_ROOT/standards/agents/claude-code/permissions"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

# Create a temp directory with automatic cleanup
TMPDIR_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-bootstrap.XXXXXX")"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() {
    echo -e "${GREEN}✓${NC}"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "${RED}✗${NC}"
    echo "  Error: $1"
    FAIL=$((FAIL + 1))
}

echo -e "${BLUE}Testing language-aware bootstrap scripts${NC}"
echo ""

# ---------- detect-languages.sh ----------

# Test 1: Single language (Rust)
echo -n "Test 1:  detect-languages — single language (Rust)... "
dir="$TMPDIR_BASE/t1" && mkdir -p "$dir"
touch "$dir/Cargo.toml"
output="$("$DETECT" "$dir")"
if [ "$output" = "rust" ]; then
    pass
else
    fail "expected 'rust', got '$output'"
fi

# Test 2: Multi-language (Python + JS)
echo -n "Test 2:  detect-languages — multi-language (Python + JS)... "
dir="$TMPDIR_BASE/t2" && mkdir -p "$dir"
touch "$dir/pyproject.toml" "$dir/package.json"
output="$("$DETECT" "$dir")"
if echo "$output" | grep -q "python" && echo "$output" | grep -q "javascript"; then
    pass
else
    fail "expected python and javascript, got '$output'"
fi

# Test 3: All 8 languages
echo -n "Test 3:  detect-languages — all 8 languages... "
dir="$TMPDIR_BASE/t3" && mkdir -p "$dir"
touch "$dir/pyproject.toml"   # python
touch "$dir/Cargo.toml"       # rust
touch "$dir/Gemfile"          # ruby
touch "$dir/package.json"     # javascript
touch "$dir/build.gradle"     # jvm
touch "$dir/Package.swift"    # swift
touch "$dir/pubspec.yaml"     # dart
touch "$dir/build.zig"        # zig
output="$("$DETECT" "$dir")"
count="$(echo "$output" | wc -l | tr -d ' ')"
if [ "$count" -eq 8 ]; then
    pass
else
    fail "expected 8 languages, got $count: $output"
fi

# Test 4: Empty project
echo -n "Test 4:  detect-languages — empty project (no manifests)... "
dir="$TMPDIR_BASE/t4" && mkdir -p "$dir"
output="$("$DETECT" "$dir")"
if [ -z "$output" ]; then
    pass
else
    fail "expected empty output, got '$output'"
fi

# ---------- build-claude-settings.sh ----------

# Test 5: No languages — outputs base template unchanged
echo -n "Test 5:  build-claude-settings — no languages (base template)... "
output="$("$BUILD" "$BASE_TEMPLATE" "$PERMISSIONS_DIR"  < /dev/null)"
expected="$(cat "$BASE_TEMPLATE")"
if [ "$output" = "$expected" ]; then
    pass
else
    fail "output differs from base template"
fi

# Test 6: Single language produces valid JSON
echo -n "Test 6:  build-claude-settings — single language valid JSON... "
output="$("$BUILD" "$BASE_TEMPLATE" "$PERMISSIONS_DIR" rust)"
if echo "$output" | python3 -m json.tool > /dev/null 2>&1; then
    pass
else
    fail "output is not valid JSON"
fi

# Test 7: Multiple languages produces valid JSON
echo -n "Test 7:  build-claude-settings — multiple languages valid JSON... "
output="$("$BUILD" "$BASE_TEMPLATE" "$PERMISSIONS_DIR" python rust javascript)"
if echo "$output" | python3 -m json.tool > /dev/null 2>&1; then
    pass
else
    fail "output is not valid JSON"
fi

# Test 8: All 8 languages produces valid JSON
echo -n "Test 8:  build-claude-settings — all 8 languages valid JSON... "
output="$("$BUILD" "$BASE_TEMPLATE" "$PERMISSIONS_DIR" python rust ruby javascript jvm swift dart zig)"
if echo "$output" | python3 -m json.tool > /dev/null 2>&1; then
    pass
else
    fail "output is not valid JSON"
fi

# Test 9: Content check — expected commands present
echo -n "Test 9:  build-claude-settings — content check (cargo test, pytest)... "
output="$("$BUILD" "$BASE_TEMPLATE" "$PERMISSIONS_DIR" python rust)"
if echo "$output" | grep -q "cargo test" && echo "$output" | grep -q "pytest"; then
    pass
else
    fail "expected 'cargo test' and 'pytest' in output"
fi

# Test 10: Dotfile copy — shopt -s dotglob covers dotfiles
echo -n "Test 10: dotfile glob — dotfiles matched by shopt -s dotglob... "
dir="$TMPDIR_BASE/t10_src" && mkdir -p "$dir"
dest="$TMPDIR_BASE/t10_dst" && mkdir -p "$dest"
touch "$dir/.prettierrc" "$dir/.eslintrc" "$dir/normal.txt"
(
    cd "$dir"
    shopt -s dotglob
    cp ./* "$dest/"
)
if [ -f "$dest/.prettierrc" ] && [ -f "$dest/.eslintrc" ] && [ -f "$dest/normal.txt" ]; then
    pass
else
    fail "dotfiles were not copied — dotglob not working"
fi

# ---------- Summary ----------
echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL tests passed!${NC}"
else
    echo -e "${RED}$FAIL of $TOTAL tests failed${NC}"
    exit 1
fi
