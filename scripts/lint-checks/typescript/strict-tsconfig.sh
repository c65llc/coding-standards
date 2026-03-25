#!/bin/bash
# Check: TypeScript strict mode in tsconfig.json
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="typescript/strict-tsconfig"

TSCONFIG_FOUND=""

# Look for tsconfig.json in root or common locations
for cfg in tsconfig.json tsconfig.base.json tsconfig.app.json; do
    if [ -f "$PROJECT_ROOT/$cfg" ]; then
        TSCONFIG_FOUND="$cfg"
        break
    fi
done

# Also check src/ subdirectory
if [ -z "$TSCONFIG_FOUND" ] && [ -f "$PROJECT_ROOT/src/tsconfig.json" ]; then
    TSCONFIG_FOUND="src/tsconfig.json"
fi

if [ -z "$TSCONFIG_FOUND" ]; then
    echo "FAIL $CHECK_NAME No tsconfig.json found"
    exit 1
fi

TSCONFIG_PATH="$PROJECT_ROOT/$TSCONFIG_FOUND"

# Check for "strict": true in the tsconfig
if grep -qE '"strict"\s*:\s*true' "$TSCONFIG_PATH" 2>/dev/null; then
    echo "PASS $CHECK_NAME \"strict\": true found in $TSCONFIG_FOUND"
    exit 0
fi

# Check if strict is explicitly false
if grep -qE '"strict"\s*:\s*false' "$TSCONFIG_PATH" 2>/dev/null; then
    echo "FAIL $CHECK_NAME \"strict\": false in $TSCONFIG_FOUND — strict mode must be enabled"
    exit 1
fi

# strict key not present
echo "WARN $CHECK_NAME $TSCONFIG_FOUND found but \"strict\": true not set in compilerOptions"
exit 2
