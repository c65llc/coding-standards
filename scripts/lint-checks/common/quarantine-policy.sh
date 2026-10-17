#!/bin/bash
# Check: flaky-test quarantine registry is bounded and current (proc-05 § 2)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# Validates the quarantine registry (templates/test-quarantine.json.example):
#   - every entry has test, issue, owner, reason, added, expires
#   - `test` is an exact id (no wildcards), unique within the registry
#   - `added`/`expires` are ISO dates, expires >= added
#   - the window (expires - added) is at most 30 days
#   - no entry is past due (expires < today)
#   - the registry carries no coverage overrides (quarantine never lowers a gate)
#
# Gate rules (proc-05 § 7, scripts/lint-checks/README.md "Writing a gate"):
#   - self-tests the parser on every run and FAILs if the detector has rotted
#   - fails closed when a declared registry is missing, empty, or unparseable
#   - depends only on bash 3.2 + POSIX awk/sed/tr so results match on every host

PROJECT_ROOT="${1:-.}"

CHECK_NAME="quarantine-policy"
MAX_WINDOW_DAYS=30
EXPIRING_SOON_DAYS=3
REQUIRED_FIELDS="test issue owner reason added expires"
DEFAULT_LOCATIONS="test-quarantine.json .github/ci/test-quarantine.json ci/test-quarantine.json tests/test-quarantine.json"

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

# iso_to_days YYYY-MM-DD → day number, or non-zero exit on a malformed date
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
    if [ "$((10#$d))" -lt 1 ] || [ "$((10#$d))" -gt 31 ]; then return 1; fi
    days_from_civil "$y" "$m" "$d"
}

# ---------------------------------------------------------------------------
# Registry parsing — flat JSON objects with string values, one entry per line
# ---------------------------------------------------------------------------

# split_entries <json-text> → one object per output line
split_entries() {
    printf '%s' "$1" | tr -d '\n\r' | awk '{ gsub(/\}[ \t]*,[ \t]*\{/, "}\n{"); print }'
}

# field <line> <key> → the string value of "key" on that line (empty if absent)
field() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# is_entry <line> → true when the line carries at least one entry key
is_entry() {
    printf '%s' "$1" | grep -qE '"(test|issue|owner|reason|added|expires)"[[:space:]]*:'
}

# braces_balanced <json-text> → true when {} and [] balance outside strings
braces_balanced() {
    local stripped open close
    stripped=$(printf '%s' "$1" | tr -d '\n\r' | sed 's/"[^"]*"//g')
    open=$(printf '%s' "$stripped" | tr -cd '{' | wc -c | tr -d ' ')
    close=$(printf '%s' "$stripped" | tr -cd '}' | wc -c | tr -d ' ')
    [ "$open" -eq "$close" ] || return 1
    open=$(printf '%s' "$stripped" | tr -cd '[' | wc -c | tr -d ' ')
    close=$(printf '%s' "$stripped" | tr -cd ']' | wc -c | tr -d ' ')
    [ "$open" -eq "$close" ]
}

# ---------------------------------------------------------------------------
# Self-test — the detector must prove it still detects before it may report
# ---------------------------------------------------------------------------

self_test() {
    local fixture lines count first second d1 d2
    fixture='{"version": 1, "entries": [
      {"test": "a::b", "issue": "#1", "owner": "@x", "reason": "r", "added": "2026-01-01", "expires": "2026-01-20"},
      {"test": "c::d", "issue": "#2", "owner": "@y", "reason": "s", "added": "2026-02-10", "expires": "2026-03-01"}
    ]}'
    lines=$(split_entries "$fixture")
    count=0
    while IFS= read -r line; do
        is_entry "$line" && count=$((count + 1))
    done <<EOF
