#!/bin/bash
# Check: flaky-test quarantine registry is bounded and current (proc-05 § 2)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# Validates the quarantine registry (templates/test-quarantine.json.example):
#   - the file is syntactically valid JSON: an object whose `entries` key is an
#     array, and every element of that array is an object
#   - every entry has non-blank string fields test, issue, owner, reason, added, expires
#   - `test` is an exact id (no wildcards), unique within the registry
#   - `added`/`expires` are real ISO calendar dates, expires >= added
#   - `added` is not in the future (one day of timezone slack)
#   - the window (expires - added) is at most 30 days
#   - no entry is past due (expires < today)
#   - the registry carries no coverage overrides (quarantine never lowers a gate)
#
# Gate rules (proc-05 § 7, scripts/lint-checks/README.md "Writing a gate"):
#   - self-tests the parser AND the validator on every run: the built-in
#     rejecting fixture must trip, the clean fixture must pass, else FAIL
#   - fails closed when a declared registry is missing, empty, or not valid JSON
#   - depends only on bash 3.2 + POSIX awk/sed so results match on every host
#
# An existing registry whose `entries` array is empty is the normal end state
# after the last quarantined test is fixed; it PASSes and the PASS line says so
# explicitly ("0 quarantined test(s)"), per the proc-05 § 7.2 exception for a
# legitimately optional domain.

PROJECT_ROOT="${1:-.}"

CHECK_NAME="quarantine-policy"
MAX_WINDOW_DAYS=30
EXPIRING_SOON_DAYS=3
FUTURE_SLACK_DAYS=1
REQUIRED_FIELDS="test issue owner reason added expires"
DEFAULT_LOCATIONS="test-quarantine.json .github/ci/test-quarantine.json ci/test-quarantine.json tests/test-quarantine.json"
US="$(printf '\037')"

# ---------------------------------------------------------------------------
# Date helpers — pure integer arithmetic, no `date -d` / `date -v` portability
# ---------------------------------------------------------------------------

# days_from_civil Y M D → days since 1970-01-01 (Howard Hinnant's algorithm)
days_from_civil() {
    local y=$((10#$1)) m=$((10#$2)) d=$((10#$3))
    local era yoe mp doy doe
    if [ "$m" -le 2 ]; then y=$((y - 1)); fi
    era=$((y / 400))
    yoe=$((y - era * 400))
    mp=$(((m + 9) % 12))
    doy=$(((153 * mp + 2) / 5 + d - 1))
    doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
    echo $((era * 146097 + doe - 719468))
}

# days_in_month Y M → 28..31, honoring leap years
days_in_month() {
    local y=$((10#$1)) m=$((10#$2))
    case "$m" in
        1|3|5|7|8|10|12) echo 31 ;;
        4|6|9|11) echo 30 ;;
        2)
            if [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; }; then
                echo 29
            else
                echo 28
            fi
            ;;
    esac
}

# iso_to_days YYYY-MM-DD → day number, or non-zero exit on a malformed or
# impossible calendar date (2027-02-31, 2023-02-29, month 13, ...)
iso_to_days() {
    local iso="$1" y m d rest
    case "$iso" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
        *) return 1 ;;
    esac
    y="${iso%%-*}"
    rest="${iso#*-}"
    m="${rest%%-*}"
    d="${rest#*-}"
    if [ "$((10#$m))" -lt 1 ] || [ "$((10#$m))" -gt 12 ]; then return 1; fi
    if [ "$((10#$d))" -lt 1 ] || [ "$((10#$d))" -gt "$(days_in_month "$y" "$m")" ]; then return 1; fi
    days_from_civil "$y" "$m" "$d"
}

# ---------------------------------------------------------------------------
# Registry parsing — a strict recursive-descent JSON reader in POSIX awk
#
# parse_registry < file emits unit-separator (\037) delimited records:
#   ENTRY<US>n                     start of entries[n-1]
#   F<US>n<US>key<US>type<US>value one member of that entry; type is
#                                  s (string, raw JSON text with escapes kept),
#                                  n (number), l (true/false/null), o (object),
#                                  a (array). value is empty unless type is s.
#   END<US>n                       end of that entry
#   OK<US>count                    document valid; count = number of entries
#   ERROR <message>                document rejected (exit status 1)
# Any element of `entries` that is not an object, any missing comma, unquoted
# key, trailing comma, raw control character, bad escape, or trailing garbage
# is an ERROR, so the gate cannot pass a registry a real JSON parser rejects.
# ---------------------------------------------------------------------------

