#!/bin/bash
# Check: Python banned functions (eval, exec, pickle.loads, os.system, subprocess shell=True)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="python/banned-functions"

# Find Python files (exclude virtual environments and caches; test files are intentionally included)
PYTHON_FILES=$(find "$PROJECT_ROOT" -name "*.py" \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.venv/*" \
    -not -path "*/venv/*" \
    -not -path "*/.tox/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/.standards/*" \
    -not -path "*/.standards_tmp/*" \
    2>/dev/null)

if [ -z "$PYTHON_FILES" ]; then
    echo "PASS $CHECK_NAME No Python files found to check"
    exit 0
fi

VIOLATIONS=""

check_pattern() {
    local label="$1"
    local pattern="$2"
    local results
    results=$(while IFS= read -r file; do
        grep -nE "$pattern" "$file" 2>/dev/null || true
    done <<< "$PYTHON_FILES" \
        | grep -v '^\s*#' \
        | head -5 || true)
    if [ -n "$results" ]; then
        first_match=$(echo "$results" | head -1 | sed "s|$PROJECT_ROOT/||")
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

if [ -z "$VIOLATIONS" ]; then
    echo "PASS $CHECK_NAME No banned function calls detected in Python files"
    exit 0
else
    # Trim trailing semicolon+space
    VIOLATIONS="${VIOLATIONS%; }"
    echo "FAIL $CHECK_NAME Banned functions found — $VIOLATIONS"
    exit 1
fi
