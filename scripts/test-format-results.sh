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

# Test 11: a member other than the root prefixes the check name (monorepo runs, #179)
out=$(python3 "$FORMATTER" '{"results":[{"status":"FAIL","check":"python/banned-functions","member":"server","message":"eval found"}]}')
expected="| :x: FAIL | \`server\`: python/banned-functions | eval found |"
assert_eq "member prefixes the check name" "$expected" "$out"

# Test 12: the root member (".") and a missing member field render the bare check name
out=$(python3 "$FORMATTER" '{"results":[{"status":"PASS","check":"no-secrets","member":".","message":"ok"},{"status":"PASS","check":"naming","message":"ok"}]}')
expected=$(printf '| :white_check_mark: PASS | no-secrets | ok |\n| :white_check_mark: PASS | naming | ok |')
assert_eq "root member and absent member render the bare check" "$expected" "$out"

# Test 13: a member value containing a pipe cannot break the table
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"c","member":"a|b","message":"m"}]}')
expected="| :warning: WARN | \`a\\|b\`: c | m |"
assert_eq "pipe in member is escaped" "$expected" "$out"

# Test 14: a member value is repo-controlled: mentions, links, images and code
# spans are neutralised and the remainder is shown as a literal code span
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"c","member":"@org/team ![x](https://evil/i.png) <b>`q`","message":"m"}]}')
expected="| :warning: WARN | \`org/team !xhttps://evil/i.png bq\`: c | m |"
assert_eq "mentions, links and markup in member are neutralised" "$expected" "$out"

# Test 15: a member made only of markup still renders a placeholder
out=$(python3 "$FORMATTER" '{"results":[{"status":"PASS","check":"c","member":"@[]","message":"m"}]}')
expected="| :white_check_mark: PASS | \`member\`: c | m |"
assert_eq "markup-only member falls back to a placeholder" "$expected" "$out"

# Test 16: the synthetic members check quotes declared paths in its message, so
# that message is neutralised too; other checks' messages are left as they are
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"members","member":".","message":"declared member '"'"'@org/team'"'"' not found [x](https://evil)"},{"status":"PASS","check":"naming","member":".","message":"ok (see @docs)"}]}')
expected=$(printf "| :warning: WARN | members | declared member 'org/team' not found xhttps://evil |\n| :white_check_mark: PASS | naming | ok (see @docs) |")
assert_eq "members-check message is neutralised, others untouched" "$expected" "$out"

echo ""
echo "format-results.py tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