parse_registry() {
    LC_ALL=C awk '
    function fail(msg,   head, ln) {
        head = substr(s, 1, p - 1)
        ln = 1 + gsub(/\n/, "\n", head)
        printf "ERROR %s (line %d)\n", msg, ln
        exit 1
    }
    function peek() { return substr(s, p, 1) }
    function ws(   c) {
        while (p <= n) {
            c = substr(s, p, 1)
            if (c == " " || c == "\t" || c == "\n" || c == "\r") p++
            else break
        }
    }
    function parse_string(   out, c, h) {
        p++
        out = ""
        while (1) {
            if (p > n) fail("unterminated string")
            c = substr(s, p, 1)
            if (c == "\"") { p++; return out }
            if (c == "\\") {
                p++
                c = substr(s, p, 1)
                if (c == "u") {
                    h = substr(s, p + 1, 4)
                    if (h !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) fail("invalid \\u escape in string")
                    out = out "\\u" h
                    p += 5
                    continue
                }
                if (c == "" || index("\"\\/bfnrt", c) == 0) fail("invalid escape \\" c " in string")
                out = out "\\" c
                p++
                continue
            }
            if (c < " ") fail("raw control character inside a string (newline or tab must be escaped)")
            out = out c
            p++
        }
    }
    function parse_number(   rest) {
        rest = substr(s, p)
        if (match(rest, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/) == 0) fail("invalid number")
        p += RLENGTH
    }
    function parse_value(depth,   c, rest) {
        ws()
        if (p > n) fail("unexpected end of input")
        c = substr(s, p, 1)
        if (c == "{") { parse_object(depth); return "o" }
        if (c == "[") { parse_array(depth); return "a" }
        if (c == "\"") { last_str = parse_string(); return "s" }
        if (c == "-" || c ~ /[0-9]/) { parse_number(); return "n" }
        rest = substr(s, p, 5)
        if (substr(rest, 1, 4) == "true") { p += 4; return "l" }
        if (rest == "false") { p += 5; return "l" }
        if (substr(rest, 1, 4) == "null") { p += 4; return "l" }
        fail("unexpected character \"" c "\"")
    }
    function parse_object(depth,   key, t, c) {
        p++
        ws()
        if (peek() == "}") { p++; return }
        while (1) {
            ws()
            if (peek() != "\"") fail("expected a quoted key in object" ctx())
            key = parse_string()
            ws()
            if (peek() != ":") fail("expected \":\" after key \"" key "\"" ctx())
            p++
            if (depth == 0 && key == "entries") {
                ws()
                if (peek() != "[") fail("\"entries\" must be an array")
                in_entries = 1
                parse_array(depth + 1)
                in_entries = 0
                have_entries = 1
            } else if (in_entry && depth == 2) {
                t = parse_value(depth + 1)
                printf "F\037%d\037%s\037%s\037%s\n", entry_idx, key, t, (t == "s" ? last_str : "")
            } else {
                parse_value(depth + 1)
            }
            ws()
            c = peek()
            if (c == ",") { p++; continue }
            if (c == "}") { p++; return }
            fail("expected \",\" or \"}\" after value of \"" key "\"" ctx())
        }
    }
    function parse_array(depth,   is_entries, c) {
        is_entries = (in_entries && depth == 1)
        p++
        ws()
        if (peek() == "]") { p++; return }
        while (1) {
            ws()
            if (is_entries) {
                if (peek() != "{") fail("entries[" entry_count "] is not an object")
                entry_count++
                entry_idx = entry_count
                in_entry = 1
                printf "ENTRY\037%d\n", entry_idx
                parse_object(depth + 1)
                in_entry = 0
                printf "END\037%d\n", entry_idx
            } else {
                parse_value(depth + 1)
            }
            ws()
            c = peek()
            if (c == ",") { p++; continue }
            if (c == "]") { p++; return }
            fail("expected \",\" or \"]\" in array" ctx())
        }
    }
    function ctx() { return in_entry ? " (entry " entry_idx ")" : "" }
    { s = s $0 "\n" }
    END {
        n = length(s)
        p = 1
        entry_count = 0
        ws()
        if (p > n) fail("empty document")
        if (peek() != "{") fail("top level must be an object")
        parse_object(0)
        ws()
        if (p <= n) fail("trailing characters after the top-level object")
        if (!have_entries) fail("no \"entries\" array (see templates/test-quarantine.json.example)")
        printf "OK\037%d\n", entry_count
    }'
}

