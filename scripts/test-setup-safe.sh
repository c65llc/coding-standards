#!/bin/bash
# Functional tests for Standards 1.2 safe-setup behavior.
# Each test creates a temp project, runs setup.sh, and asserts outcomes.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMPDIR_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-setup-safe.XXXXXX")"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

make_project() {
    local name="$1"
    local dir="$TMPDIR_BASE/$name"
    mkdir -p "$dir"
    (cd "$dir" && git init -q \
        && git -c user.email="test@test.local" -c user.name="Test" \
               commit -q --allow-empty -m "init")
    echo "$dir"
}

echo -e "${BLUE}Testing Standards 1.2 safe-setup behavior${NC}"
echo ""

echo -n "Test 1: setup.sh exists and is executable... "
if [ -x "$SETUP" ]; then pass; else fail "$SETUP not executable"; fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}$FAIL failures${NC}"
    exit 1
fi
echo -e "${GREEN}All $PASS tests passed!${NC}"