$lines
EOF
    [ "$count" -eq 2 ] || { echo "entry split returned $count (expected 2)"; return 1; }
    first=$(printf '%s\n' "$lines" | head -1)
    second=$(printf '%s\n' "$lines" | sed -n '2p')
    [ "$(field "$first" test)" = "a::b" ] || { echo "field extraction returned '$(field "$first" test)'"; return 1; }
    [ "$(field "$second" owner)" = "@y" ] || { echo "field extraction on 2nd entry failed"; return 1; }
    [ -z "$(field "$first" nope)" ] || { echo "absent field returned a value"; return 1; }
    d1=$(iso_to_days 2026-01-01) || { echo "iso_to_days rejected a valid date"; return 1; }
    d2=$(iso_to_days 2026-01-20) || { echo "iso_to_days rejected a valid date"; return 1; }
    [ $((d2 - d1)) -eq 19 ] || { echo "day arithmetic returned $((d2 - d1)) (expected 19)"; return 1; }
    [ "$(iso_to_days 2026-02-28)" -eq "$(( $(iso_to_days 2026-03-01) - 1 ))" ] || { echo "month boundary arithmetic failed"; return 1; }
    iso_to_days 2026-13-01 >/dev/null 2>&1 && { echo "iso_to_days accepted month 13"; return 1; }
    iso_to_days "not-a-date" >/dev/null 2>&1 && { echo "iso_to_days accepted garbage"; return 1; }
    braces_balanced "$fixture" || { echo "brace check rejected balanced fixture"; return 1; }
    braces_balanced '{ "entries": [ { "test": "x" ' && { echo "brace check accepted truncated JSON"; return 1; }
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
    DECLARED=$(awk '
        /^tests:/ { inblk = 1; next }
        inblk && /^[^[:space:]#]/ { exit }
        inblk && /^[[:space:]]+quarantine_file:/ {
            sub(/^[[:space:]]*quarantine_file:[[:space:]]*/, "")
            sub(/[[:space:]]+#.*$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print; exit
        }' "$PROJECT_ROOT/.standards.yml" 2>/dev/null)
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

if [ ! -s "$REGISTRY" ]; then
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL is empty — an unreadable registry cannot pass (failing closed)"
    exit 1
fi

CONTENT=$(cat "$REGISTRY")

if ! braces_balanced "$CONTENT"; then
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL is not well-formed JSON (unbalanced braces) — failing closed"
    exit 1
fi

if ! printf '%s' "$CONTENT" | grep -q '"entries"[[:space:]]*:'; then
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL has no \"entries\" array (see templates/test-quarantine.json.example)"
    exit 1
fi

if printf '%s' "$CONTENT" | grep -qE '"(coverage|coverage_minimum|min_coverage|threshold)"[[:space:]]*:'; then
    echo "FAIL $CHECK_NAME Quarantine registry $REGISTRY_LABEL carries a coverage override — quarantine may never lower a coverage threshold"
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate entries
# ---------------------------------------------------------------------------

TODAY_DAYS=$(iso_to_days "$(date -u +%Y-%m-%d)")
ENTRIES=0
PROBLEMS=""
PROBLEM_COUNT=0
EXPIRING_SOON=0
SEEN_IDS=""

add_problem() {
    PROBLEM_COUNT=$((PROBLEM_COUNT + 1))
    if [ "$PROBLEM_COUNT" -le 4 ]; then
        if [ -n "$PROBLEMS" ]; then PROBLEMS="$PROBLEMS; $1"; else PROBLEMS="$1"; fi
    fi
}

LINES=$(split_entries "$CONTENT")
while IFS= read -r line; do
    is_entry "$line" || continue
    ENTRIES=$((ENTRIES + 1))

    test_id=$(field "$line" test)
    label="${test_id:-entry #$ENTRIES}"

    missing=""
    for f in $REQUIRED_FIELDS; do
        if [ -z "$(field "$line" "$f")" ]; then
            missing="$missing $f"
        fi
    done
    if [ -n "$missing" ]; then
        add_problem "$label missing required field(s):${missing}"
        continue
    fi

    case "$test_id" in
        *'*'*|*'?'*) add_problem "$label test id must be exact (no wildcards)" ;;
    esac

    case " $SEEN_IDS " in
        *" $test_id "*) add_problem "$label is listed more than once" ;;
    esac
    SEEN_IDS="$SEEN_IDS $test_id"

    added=$(field "$line" added)
    expires=$(field "$line" expires)
    if ! added_days=$(iso_to_days "$added"); then
        add_problem "$label has invalid added date '$added' (expected YYYY-MM-DD)"
        continue
    fi
    if ! expires_days=$(iso_to_days "$expires"); then
        add_problem "$label has invalid expires date '$expires' (expected YYYY-MM-DD)"
        continue
    fi
    if [ "$expires_days" -lt "$added_days" ]; then
        add_problem "$label expires ($expires) before it was added ($added)"
        continue
    fi
    window=$((expires_days - added_days))
    if [ "$window" -gt "$MAX_WINDOW_DAYS" ]; then
        add_problem "$label quarantine window is $window days (maximum $MAX_WINDOW_DAYS days)"
    fi
    if [ "$expires_days" -lt "$TODAY_DAYS" ]; then
        add_problem "$label expired on $expires (past due — fix the test or re-triage, do not extend silently)"
    elif [ $((expires_days - TODAY_DAYS)) -le "$EXPIRING_SOON_DAYS" ]; then
        EXPIRING_SOON=$((EXPIRING_SOON + 1))
    fi
done <<EOF
$LINES
EOF

if [ "$PROBLEM_COUNT" -gt 0 ]; then
    more=""
    if [ "$PROBLEM_COUNT" -gt 4 ]; then more=" (+$((PROBLEM_COUNT - 4)) more)"; fi
    echo "FAIL $CHECK_NAME $PROBLEM_COUNT problem(s) in $REGISTRY_LABEL: $PROBLEMS$more"
    exit 1
fi

if [ "$EXPIRING_SOON" -gt 0 ]; then
    echo "WARN $CHECK_NAME $ENTRIES quarantined test(s) in $REGISTRY_LABEL; $EXPIRING_SOON expire within $EXPIRING_SOON_DAYS days"
    exit 2
fi

echo "PASS $CHECK_NAME $ENTRIES quarantined test(s) in $REGISTRY_LABEL, all fields present, none expired, windows <= $MAX_WINDOW_DAYS days"
exit 0