# parse_error <parse-output> → the human-readable reason the parser rejected
parse_error() {
    printf '%s\n' "$1" | sed -n 's/^ERROR //p' | head -1
}

# entry_count <parse-output> → the count from the OK record
entry_count() {
    printf '%s\n' "$1" | sed -n "s/^OK$US//p" | head -1
}

# is_blank <value> → true when the value is empty or only (JSON-escaped) whitespace
is_blank() {
    local v
    v=$(printf '%s' "$1" | sed 's/\\[tnr]/ /g; s/[[:space:]]//g')
    [ -z "$v" ]
}

# ---------------------------------------------------------------------------
# Entry validation
#
# validate_entries <parse-output> <today-day-number> emits one record per line:
#   P<US>message   a problem that fails the gate
#   S<US>test-id   an entry that expires within EXPIRING_SOON_DAYS
# Every ENTRY/END pair in the parse output is validated; nothing is skipped.
# ---------------------------------------------------------------------------

validate_entries() {
    local parsed="$1" today_days="$2"
    local tag idx key type value label test_id added expires added_days expires_days window
    local missing f seen_ids="" in_entry=0
    local v_test v_issue v_owner v_reason v_added v_expires
    local t_test t_issue t_owner t_reason t_added t_expires

    while IFS="$US" read -r tag idx key type value; do
        case "$tag" in
            ENTRY)
                in_entry=1
                v_test=""; v_issue=""; v_owner=""; v_reason=""; v_added=""; v_expires=""
                t_test=""; t_issue=""; t_owner=""; t_reason=""; t_added=""; t_expires=""
                ;;
            F)
                [ "$in_entry" -eq 1 ] || continue
                case "$key" in
                    test)    v_test="$value";    t_test="$type" ;;
                    issue)   v_issue="$value";   t_issue="$type" ;;
                    owner)   v_owner="$value";   t_owner="$type" ;;
                    reason)  v_reason="$value";  t_reason="$type" ;;
                    added)   v_added="$value";   t_added="$type" ;;
                    expires) v_expires="$value"; t_expires="$type" ;;
                esac
                ;;
            END)
                in_entry=0
                test_id="$v_test"
                if [ "$t_test" = "s" ] && ! is_blank "$test_id"; then
                    label="$test_id"
                else
                    label="entry #$idx"
                fi

                missing=""
                for f in $REQUIRED_FIELDS; do
                    eval "type=\"\$t_$f\"; value=\"\$v_$f\""
                    if [ -z "$type" ]; then
                        missing="$missing $f"
                    elif [ "$type" != "s" ]; then
                        missing="$missing $f(not-a-string)"
                    elif is_blank "$value"; then
                        missing="$missing $f(blank)"
                    fi
                done
                if [ -n "$missing" ]; then
                    printf 'P%s%s missing or blank required field(s):%s\n' "$US" "$label" "$missing"
                    continue
                fi

                case "$test_id" in
                    *'*'*|*'?'*) printf 'P%s%s test id must be exact (no wildcards)\n' "$US" "$label" ;;
                esac

                if printf '%s\n' "$seen_ids" | grep -Fxq -- "$test_id"; then
                    printf 'P%s%s is listed more than once\n' "$US" "$label"
                fi
                seen_ids="$seen_ids
