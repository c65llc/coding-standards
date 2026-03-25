#!/bin/bash
# Check: Credo static analysis configured in mix.exs
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="elixir/credo-config"

if [ ! -f "$PROJECT_ROOT/mix.exs" ]; then
    echo "FAIL $CHECK_NAME No mix.exs found — not an Elixir project"
    exit 1
fi

# Check for :credo in mix.exs deps
if grep -qE '^\s*\{?:credo' "$PROJECT_ROOT/mix.exs" 2>/dev/null; then
    # Check if it's only a dev/test dep (common pattern)
    if grep -E '^\s*\{?:credo' "$PROJECT_ROOT/mix.exs" 2>/dev/null | grep -qE 'only:\s*(dev|test|\[)'; then
        echo "PASS $CHECK_NAME Credo configured in mix.exs (dev/test dependency)"
    else
        echo "PASS $CHECK_NAME Credo configured in mix.exs"
    fi
    exit 0
fi

# Check for .credo.exs config file as backup indicator
if [ -f "$PROJECT_ROOT/.credo.exs" ]; then
    echo "WARN $CHECK_NAME .credo.exs found but :credo not in mix.exs deps"
    exit 2
fi

echo "FAIL $CHECK_NAME :credo not found in mix.exs dependencies"
exit 1
