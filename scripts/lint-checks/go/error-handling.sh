#!/bin/bash
# Check: Go error handling — scan for ignored errors (bare _ assignments)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# File enumeration (git ls-files with pruned-find fallback, built-in
# cache/worktree/vendor exclusions, `.standards.yml` lint.exclude, and the
# runner's --since/--changed scope) lives in scripts/lib/lint-files.sh.

PROJECT_ROOT="${1:-.}"

CHECK_NAME="go/error-handling"

LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../lib/lint-files.sh
source "$LINT_LIB"

# Go source files (test files are enumerated but skipped per pattern below)
GO_FILES=$(lint_list_files "$PROJECT_ROOT" | grep -E '\.go$' || true)

# Filenames containing a newline cannot be carried by the file list; report
# them rather than skipping them silently (test files are skipped as below).
UNSCANNABLE=$(lint_unscannable_files "$PROJECT_ROOT" | grep -E '\.go$' | grep -v '_test\.go' || true)

if [ -z "$GO_FILES" ] && [ -z "$UNSCANNABLE" ]; then
    echo "PASS $CHECK_NAME No Go files found to check"
    exit 0
fi

VIOLATIONS=""

if [ -n "$UNSCANNABLE" ]; then
    n=$(echo "$UNSCANNABLE" | wc -l | tr -d ' ')
    VIOLATIONS="${VIOLATIONS}${n} file(s) not scanned (newline in filename): $(echo "$UNSCANNABLE" | head -3 | tr '\n' ' '); "
fi

# Pattern: `_ = someFunc()` — discarding a return value (likely an error)
# This catches `_ = f.Close()`, `_ = fmt.Fprintf(...)` etc.
blank_assign=$(lint_grep_files "$GO_FILES" -nHE '^\s*_\s*=\s*\w+' \
    | grep -v '_test\.go' \
    | head -10 || true)

if [ -n "$blank_assign" ]; then
    count=$(echo "$blank_assign" | wc -l | tr -d ' ')
    first=$(echo "$blank_assign" | head -1 | lint_strip_root "$PROJECT_ROOT")
    VIOLATIONS="${VIOLATIONS}Ignored return values (_ = ...) $count occurrence(s), first: $first; "
fi

# Pattern: multi-return `_, err := ...` where err itself is then ignored
# More specifically: `x, _ := someFunc()` where the second return might be an error
blank_multi=$(lint_grep_files "$GO_FILES" -nHE ',\s*_\s*:?=\s*\w+' \
    | grep -v '_test\.go' \
    | grep -v '//.*ignore' \
    | head -10 || true)

if [ -n "$blank_multi" ]; then
    count=$(echo "$blank_multi" | wc -l | tr -d ' ')
    first=$(echo "$blank_multi" | head -1 | lint_strip_root "$PROJECT_ROOT")
    VIOLATIONS="${VIOLATIONS}Multi-return blanked values (, _ := ...) $count occurrence(s), first: $first; "
fi

if [ -z "$VIOLATIONS" ]; then
    echo "PASS $CHECK_NAME No ignored error patterns detected in Go files"
    exit 0
else
    VIOLATIONS="${VIOLATIONS%; }"
    echo "WARN $CHECK_NAME Potential unchecked errors — $VIOLATIONS"
    exit 2
fi