$test_id"

                added="$v_added"
                expires="$v_expires"
                if ! added_days=$(iso_to_days "$added"); then
                    printf 'P%s%s has invalid added date %s (expected a real YYYY-MM-DD date)\n' "$US" "$label" "'$added'"
                    continue
                fi
                if ! expires_days=$(iso_to_days "$expires"); then
                    printf 'P%s%s has invalid expires date %s (expected a real YYYY-MM-DD date)\n' "$US" "$label" "'$expires'"
                    continue
                fi
                if [ "$added_days" -gt $((today_days + FUTURE_SLACK_DAYS)) ]; then
                    printf 'P%s%s was added in the future (%s) — the window must start when the entry lands\n' "$US" "$label" "$added"
                    continue
                fi
                if [ "$expires_days" -lt "$added_days" ]; then
                    printf 'P%s%s expires (%s) before it was added (%s)\n' "$US" "$label" "$expires" "$added"
                    continue
                fi
                window=$((expires_days - added_days))
                if [ "$window" -gt "$MAX_WINDOW_DAYS" ]; then
                    printf 'P%s%s quarantine window is %s days (maximum %s days)\n' "$US" "$label" "$window" "$MAX_WINDOW_DAYS"
                fi
                if [ "$expires_days" -lt "$today_days" ]; then
                    printf 'P%s%s expired on %s (past due — fix the test or re-triage, do not extend silently)\n' "$US" "$label" "$expires"
                elif [ $((expires_days - today_days)) -le "$EXPIRING_SOON_DAYS" ]; then
                    printf 'S%s%s\n' "$US" "$label"
                fi
                ;;
        esac
    done <<EOF
$parsed
EOF
}

# ---------------------------------------------------------------------------
# Self-test — the detector must prove it still detects before it may report
# ---------------------------------------------------------------------------

