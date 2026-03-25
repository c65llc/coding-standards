#!/bin/bash
# Check: ruff linter configuration
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="python/ruff-config"

# Check for ruff.toml
if [ -f "$PROJECT_ROOT/ruff.toml" ]; then
    echo "PASS $CHECK_NAME ruff.toml configured"
    exit 0
fi

# Check for .ruff.toml
if [ -f "$PROJECT_ROOT/.ruff.toml" ]; then
    echo "PASS $CHECK_NAME .ruff.toml configured"
    exit 0
fi

# Check pyproject.toml for [tool.ruff]
if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    if grep -qE '^\[tool\.ruff\]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
        echo "PASS $CHECK_NAME [tool.ruff] section configured in pyproject.toml"
        exit 0
    fi
fi

echo "FAIL $CHECK_NAME No ruff configuration found (checked ruff.toml, .ruff.toml, pyproject.toml [tool.ruff])"
exit 1
