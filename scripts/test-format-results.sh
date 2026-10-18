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
expected=$(printf '| :white_check_mark: PASS | naming | `ok` |\n| :x: FAIL | secrets | `hardcoded key \\| found` |')
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
expected="| :warning: WARN | naming | \`line1 line2\` |"
assert_eq "newlines in message flatten to spaces" "$expected" "$out"

# Test 11: a member other than the root prefixes the check name (monorepo runs, #179)
out=$(python3 "$FORMATTER" '{"results":[{"status":"FAIL","check":"python/banned-functions","member":"server","message":"eval found"}]}')
expected="| :x: FAIL | \`server\`: python/banned-functions | \`eval found\` |"
assert_eq "member prefixes the check name" "$expected" "$out"

# Test 12: the root member (".") and a missing member field render the bare check name
out=$(python3 "$FORMATTER" '{"results":[{"status":"PASS","check":"no-secrets","member":".","message":"ok"},{"status":"PASS","check":"naming","message":"ok"}]}')
expected=$(printf '| :white_check_mark: PASS | no-secrets | `ok` |\n| :white_check_mark: PASS | naming | `ok` |')
assert_eq "root member and absent member render the bare check" "$expected" "$out"

# Test 13: a member value containing a pipe cannot break the table
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"c","member":"a|b","message":"m"}]}')
expected="| :warning: WARN | \`a\\|b\`: c | \`m\` |"
assert_eq "pipe in member is escaped" "$expected" "$out"

# Test 14: a member value is repo-controlled: mentions, links, images and code
# spans are neutralised and the remainder is shown as a literal code span
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"c","member":"@org/team ![x](https://evil/i.png) <b>`q`","message":"m"}]}')
expected="| :warning: WARN | \`org/team !xhttps://evil/i.png bq\`: c | \`m\` |"
assert_eq "mentions, links and markup in member are neutralised" "$expected" "$out"

# Test 15: a member made only of markup still renders a placeholder
out=$(python3 "$FORMATTER" '{"results":[{"status":"PASS","check":"c","member":"@[]","message":"m"}]}')
expected="| :white_check_mark: PASS | \`member\`: c | \`m\` |"
assert_eq "markup-only member falls back to a placeholder" "$expected" "$out"

# Test 16: every message (members check or not) is a literal code span, so a
# quoted member path, a Markdown link or a mention cannot become active markup;
# the text itself is preserved verbatim (no characters deleted)
out=$(python3 "$FORMATTER" '{"results":[{"status":"WARN","check":"members","member":".","message":"declared member '"'"'@org/team'"'"' not found [x](https://evil)"},{"status":"PASS","check":"naming","member":".","message":"ok (see @docs)"}]}')
expected=$(printf "| :warning: WARN | members | \`declared member '@org/team' not found [x](https://evil)\` |\n| :white_check_mark: PASS | naming | \`ok (see @docs)\` |")
assert_eq "every check message is a literal code span" "$expected" "$out"

# Test 17: a non-members check echoing repo content cannot inject a link, bare
# autolinked URL, mention, image, HTML or code span: backticks (the only
# character that could end the span) become apostrophes, everything else is literal
out=$(python3 "$FORMATTER" '{"results":[{"status":"FAIL","check":"doc-lint","member":".","message":"docs/a.md -> `](https://evil) @user <img src=x> ![i](u)"}]}')
expected="| :x: FAIL | doc-lint | \`docs/a.md -> '](https://evil) @user <img src=x> ![i](u)\` |"
assert_eq "hostile doc-lint message cannot leave its code span" "$expected" "$out"

# Test 18: legitimate paths and config keys keep their characters
out=$(python3 "$FORMATTER" '{"results":[{"status":"FAIL","check":"ruff","member":".","message":"packages/@scope/app/pyproject.toml: missing [tool.ruff]"}]}')
expected="| :x: FAIL | ruff | \`packages/@scope/app/pyproject.toml: missing [tool.ruff]\` |"
assert_eq "literal @ and brackets in diagnostics are preserved" "$expected" "$out"

# Test 19: an empty message renders an empty cell, not an empty code span
out=$(python3 "$FORMATTER" '{"results":[{"status":"PASS","check":"c","member":".","message":"   "}]}')
expected="| :white_check_mark: PASS | c |  |"
assert_eq "blank message renders an empty cell" "$expected" "$out"

# Test 20: messages are length-capped (500 chars + ellipsis) so a PR cannot flood a row
long=$(python3 -c 'print("x"*900)')
out=$(python3 "$FORMATTER" "{\"results\":[{\"status\":\"PASS\",\"check\":\"c\",\"member\":\".\",\"message\":\"$long\"}]}")
expected="| :white_check_mark: PASS | c | \`$(python3 -c 'print("x"*500)') …\` |"
assert_eq "message is capped at 500 characters with an ellipsis" "$expected" "$out"

# Test 21: the whole table is bounded. 150 PASS rows of 500 chars (~78 KB) exceed
# the budget: PASS rows are dropped first and the omission is stated explicitly,
# while every FAIL/WARN row survives
big=$(python3 -c '
import json
rows=[{"status":"PASS","check":"c%d"%i,"member":".","message":"x"*500} for i in range(150)]
rows.append({"status":"FAIL","check":"secrets","member":".","message":"key found"})
rows.append({"status":"WARN","check":"naming","member":".","message":"odd name"})
print(json.dumps({"results":rows}))')
out=$(python3 "$FORMATTER" "$big")
expected=$(printf '| :x: FAIL | secrets | `key found` |\n| :warning: WARN | naming | `odd name` |\n| :grey_question: TRUNCATED | comment size limit | 150 passing result row(s) not shown; see the workflow log for the full report |')
assert_eq "oversized table drops PASS rows first and says so" "$expected" "$out"

# Test 22: when even the FAIL/WARN rows do not fit, the table is cut at the budget
# and the truncation row counts the rest; the output stays well under GitHub's
# 65536-character comment limit
big=$(python3 -c '
import json
rows=[{"status":"WARN","check":"c%d"%i,"member":".","message":"x"*500} for i in range(300)]
print(json.dumps({"results":rows}))')
out=$(python3 "$FORMATTER" "$big")
n_rows=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
total=$(printf '%s' "$out" | wc -c | tr -d ' ')
last=$(printf '%s\n' "$out" | tail -1)
if [ "$total" -le 51000 ] && [ "$n_rows" -le 201 ] && printf '%s' "$last" | grep -q 'TRUNCATED | comment size limit | [0-9]* further result row(s) not shown'; then
    PASS=$((PASS+1)); printf "  ✅ %s\n" "oversized FAIL/WARN table is cut at the byte budget with a count"
else
    FAIL=$((FAIL+1)); echo "FAIL: table not bounded (rows=$n_rows bytes=$total last=$last)"
fi

# Test 23: a table within the budget is never truncated (no spurious TRUNCATED row)
ok=$(python3 -c '
import json
rows=[{"status":"PASS","check":"c%d"%i,"member":".","message":"fine"} for i in range(200)]
print(json.dumps({"results":rows}))')
out=$(python3 "$FORMATTER" "$ok")
n_rows=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
if [ "$n_rows" -eq 200 ] && ! printf '%s' "$out" | grep -q TRUNCATED; then
    PASS=$((PASS+1)); printf "  ✅ %s\n" "200 short rows fit without truncation"
else
    FAIL=$((FAIL+1)); echo "FAIL: in-budget table was truncated (rows=$n_rows)"
fi

echo ""
echo "format-results.py tests: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