self_test() {
    local clean bad parsed problems count today
    today=$(iso_to_days 2026-06-15)

    # --- parser: clean fixture (template shape, escapes, spaces in ids, extra keys)
    clean='{
      "$comment": "fixture",
      "version": 1,
      "entries": [
        {"test": "a::b", "issue": "#1", "owner": "@x", "reason": "r \"quoted\"", "added": "2026-06-01", "expires": "2026-06-20"},
        {"test": "suite > applies promo", "issue": "#2", "owner": "@y", "reason": "s", "added": "2026-06-10", "expires": "2026-07-01", "notes": ["x", {"k": null}], "n": -1.5e3}
      ]
    }'
    parsed=$(printf '%s' "$clean" | parse_registry) || { echo "parser rejected the clean fixture: $(parse_error "$parsed")"; return 1; }
    [ "$(entry_count "$parsed")" = "2" ] || { echo "parser counted $(entry_count "$parsed") entries (expected 2)"; return 1; }
    printf '%s\n' "$parsed" | grep -Fxq -- "F${US}1${US}test${US}s${US}a::b" || { echo "field extraction failed for entry 1"; return 1; }
    printf '%s\n' "$parsed" | grep -Fxq -- "F${US}1${US}reason${US}s${US}r \\\"quoted\\\"" || { echo "escaped quote not preserved"; return 1; }
    printf '%s\n' "$parsed" | grep -Fxq -- "F${US}2${US}test${US}s${US}suite > applies promo" || { echo "id with spaces not preserved"; return 1; }
    printf '%s\n' "$parsed" | grep -Fxq -- "F${US}2${US}notes${US}a${US}" || { echo "nested array not typed as a"; return 1; }
    problems=$(validate_entries "$parsed" "$today" | grep -c "^P$US" || true)
    [ "$problems" -eq 0 ] || { echo "validator reported $problems problem(s) on the clean fixture: $(validate_entries "$parsed" "$today")"; return 1; }

    # --- parser: empty entries array is valid and counts 0
    parsed=$(printf '%s' '{"version": 1, "entries": []}' | parse_registry) || { echo "parser rejected an empty entries array"; return 1; }
    [ "$(entry_count "$parsed")" = "0" ] || { echo "empty entries array counted $(entry_count "$parsed")"; return 1; }

    # --- parser: every malformed document must be rejected
    for bad in \
        '{ "entries": [ { "test": "x" ' \
        '{"version": 1, "entries": [{"test": "a" "issue": "#1"}]}' \
        '{"version": 1, "entries": [{"test": "a", "issue": "#1",}]}' \
        '{"version": 1, "entries": [{"test": "a"}, 7]}' \
        '{"version": 1, "entries": [{"test": "a"}, "b"]}' \
        '{"version": 1, "entries": {}}' \
        '{"version": 1, "entries": [{test: "a"}]}' \
        '{"version": 1, "entries": [{"test": "a\q"}]}' \
        '{"version": 1, "entries": []} x' \
        '{"version": 01, "entries": []}' \
        '["entries"]' \
        '{"version": 1}' \
        ''; do
        if parsed=$(printf '%s' "$bad" | parse_registry 2>/dev/null); then
            echo "parser accepted malformed JSON: $bad"
            return 1
        fi
    done
    parsed=$(printf '{"version": 1, "entries": [{"test": "tab\there"}]}' | parse_registry 2>/dev/null) && { echo "parser accepted a raw tab inside a string"; return 1; }

    # --- validator: the rejecting fixture must trip on every rule
    bad='{"version": 1, "entries": [
      {"test": "ok::one", "issue": "#1", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "suite applies promo", "issue": "#2", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "applies", "issue": "#3", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "dup::id", "issue": "#4", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "dup::id", "issue": "#5", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"foo": "bar"},
      {"test": "blank::owner", "issue": "#6", "owner": " \t", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "num::issue", "issue": 7, "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "wild::*", "issue": "#8", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-06-20"},
      {"test": "bad::date", "issue": "#9", "owner": "@a", "reason": "r", "added": "2026-02-30", "expires": "2026-03-10"},
      {"test": "future::added", "issue": "#10", "owner": "@a", "reason": "r", "added": "2099-01-01", "expires": "2099-01-20"},
      {"test": "long::window", "issue": "#11", "owner": "@a", "reason": "r", "added": "2026-06-01", "expires": "2026-07-15"},
      {"test": "past::due", "issue": "#12", "owner": "@a", "reason": "r", "added": "2026-05-01", "expires": "2026-05-20"},
      {"test": "backwards", "issue": "#13", "owner": "@a", "reason": "r", "added": "2026-06-10", "expires": "2026-06-01"}
    ]}'
    parsed=$(printf '%s' "$bad" | parse_registry) || { echo "parser rejected the validator fixture: $(parse_error "$parsed")"; return 1; }
    [ "$(entry_count "$parsed")" = "14" ] || { echo "validator fixture counted $(entry_count "$parsed") entries (expected 14)"; return 1; }
    problems=$(validate_entries "$parsed" "$today")
    count=$(printf '%s\n' "$problems" | grep -c "^P$US" || true)
    [ "$count" -eq 10 ] || { echo "validator tripped $count time(s) on the rejecting fixture (expected 10): $(printf '%s' "$problems" | tr '\n' ';')"; return 1; }
    for f in "dup::id is listed more than once" "entry #6 missing" "blank::owner missing or blank required field(s): owner(blank)" \
             "num::issue missing or blank required field(s): issue(not-a-string)" "wild::\* test id must be exact" \
             "bad::date has invalid added date '2026-02-30'" "future::added was added in the future" \
             "long::window quarantine window is 44 days" "past::due expired on 2026-05-20" "backwards expires (2026-06-01) before"; do
        printf '%s\n' "$problems" | grep -q -- "$f" || { echo "validator did not report: $f"; return 1; }
    done
    printf '%s\n' "$problems" | grep -q "applies is listed more than once" && { echo "duplicate check collided on a substring of an id with spaces"; return 1; }

    # --- dates
    [ "$(( $(iso_to_days 2026-01-20) - $(iso_to_days 2026-01-01) ))" -eq 19 ] || { echo "day arithmetic failed"; return 1; }
    [ "$(iso_to_days 2026-02-28)" -eq "$(( $(iso_to_days 2026-03-01) - 1 ))" ] || { echo "month boundary arithmetic failed"; return 1; }
    iso_to_days 2024-02-29 >/dev/null || { echo "iso_to_days rejected a leap day"; return 1; }
    iso_to_days 2023-02-29 >/dev/null 2>&1 && { echo "iso_to_days accepted Feb 29 in a non-leap year"; return 1; }
    iso_to_days 2100-02-29 >/dev/null 2>&1 && { echo "iso_to_days accepted Feb 29 in a 100-year non-leap year"; return 1; }
    iso_to_days 2027-04-31 >/dev/null 2>&1 && { echo "iso_to_days accepted April 31"; return 1; }
    iso_to_days 2026-13-01 >/dev/null 2>&1 && { echo "iso_to_days accepted month 13"; return 1; }
    iso_to_days "not-a-date" >/dev/null 2>&1 && { echo "iso_to_days accepted garbage"; return 1; }
    return 0
}

if ! self_test_msg=$(self_test); then
    echo "FAIL $CHECK_NAME self-test failed (detector rot, refusing to report): $self_test_msg"
    exit 1
fi

# ---------------------------------------------------------------------------
# Locate the registry
# ---------------------------------------------------------------------------

