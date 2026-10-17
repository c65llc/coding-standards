#!/bin/bash
# Check: Python banned functions (eval, exec, pickle.loads, os.system, subprocess shell=True)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# File enumeration (git ls-files with pruned-find fallback, built-in
# cache/worktree exclusions, `.standards.yml` lint.exclude) lives in
# scripts/lib/lint-files.sh. docs/ is excluded by default: mockups and
# snippets there are not shipped code. Test files are intentionally included.

PROJECT_ROOT="${1:-.}"

CHECK_NAME="python/banned-functions"

LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../lib/lint-files.sh
source "$LINT_LIB"

PYTHON_FILES=$(lint_list_files "$PROJECT_ROOT" docs | grep -E '\.py$' || true)

# Filenames containing a newline cannot be carried by the file list; report
# them rather than skipping them silently.
UNSCANNABLE=$(lint_unscannable_files "$PROJECT_ROOT" docs | grep -E '\.py$' || true)

if [ -z "$PYTHON_FILES" ] && [ -z "$UNSCANNABLE" ]; then
    echo "PASS $CHECK_NAME No Python files found to check"
    exit 0
fi

VIOLATIONS=""

check_pattern() {
    local label="$1"
    local pattern="$2"
    local results first_match count
    # lint_grep_hits yields "<relative path>:<line>:<content>" and drops lines
    # whose content starts with "#" (anchored on the per-file "<line>:" prefix,
    # so neither the filename nor the content can forge a suppression).
    results=$(lint_grep_hits "$PYTHON_FILES" "$PROJECT_ROOT" '#' "$pattern" | head -5)
    if [ -n "$results" ]; then
        first_match=$(echo "$results" | head -1)
        count=$(echo "$results" | wc -l | tr -d ' ')
        if [ "$count" -eq 1 ]; then
            VIOLATIONS="${VIOLATIONS}${label} at $first_match; "
        else
            VIOLATIONS="${VIOLATIONS}${label} ($count occurrences, first: $first_match); "
        fi
    fi
}

check_pattern "eval()" 'eval\('
check_pattern "exec()" 'exec\('
check_pattern "pickle.loads()" 'pickle\.loads\('
check_pattern "os.system()" 'os\.system\('
check_pattern "subprocess shell=True" 'subprocess\.(call|run|Popen|check_call|check_output).*shell\s*=\s*True'

if [ -n "$UNSCANNABLE" ]; then
    n=$(echo "$UNSCANNABLE" | wc -l | tr -d ' ')
    VIOLATIONS="${VIOLATIONS}${n} file(s) not scanned (newline in filename): $(echo "$UNSCANNABLE" | head -3 | tr '\n' ' '); "
fi

if [ -z "$VIOLATIONS" ]; then
    echo "PASS $CHECK_NAME No banned function calls detected in Python files"
    exit 0
else
    # Trim trailing semicolon+space
    VIOLATIONS="${VIOLATIONS%; }"
    echo "FAIL $CHECK_NAME Banned functions found — $VIOLATIONS"
    exit 1
fi
