#!/bin/bash
# Check: ESLint configuration present
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="typescript/eslint-config"

# Check for various ESLint config file formats
ESLINT_CONFIG_FILES=(
    ".eslintrc"
    ".eslintrc.js"
    ".eslintrc.cjs"
    ".eslintrc.yaml"
    ".eslintrc.yml"
    ".eslintrc.json"
    "eslint.config.js"
    "eslint.config.mjs"
    "eslint.config.cjs"
    "eslint.config.ts"
)

for cfg in "${ESLINT_CONFIG_FILES[@]}"; do
    if [ -f "$PROJECT_ROOT/$cfg" ]; then
        echo "PASS $CHECK_NAME ESLint configured ($cfg)"
        exit 0
    fi
done

# Check package.json for eslintConfig key
if [ -f "$PROJECT_ROOT/package.json" ]; then
    if grep -qE '"eslintConfig"\s*:' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        echo "PASS $CHECK_NAME ESLint configured (eslintConfig in package.json)"
        exit 0
    fi
fi

echo "FAIL $CHECK_NAME No ESLint configuration found (checked .eslintrc*, eslint.config.*, package.json eslintConfig)"
exit 1