DECLARED=""
if [ -f "$PROJECT_ROOT/.standards.yml" ]; then
    # Prints the declared path, or __EMPTY__ when the key is present with no value.
    DECLARED=$(awk '
        /^tests:/ { inblk = 1; next }
        inblk && /^[^[:space:]#]/ { exit }
        inblk && /^[[:space:]]+quarantine_file:/ {
            sub(/^[[:space:]]*quarantine_file:[[:space:]]*/, "")
            sub(/[[:space:]]+#.*$/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            if ($0 == "" || $0 == "~" || $0 == "null") print "__EMPTY__"; else print
            exit
        }' "$PROJECT_ROOT/.standards.yml" 2>/dev/null)
fi

if [ "$DECLARED" = "__EMPTY__" ]; then
    echo "FAIL $CHECK_NAME .standards.yml declares tests.quarantine_file with no value — set a path or remove the key (failing closed)"
    exit 1
fi

REGISTRY=""
REGISTRY_LABEL=""
if [ -n "$DECLARED" ]; then
    REGISTRY_LABEL="$DECLARED"
    if [ ! -f "$PROJECT_ROOT/$DECLARED" ]; then
        echo "FAIL $CHECK_NAME .standards.yml declares tests.quarantine_file: $DECLARED but the file does not exist (failing closed)"
        exit 1
    fi
    REGISTRY="$PROJECT_ROOT/$DECLARED"
else
    for candidate in $DEFAULT_LOCATIONS; do
        if [ -f "$PROJECT_ROOT/$candidate" ]; then
            REGISTRY="$PROJECT_ROOT/$candidate"
            REGISTRY_LABEL="$candidate"
            break
        fi
    done
fi

if [ -z "$REGISTRY" ]; then
    echo "PASS $CHECK_NAME No quarantine registry (none declared in .standards.yml, no test-quarantine.json) — nothing quarantined"
    exit 0
fi

if [ ! -r "$REGISTRY" ] || [ ! -s "$REGISTRY" ]; then
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL is empty or unreadable — cannot pass (failing closed)"
    exit 1
fi

# ---------------------------------------------------------------------------
# Parse and validate
# ---------------------------------------------------------------------------

if ! PARSED=$(parse_registry < "$REGISTRY" 2>/dev/null); then
    reason=$(parse_error "$PARSED")
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL is not valid JSON: ${reason:-parse error} — failing closed"
    exit 1
fi
ENTRIES=$(entry_count "$PARSED")

if grep -qE '"(coverage|coverage_minimum|min_coverage|threshold)"[[:space:]]*:' "$REGISTRY"; then
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL carries a coverage override — quarantine may never lower a coverage threshold"
    exit 1
fi

TODAY_DAYS=$(iso_to_days "$(date -u +%Y-%m-%d)")
RESULTS=$(validate_entries "$PARSED" "$TODAY_DAYS")
PROBLEM_COUNT=$(printf '%s\n' "$RESULTS" | grep -c "^P$US" || true)
EXPIRING_SOON=$(printf '%s\n' "$RESULTS" | grep -c "^S$US" || true)

if [ "$PROBLEM_COUNT" -gt 0 ]; then
    PROBLEMS=$(printf '%s\n' "$RESULTS" | sed -n "s/^P$US//p" | head -4 | tr '\n' ';' | sed 's/;$//; s/;/; /g')
    more=""
    if [ "$PROBLEM_COUNT" -gt 4 ]; then more=" (+$((PROBLEM_COUNT - 4)) more)"; fi
    echo "FAIL $CHECK_NAME $PROBLEM_COUNT problem(s) in $REGISTRY_LABEL: $PROBLEMS$more"
    exit 1
fi

if [ "$EXPIRING_SOON" -gt 0 ]; then
    echo "WARN $CHECK_NAME $ENTRIES quarantined test(s) in $REGISTRY_LABEL; $EXPIRING_SOON expire within $EXPIRING_SOON_DAYS days"
    exit 2
fi

if [ "$ENTRIES" -eq 0 ]; then
    echo "PASS $CHECK_NAME $REGISTRY_LABEL is valid and lists 0 quarantined test(s) — nothing quarantined"
    exit 0
fi

echo "PASS $CHECK_NAME $ENTRIES quarantined test(s) in $REGISTRY_LABEL, all fields present, none expired, windows <= $MAX_WINDOW_DAYS days"
exit 0
