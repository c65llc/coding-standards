#!/bin/bash
# Check: Python type annotations / mypy configuration
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="python/type-annotations"

MYPY_FOUND=""
STRICT_MODE=""

# Check pyproject.toml for [tool.mypy]
if [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    if grep -qE '^\[tool\.mypy\]' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
        MYPY_FOUND="pyproject.toml [tool.mypy]"
        if grep -qE 'strict\s*=\s*true' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
            STRICT_MODE="strict = true"
        fi
        # Also check for strict-equivalent individual settings
        if [ -z "$STRICT_MODE" ]; then
            disallow_untyped=$(grep -E 'disallow_untyped_defs\s*=\s*true' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null | wc -l | tr -d ' ')
            disallow_any=$(grep -E 'disallow_any_generics\s*=\s*true' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null | wc -l | tr -d ' ')
            if [ "$disallow_untyped" -gt 0 ] && [ "$disallow_any" -gt 0 ]; then
                STRICT_MODE="strict-equivalent settings"
            fi
        fi
    fi
fi

# Check .mypy.ini
if [ -z "$MYPY_FOUND" ] && [ -f "$PROJECT_ROOT/.mypy.ini" ]; then
    MYPY_FOUND=".mypy.ini"
    if grep -qE '^strict\s*=\s*True' "$PROJECT_ROOT/.mypy.ini" 2>/dev/null; then
        STRICT_MODE="strict = True"
    fi
fi

# Check mypy.ini
if [ -z "$MYPY_FOUND" ] && [ -f "$PROJECT_ROOT/mypy.ini" ]; then
    MYPY_FOUND="mypy.ini"
    if grep -qE '^strict\s*=\s*True' "$PROJECT_ROOT/mypy.ini" 2>/dev/null; then
        STRICT_MODE="strict = True"
    fi
fi

# Check setup.cfg [mypy]
if [ -z "$MYPY_FOUND" ] && [ -f "$PROJECT_ROOT/setup.cfg" ]; then
    if grep -qE '^\[mypy\]' "$PROJECT_ROOT/setup.cfg" 2>/dev/null; then
        MYPY_FOUND="setup.cfg [mypy]"
        if grep -qE '^strict\s*=\s*True' "$PROJECT_ROOT/setup.cfg" 2>/dev/null; then
            STRICT_MODE="strict = True"
        fi
    fi
fi

if [ -z "$MYPY_FOUND" ]; then
    echo "FAIL $CHECK_NAME No mypy configuration found (checked pyproject.toml, .mypy.ini, mypy.ini, setup.cfg)"
    exit 1
elif [ -z "$STRICT_MODE" ]; then
    echo "WARN $CHECK_NAME mypy configured in $MYPY_FOUND but strict mode not enabled"
    exit 2
else
    echo "PASS $CHECK_NAME mypy strict mode enabled in $MYPY_FOUND"
    exit 0
fi
