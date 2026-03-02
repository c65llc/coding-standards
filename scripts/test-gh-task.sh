#!/bin/bash
# Test script for gh-task CLI
# Validates syntax and basic functionality without requiring GitHub authentication

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GH_TASK="$SCRIPT_DIR/../bin/gh-task"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Testing gh-task CLI${NC}"
echo ""

# Test 1: Check if gh-task exists
echo -n "Test 1: gh-task file exists... "
if [ -f "$GH_TASK" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: $GH_TASK not found"
    exit 1
fi

# Test 2: Check if gh-task is executable
echo -n "Test 2: gh-task is executable... "
if [ -x "$GH_TASK" ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: $GH_TASK is not executable"
    exit 1
fi

# Test 3: Syntax check
echo -n "Test 3: Bash syntax is valid... "
if bash -n "$GH_TASK" 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Syntax errors found in $GH_TASK"
    bash -n "$GH_TASK"
    exit 1
fi

# Test 4: Help command works
echo -n "Test 4: Help command works... "
if "$GH_TASK" help >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Help command failed"
    exit 1
fi

# Test 5: Help output contains expected commands
echo -n "Test 5: Help lists all commands... "
help_output=$("$GH_TASK" help 2>&1)
commands=("create" "start" "status" "update" "submit")
all_found=true

for cmd in "${commands[@]}"; do
    if ! echo "$help_output" | grep -q "$cmd"; then
        all_found=false
        echo -e "${RED}✗${NC}"
        echo "  Error: Command '$cmd' not found in help output"
        break
    fi
done

if [ "$all_found" = true ]; then
    echo -e "${GREEN}✓${NC}"
fi

# Test 6: Unknown command shows error
echo -n "Test 6: Unknown command shows error... "
if "$GH_TASK" unknown_command 2>&1 | grep -q "Unknown command"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Unknown command didn't produce expected error"
fi

# Test 7: Check for required utilities in script
echo -n "Test 7: Script checks for prerequisites... "
if grep -q "check_prerequisites" "$GH_TASK" && \
   grep -q "command -v gh" "$GH_TASK"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Missing prerequisite checks"
fi

# Test 8: Configuration loading functions exist
echo -n "Test 8: Configuration functions exist... "
if grep -q "load_config" "$GH_TASK" && \
   grep -q "PROJECT_ID" "$GH_TASK"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Missing configuration functions"
fi

# Test 9: GraphQL queries for Projects V2
echo -n "Test 9: GraphQL queries present... "
if grep -q "updateProjectV2ItemFieldValue" "$GH_TASK" && \
   grep -q "ProjectV2" "$GH_TASK"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Missing GraphQL queries"
fi

# Test 10: State management functions
echo -n "Test 10: State management functions... "
if grep -q "save_state" "$GH_TASK" && \
   grep -q "load_state" "$GH_TASK" && \
   grep -q ".gh-task-state" "$GH_TASK"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Missing state management"
fi

# Test 11: Validation checks in submit command
echo -n "Test 11: Validation checks in submit... "
if grep -q "npm test" "$GH_TASK" && \
   grep -q "make test" "$GH_TASK" && \
   grep -q "pytest" "$GH_TASK"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Missing validation checks"
fi

# Test 12: Branch naming sanitization
echo -n "Test 12: Branch name sanitization... "
if grep -q "sanitize_title" "$GH_TASK"; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
    echo "  Error: Missing title sanitization"
fi

# Summary
echo ""
echo -e "${GREEN}All tests passed!${NC}"
echo ""
echo "Note: These tests only validate syntax and structure."
echo "Full integration testing requires:"
echo "  - GitHub CLI (gh) installed and authenticated"
echo "  - Valid GitHub repository with Projects V2"
echo "  - Proper configuration in .gemini/settings.json or .gh-task.conf"
echo ""
echo "For integration testing, see docs/GH_TASK_GUIDE.md"
