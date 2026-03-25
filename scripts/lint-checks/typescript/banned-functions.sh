#!/bin/bash
# Check: TypeScript/JavaScript banned functions
# (eval, new Function(), innerHTML, document.write, setTimeout with string)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="typescript/banned-functions"

# Find TS/JS files (exclude node_modules, dist, build, .git)
TS_JS_FILES=$(find "$PROJECT_ROOT" \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" \) \
    -not -path "*/.git/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/.next/*" \
    -not -path "*/coverage/*" \
    -not -path "*/.standards/*" \
    -not -path "*/.standards_tmp/*" \
    -not -name "*.min.js" \
    -not -name "*.d.ts" \
    2>/dev/null)

if [ -z "$TS_JS_FILES" ]; then
    echo "PASS $CHECK_NAME No TypeScript/JavaScript files found to check"
    exit 0
fi

VIOLATIONS=""

check_pattern() {
    local label="$1"
    local pattern="$2"
    local results
    results=$(while IFS= read -r file; do
        grep -nE "$pattern" "$file" 2>/dev/null || true
    done <<< "$TS_JS_FILES" \
        | grep -v '^\s*//' \
        | grep -v '^\s*\*' \
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

check_pattern "eval()" '\beval\s*\('
check_pattern "new Function()" 'new\s+Function\s*\('
check_pattern "innerHTML" '\.innerHTML\s*='
check_pattern "document.write()" 'document\.write\s*\('
# setTimeout/setInterval with string argument (not arrow function or named function ref)
check_pattern "setTimeout with string" 'setTimeout\s*\(\s*["'"'"']'

if [ -z "$VIOLATIONS" ]; then
    echo "PASS $CHECK_NAME No banned function calls detected in TypeScript/JavaScript files"
    exit 0
else
    VIOLATIONS="${VIOLATIONS%; }"
    echo "FAIL $CHECK_NAME Banned functions found — $VIOLATIONS"
    exit 1
fi
