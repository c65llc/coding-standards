#!/bin/bash
# Test scripts/format-results.py against representative inputs.
#
# Usage:
#   ./scripts/test-format-results.sh
#
# Run from the standards repo root (or any directory; uses absolute path
# discovery via $0).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORMATTER="$REPO_ROOT/.github/actions/standards-review/format-results.py"

if [ ! -f "$FORMATTER" ]; then
    echo "FAIL: formatter not found at $FORMATTER" >&2
    exit 1
fi

PASS=0
FAIL=0

assert_eq() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
        printf "  ✅ %s\n" "$label"
    else
        FAIL=$((FAIL + 1))
        printf "  ❌ %s\n" "$label"
        printf "     expected: %q\n" "$expected"
        printf "     actual:   %q\n" "$actual"
    fi
}

# Test 1: valid JSON with multiple results — emits one row per result
out=$(python3 "$FORMATTER" '{"results":[{"status":"PASS","check":"naming","message":"ok"},{"status":"FAIL","check":"secrets","message":"hardcoded key | found"}]}')
expected=$(printf '| :white_check_mark: PASS | naming | ok |\n| :x: FAIL | secrets | hardcoded key \\| found |')
assert_eq "valid JSON renders rows with pipe-escaping" "$expected" "$out"

# Test 2: empty results array — emits nothing
out=$(python3 "$FORMATTER" '{"results":[]}')
assert_eq "empty results array → no output" "" "$out"

# Test 3: malformed JSON — degrades to no output (does not crash)
out=$(python3 "$FORMATTER" 'not-json')
assert_eq "malformed JSON → no output" "" "$out"

# Test 4: no args — uses default empty object → no output
out=$(python3 "$FORMATTER")
assert_eq "no args → no output" "" "$out"

# Test 5: JSON root is an array (not object) — does not crash, no output
out=$(python3 "$FORMATTER" '[]')
assert_eq "JSON array root → no output (no AttributeError)" "" "$out"

# Test 6: JSON root is null — does not crash, no output
out=$(python3 "$FORMATTER" 'null')
assert_eq "JSON null root → no output" "" "$out"

# Test 7: JSON root is a string — does not crash, no output
out=$(python3 "$FORMATTER" '"some string"')
assert_eq "JSON string root → no output" "" "$out"

# Test 8: results field is not a list — does not crash, no output
out=$(python3 "$FORMATTER" '{"results":"not-a-list"}')
assert_eq "results field non-list → no output" "" "$out"

# Test 9: result missing fields — uses empty defaults, still emits row with grey_question icon
out=$(python3 "$FORMATTER" '{"results":[{}]}')
expected="| :grey_question:  |  |  |"
assert_eq "result with missing fields → row with grey_question icon" "$expected" "$out"

# Test 10: newlines in message are flattened to spaces (so table renders correctly)
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"naming","message":"line1\nline2"}]}')
expected="| :warning: WARN | naming | line1 line2 |"
assert_eq "newlines in message flatten to spaces" "$expected" "$out"

echo ""
echo "format-results.py tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
