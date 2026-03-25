#!/bin/bash
# Check: Dialyxir (Dialyzer) configured in mix.exs
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="elixir/dialyzer-config"

if [ ! -f "$PROJECT_ROOT/mix.exs" ]; then
    echo "FAIL $CHECK_NAME No mix.exs found — not an Elixir project"
    exit 1
fi

# Check for :dialyxir in mix.exs deps
if grep -qE '^\s*\{?:dialyxir' "$PROJECT_ROOT/mix.exs" 2>/dev/null; then
    if grep -E '^\s*\{?:dialyxir' "$PROJECT_ROOT/mix.exs" 2>/dev/null | grep -qE 'only:\s*(dev|\[)'; then
        echo "PASS $CHECK_NAME Dialyxir configured in mix.exs (dev dependency)"
    else
        echo "PASS $CHECK_NAME Dialyxir configured in mix.exs"
    fi
    exit 0
fi

# Check for dialyzer PLT config in mix.exs as a weaker signal
if grep -qE 'dialyzer:' "$PROJECT_ROOT/mix.exs" 2>/dev/null; then
    echo "WARN $CHECK_NAME dialyzer config found in mix.exs but :dialyxir dependency missing"
    exit 2
fi

echo "FAIL $CHECK_NAME :dialyxir not found in mix.exs dependencies"
exit 1
