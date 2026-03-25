#!/bin/bash
# Check: test directory exists and contains plausible test files
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="test-directory"

# Look for a tests/test/spec directory
TEST_DIR=""
for candidate in tests test spec __tests__; do
    if [ -d "$PROJECT_ROOT/$candidate" ]; then
        TEST_DIR="$PROJECT_ROOT/$candidate"
        TEST_DIR_NAME="$candidate"
        break
    fi
done

if [ -z "$TEST_DIR" ]; then
    echo "FAIL $CHECK_NAME No test directory found (looked for: tests/, test/, spec/, __tests__/)"
    exit 1
fi

# If src/ exists, check that tests mirror source structure
if [ -d "$PROJECT_ROOT/src" ]; then
    # Count top-level subdirs in src/
    src_subdirs=$(find "$PROJECT_ROOT/src" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

    if [ "$src_subdirs" -eq 0 ]; then
        echo "PASS $CHECK_NAME Test directory '$TEST_DIR_NAME/' found (no subdirectories in src/ to mirror)"
        exit 0
    fi

    # Check if at least some test files exist
    test_files=$(find "$TEST_DIR" -name "*.test.*" -o -name "*.spec.*" -o -name "test_*" -o -name "*_test.*" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$test_files" -gt 0 ]; then
        echo "PASS $CHECK_NAME Test directory '$TEST_DIR_NAME/' found with $test_files test file(s)"
        exit 0
    else
        echo "WARN $CHECK_NAME Test directory '$TEST_DIR_NAME/' found but appears empty (no test files detected)"
        exit 2
    fi
else
    # No src/ directory — just check that test dir is non-empty
    test_files=$(find "$TEST_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$test_files" -gt 0 ]; then
        echo "PASS $CHECK_NAME Test directory '$TEST_DIR_NAME/' found with $test_files file(s)"
        exit 0
    else
        echo "WARN $CHECK_NAME Test directory '$TEST_DIR_NAME/' exists but is empty"
        exit 2
    fi
fi
