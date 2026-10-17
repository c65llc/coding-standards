#!/bin/bash
# Check: cargo-deny configuration with a license allow-list
# (lang-08 §20/§21: `cargo deny check` in CI, licenses allow-listed in deny.toml)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="rust/deny-config"

DENY_FILE=""
for candidate in deny.toml .deny.toml .cargo/deny.toml; do
    if [ -f "$PROJECT_ROOT/$candidate" ]; then
        DENY_FILE="$candidate"
        break
    fi
done

if [ -z "$DENY_FILE" ]; then
    echo "FAIL $CHECK_NAME No deny.toml found (checked deny.toml, .deny.toml, .cargo/deny.toml) — add one with a [licenses] allow-list and run 'cargo deny check' in CI"
    exit 1
fi

DENY_PATH="$PROJECT_ROOT/$DENY_FILE"

# Need a [licenses] table whose `allow = [...]` list is non-empty.
has_licenses=$(grep -cE '^\[licenses\]' "$DENY_PATH" 2>/dev/null | tr -d ' ')
# Extract the [licenses] table body (up to the next table header).
licenses_body=$(awk '/^\[licenses\]/{found=1;next} found && /^\[/{exit} found{print}' "$DENY_PATH" 2>/dev/null)

if [ "${has_licenses:-0}" -eq 0 ]; then
    echo "WARN $CHECK_NAME $DENY_FILE present but has no [licenses] section — add 'allow = [\"MIT\", \"Apache-2.0\", ...]'"
    exit 2
fi

# allow = [ ... ] may be inline or multi-line; require at least one quoted SPDX id.
allow_block=$(printf '%s\n' "$licenses_body" | awk '/^[[:space:]]*allow[[:space:]]*=/{found=1} found{print} found && /\]/{exit}')
if [ -z "$allow_block" ] || ! printf '%s' "$allow_block" | grep -qE '"[^"]+"'; then
    echo "WARN $CHECK_NAME $DENY_FILE has [licenses] but no non-empty 'allow = [...]' list — licenses are not allow-listed"
    exit 2
fi

count=$(printf '%s' "$allow_block" | grep -oE '"[^"]+"' | wc -l | tr -d ' ')
echo "PASS $CHECK_NAME $DENY_FILE allow-lists $count license(s)"
exit 0
