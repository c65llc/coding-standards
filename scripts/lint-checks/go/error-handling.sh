#!/bin/bash
# Check: Go error handling — scan for ignored errors (bare _ assignments)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="go/error-handling"

# Find Go source files (exclude vendor/, generated files, test files for some patterns)
GO_FILES=$(find "$PROJECT_ROOT" -name "*.go" \
    -not -path "*/.git/*" \
    -not -path "*/vendor/*" \
    -not -path "*/.standards/*" \
    -not -path "*/.standards_tmp/*" \
    2>/dev/null)

if [ -z "$GO_FILES" ]; then
    echo "PASS $CHECK_NAME No Go files found to check"
    exit 0
fi

VIOLATIONS=""

# Pattern: `_ = someFunc()` — discarding a return value (likely an error)
# This catches `_ = f.Close()`, `_ = fmt.Fprintf(...)` etc.
blank_assign=$(echo "$GO_FILES" | xargs grep -nE '^\s*_\s*=\s*\w+' 2>/dev/null \
    | grep -v '_test\.go' \
    | head -10 || true)

if [ -n "$blank_assign" ]; then
    count=$(echo "$blank_assign" | wc -l | tr -d ' ')
    first=$(echo "$blank_assign" | head -1 | sed "s|$PROJECT_ROOT/||")
    VIOLATIONS="${VIOLATIONS}Ignored return values (_ = ...) $count occurrence(s), first: $first; "
fi

# Pattern: multi-return `_, err := ...` where err itself is then ignored
# More specifically: `x, _ := someFunc()` where the second return might be an error
blank_multi=$(echo "$GO_FILES" | xargs grep -nE ',\s*_\s*:?=\s*\w+' 2>/dev/null \
    | grep -v '_test\.go' \
    | grep -v '//.*ignore' \
    | head -10 || true)

if [ -n "$blank_multi" ]; then
    count=$(echo "$blank_multi" | wc -l | tr -d ' ')
    first=$(echo "$blank_multi" | head -1 | sed "s|$PROJECT_ROOT/||")
    if [ -z "$VIOLATIONS" ]; then
        VIOLATIONS="${VIOLATIONS}Multi-return blanked values (, _ := ...) $count occurrence(s), first: $first; "
    fi
fi

if [ -z "$VIOLATIONS" ]; then
    echo "PASS $CHECK_NAME No ignored error patterns detected in Go files"
    exit 0
else
    VIOLATIONS="${VIOLATIONS%; }"
    echo "WARN $CHECK_NAME Potential unchecked errors — $VIOLATIONS"
    exit 2
fi
