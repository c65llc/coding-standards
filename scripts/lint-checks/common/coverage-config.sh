#!/bin/bash
# Check: verify CI has coverage gates configured, and that any scoped floors
#        declared in .standards.yml coverage.scopes are coherent (proc-05 § 6)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# coverage.scopes rules enforced here:
#   - coverage.minimum / coverage.domain, when present, are integers in 0..100
#   - every scope has a path and an integer minimum in 0..100
#   - layer, when present, is one of the documented names
#     (domain, core, application, infrastructure, inherited, native, generated)
#   - a scope with layer domain/core must have minimum 100
#   - a scope whose minimum is below the overall minimum must state a reason
#     (this is how inherited / native / generated code is carved out auditable)
#   - scope paths are unique
#   - the overall minimum is resolved before any scope is judged, wherever it
#     appears in the block
#
# Gate rules (proc-05 § 7): the parser AND the validator self-test on every
# run — a built-in rejecting fixture must trip every rule and a clean fixture
# must pass — and the check FAILs rather than reporting a clean result if
# either has rotted.

PROJECT_ROOT="${1:-.}"

CHECK_NAME="coverage-config"
DEFAULT_MINIMUM=95

# ---------------------------------------------------------------------------
# .standards.yml coverage block parser
# Emits records separated by ASCII unit separator (\037):
#   MIN<US>value
#   DOMAIN<US>value
#   SCOPE<US>path<US>layer<US>minimum<US>reason
# ---------------------------------------------------------------------------

parse_coverage_block() {
    awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function unquote(s) {
        if (s ~ /^".*"$/ || s ~ /^'"'"'.*'"'"'$/) { s = substr(s, 2, length(s) - 2) }
        return s
    }
    function strip_comment(s) { sub(/[ \t]+#.*$/, "", s); return s }
    function flush() {
        if (have) {
            printf "SCOPE\037%s\037%s\037%s\037%s\n", path, layer, min, reason
        }
        have = 0; path = ""; layer = ""; min = ""; reason = ""
    }
    function setkv(s,   k, v) {
        s = trim(s)
        if (s == "") return
        k = s; sub(/[ \t]*:.*$/, "", k)
        v = s; sub(/^[^:]*:[ \t]*/, "", v)
        v = unquote(trim(strip_comment(v)))
        if (k == "path") path = v
        else if (k == "layer") layer = v
        else if (k == "minimum") min = v
        else if (k == "reason") reason = v
    }
    /^coverage:/ { inblk = 1; next }
    !inblk { next }
    /^[^ \t#]/ { exit }
    /^[ \t]*(#|$)/ { next }
    {
        match($0, /^[ ]*/); ind = RLENGTH
        if (inscopes) {
            if ($0 ~ /^[ ]*-([ ]|$)/ && ind >= sind) {
                flush(); have = 1
                s = $0; sub(/^[ ]*-[ ]*/, "", s)
                setkv(s); next
            }
            if (ind > sind) { setkv($0); next }
            inscopes = 0; flush()
        }
        if ($0 ~ /^[ ]+scopes:[ \t]*(#.*)?$/) { inscopes = 1; sind = ind; next }
        if ($0 ~ /^[ ]+minimum:/) {
            v = $0; sub(/^[ ]*minimum:[ \t]*/, "", v)
            print "MIN\037" unquote(trim(strip_comment(v))); next
        }
        if ($0 ~ /^[ ]+domain:/) {
            v = $0; sub(/^[ ]*domain:[ \t]*/, "", v)
            print "DOMAIN\037" unquote(trim(strip_comment(v))); next
        }
    }
    END { flush() }
    ' "$1"
}

# is_pct <value> → true for an integer 0..100 (bounded before any shell
# arithmetic, so an oversized digit string can never error out of a comparison)
is_pct() {
    case "$1" in
        [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) [ "$1" -le 100 ] ;;
        *) return 1 ;;
    esac
}

KNOWN_LAYERS="domain core application infrastructure inherited native generated"

is_known_layer() {
    local l
    for l in $KNOWN_LAYERS; do
        [ "$1" = "$l" ] && return 0
    done
    return 1
}

US="$(printf '\037')"

# ---------------------------------------------------------------------------
# Validation
#
# validate_coverage_records <parsed> emits one record per line:
#   MIN<US>value   the resolved overall minimum (declared or default)
#   N<US>count     number of scopes seen
#   P<US>message   a problem that fails the gate
# The overall minimum is resolved in a first pass so a `minimum:` declared
# after `scopes:` still governs every scope.
# ---------------------------------------------------------------------------

validate_coverage_records() {
    local parsed="$1"
    local tag f1 f2 f3 f4 declared_min overall domain
    local count=0 seen_paths="" s_path s_layer s_min s_reason label

    declared_min=$(printf '%s\n' "$parsed" | sed -n "s/^MIN$US//p" | tail -1)
    domain=$(printf '%s\n' "$parsed" | sed -n "s/^DOMAIN$US//p" | tail -1)
    overall="$DEFAULT_MINIMUM"
    if [ -n "$declared_min" ]; then
        if is_pct "$declared_min"; then
            overall="$declared_min"
        else
            printf 'P%scoverage.minimum is %s (integer 0-100 required)\n' "$US" "'$declared_min'"
        fi
    fi
    if [ -n "$domain" ] && ! is_pct "$domain"; then
        printf 'P%scoverage.domain is %s (integer 0-100 required)\n' "$US" "'$domain'"
    fi
    printf 'MIN%s%s\n' "$US" "$overall"

    while IFS="$US" read -r tag f1 f2 f3 f4; do
        [ "$tag" = "SCOPE" ] || continue
        count=$((count + 1))
        s_path="$f1"; s_layer="$f2"; s_min="$f3"; s_reason="$f4"
        label="${s_path:-scope #$count}"
        if [ -z "$s_path" ]; then
            printf 'P%s%s has no path\n' "$US" "$label"
            continue
        fi
        if printf '%s\n' "$seen_paths" | grep -Fxq -- "$s_path"; then
            printf 'P%s%s is declared more than once\n' "$US" "$label"
        fi
        seen_paths="$seen_paths
$s_path"
        if ! is_pct "$s_min"; then
            printf 'P%s%s has invalid minimum %s (integer 0-100 required)\n' "$US" "$label" "'${s_min:-<missing>}'"
            continue
        fi
        if [ -n "$s_layer" ] && ! is_known_layer "$s_layer"; then
            printf 'P%s%s has unknown layer %s (expected one of: %s)\n' "$US" "$label" "'$s_layer'" "$KNOWN_LAYERS"
            continue
        fi
        case "$s_layer" in
            domain|core)
                if [ "$s_min" -ne 100 ]; then
                    printf 'P%s%s is a %s scope with floor %s%% (domain/core must stay at 100%%)\n' "$US" "$label" "$s_layer" "$s_min"
                fi
                ;;
        esac
        if [ "$s_min" -lt "$overall" ] && [ -z "$s_reason" ]; then
            printf 'P%s%s lowers the floor to %s%% without a stated reason\n' "$US" "$label" "$s_min"
        fi
    done <<EOF
$parsed
EOF
    printf 'N%s%s\n' "$US" "$count"
}

# ---------------------------------------------------------------------------
# Self-test: prove the parser parses and the validator rejects before trusting
# either on the project
# ---------------------------------------------------------------------------

self_test() {
    local fixture out min_count scope_count rec results problems f
    fixture="$(mktemp "${TMPDIR:-/tmp}/coverage-config-selftest.XXXXXX")" || return 1

    # --- clean fixture: trailing comments, quoted values, minimum after scopes
    cat > "$fixture" <<'YML'
version: 1
coverage:
  domain: 100
  scopes:   # per-module floors
    - path: src/domain
      layer: domain   # must stay at 100
      minimum: 100
    - path: "vendor/engine"
      layer: inherited
      minimum: 0
      reason: inherited engine, measured upstream
    - path: src/app
      minimum: 90
  minimum: 90   # overall, declared after the scopes on purpose
architecture: clean
YML
    out=$(parse_coverage_block "$fixture")
    min_count=$(printf '%s\n' "$out" | grep -c "^MIN${US}90\$" || true)
    scope_count=$(printf '%s\n' "$out" | grep -c '^SCOPE' || true)
    [ "$min_count" -eq 1 ] || { rm -f "$fixture"; echo "overall minimum not parsed (got $min_count match)"; return 1; }
    [ "$scope_count" -eq 3 ] || { rm -f "$fixture"; echo "expected 3 scopes, parsed $scope_count (scopes: with a trailing comment?)"; return 1; }
    rec=$(printf '%s\n' "$out" | grep '^SCOPE' | sed -n '2p')
    IFS="$US" read -r _ s_path s_layer s_min s_reason <<EOF
$rec
EOF
    [ "$s_path" = "vendor/engine" ] || { rm -f "$fixture"; echo "quoted path not unquoted ('$s_path')"; return 1; }
    [ "$s_layer" = "inherited" ] || { rm -f "$fixture"; echo "layer not parsed ('$s_layer')"; return 1; }
    [ "$s_min" = "0" ] || { rm -f "$fixture"; echo "minimum not parsed ('$s_min')"; return 1; }
    [ "$s_reason" = "inherited engine, measured upstream" ] || { rm -f "$fixture"; echo "reason not parsed ('$s_reason')"; return 1; }
    results=$(validate_coverage_records "$out")
    problems=$(printf '%s\n' "$results" | grep -c "^P$US" || true)
    [ "$problems" -eq 0 ] || { rm -f "$fixture"; echo "validator reported $problems problem(s) on the clean fixture: $(printf '%s' "$results" | tr '\n' ';')"; return 1; }
    printf '%s\n' "$results" | grep -Fxq -- "MIN${US}90" || { rm -f "$fixture"; echo "validator did not resolve the late-declared minimum to 90"; return 1; }
    printf '%s\n' "$results" | grep -Fxq -- "N${US}3" || { rm -f "$fixture"; echo "validator did not count 3 scopes"; return 1; }

    # --- rejecting fixture: every rule must trip exactly once
    cat > "$fixture" <<'YML'
version: 1
coverage:
  minimum: 95
  domain: abc
  scopes:
    - path: src/domain
      layer: domain
      minimum: 90
      reason: a reason never exempts a domain scope
    - path: native/metal
      layer: native
      minimum: 0
    - path: src/app
      layer: application
      minimum: 95
    - path: src/app
      layer: application
      minimum: 95
    - path: src/typo
      layer: domian
      minimum: 0
      reason: typo must not bypass the domain rule
    - path: src/huge
      minimum: 99999999999999999999999999
    - path: src/over
      minimum: 101
    - layer: application
      minimum: 95
YML
    out=$(parse_coverage_block "$fixture")
    rm -f "$fixture"
    results=$(validate_coverage_records "$out")
    problems=$(printf '%s\n' "$results" | grep -c "^P$US" || true)
    [ "$problems" -eq 8 ] || { echo "validator tripped $problems time(s) on the rejecting fixture (expected 8): $(printf '%s' "$results" | tr '\n' ';')"; return 1; }
    for f in "coverage.domain is 'abc'" "src/domain is a domain scope with floor 90%" "native/metal lowers the floor to 0% without a stated reason" \
             "src/app is declared more than once" "src/typo has unknown layer 'domian'" "src/huge has invalid minimum" \
             "src/over has invalid minimum '101'" "scope #8 has no path"; do
        printf '%s\n' "$results" | grep -qF -- "$f" || { echo "validator did not report: $f"; return 1; }
    done
    return 0
}

if ! self_test_msg=$(self_test); then
    echo "FAIL $CHECK_NAME self-test failed (detector rot, refusing to report): $self_test_msg"
    exit 1
fi

# ---------------------------------------------------------------------------
# Read and validate .standards.yml coverage settings
# ---------------------------------------------------------------------------

STD_MIN=""
SCOPE_COUNT=0
SCOPE_PROBLEM_COUNT=0
RESULTS=""

if [ -f "$PROJECT_ROOT/.standards.yml" ] && grep -qE '^coverage:' "$PROJECT_ROOT/.standards.yml" 2>/dev/null; then
    PARSED=$(parse_coverage_block "$PROJECT_ROOT/.standards.yml")
    RESULTS=$(validate_coverage_records "$PARSED")
    SCOPE_COUNT=$(printf '%s\n' "$RESULTS" | sed -n "s/^N$US//p" | tail -1)
    SCOPE_PROBLEM_COUNT=$(printf '%s\n' "$RESULTS" | grep -c "^P$US" || true)
    # Report the declared minimum only when one was declared (the validator
    # falls back to the default so scopes can still be judged).
    if printf '%s\n' "$PARSED" | grep -q "^MIN$US"; then
        STD_MIN=$(printf '%s\n' "$RESULTS" | sed -n "s/^MIN$US//p" | tail -1)
    fi
fi

if [ "${SCOPE_PROBLEM_COUNT:-0}" -gt 0 ]; then
    SCOPE_PROBLEMS=$(printf '%s\n' "$RESULTS" | sed -n "s/^P$US//p" | head -4 | tr '\n' ';' | sed 's/;$//; s/;/; /g')
    more=""
    if [ "$SCOPE_PROBLEM_COUNT" -gt 4 ]; then more=" (+$((SCOPE_PROBLEM_COUNT - 4)) more)"; fi
    echo "FAIL $CHECK_NAME coverage block in .standards.yml has $SCOPE_PROBLEM_COUNT problem(s): $SCOPE_PROBLEMS$more"
    exit 1
fi

SCOPES_NOTE=""
if [ "$SCOPE_COUNT" -gt 0 ]; then
    SCOPES_NOTE="$SCOPE_COUNT scoped floor(s)"
fi

# ---------------------------------------------------------------------------
# Detect a coverage gate in CI / tool configuration
# ---------------------------------------------------------------------------

FOUND=""

# Check GitHub Actions workflows for coverage mentions
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    workflow_coverage=$(grep -rlE 'coverage|codecov|coveralls' "$PROJECT_ROOT/.github/workflows/" 2>/dev/null || true)
    if [ -n "$workflow_coverage" ]; then
        workflow_name=$(basename "$(echo "$workflow_coverage" | head -1)")
        FOUND="Coverage step found in GitHub Actions ($workflow_name)"
    fi
fi

# Check pytest coverage config in pyproject.toml
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/pyproject.toml" ]; then
    if grep -qE '\[tool\.pytest|coverage\]|\[tool\.coverage' "$PROJECT_ROOT/pyproject.toml" 2>/dev/null; then
        FOUND="Coverage config found in pyproject.toml"
    fi
fi

# Check pytest.ini for coverage
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/pytest.ini" ]; then
    if grep -qE '(addopts|cov|coverage)' "$PROJECT_ROOT/pytest.ini" 2>/dev/null; then
        FOUND="Coverage config found in pytest.ini"
    fi
fi

# Check setup.cfg for coverage
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/setup.cfg" ]; then
    if grep -qE '\[coverage|cov_min|fail_under' "$PROJECT_ROOT/setup.cfg" 2>/dev/null; then
        FOUND="Coverage config found in setup.cfg"
    fi
fi

# Check jest.config for coverage thresholds
if [ -z "$FOUND" ]; then
    for jest_cfg in jest.config.js jest.config.ts jest.config.mjs jest.config.cjs jest.config.json; do
        if [ -f "$PROJECT_ROOT/$jest_cfg" ]; then
            if grep -qE 'coverageThreshold|collectCoverage' "$PROJECT_ROOT/$jest_cfg" 2>/dev/null; then
                FOUND="Coverage threshold found in $jest_cfg"
                break
            fi
        fi
    done
fi

# Check package.json jest config
if [ -z "$FOUND" ] && [ -f "$PROJECT_ROOT/package.json" ]; then
    if grep -qE 'coverageThreshold|collectCoverage' "$PROJECT_ROOT/package.json" 2>/dev/null; then
        FOUND="Coverage config found in package.json (jest)"
    fi
fi

# Check .nycrc or nyc config in package.json
if [ -z "$FOUND" ]; then
    for nyc_cfg in .nycrc .nycrc.json; do
        if [ -f "$PROJECT_ROOT/$nyc_cfg" ]; then
            FOUND="Coverage config found in $nyc_cfg"
            break
        fi
    done
fi

# Check codecov.yml
if [ -z "$FOUND" ]; then
    for codecov_cfg in codecov.yml .codecov.yml codecov.yaml; do
        if [ -f "$PROJECT_ROOT/$codecov_cfg" ]; then
            FOUND="Coverage config found in $codecov_cfg"
            break
        fi
    done
fi

# Fall back to .standards.yml coverage settings
if [ -z "$FOUND" ]; then
    if [ -n "$STD_MIN" ] && [ -n "$SCOPES_NOTE" ]; then
        FOUND="Coverage gate found in .standards.yml (minimum: ${STD_MIN}%, $SCOPES_NOTE)"
    elif [ -n "$STD_MIN" ]; then
        FOUND="Coverage gate found in .standards.yml (minimum: ${STD_MIN}%)"
    elif [ -n "$SCOPES_NOTE" ]; then
        FOUND="Coverage gate found in .standards.yml ($SCOPES_NOTE)"
    fi
elif [ -n "$SCOPES_NOTE" ]; then
    FOUND="$FOUND; $SCOPES_NOTE in .standards.yml"
fi

if [ -n "$FOUND" ]; then
    echo "PASS $CHECK_NAME $FOUND"
    exit 0
else
    echo "FAIL $CHECK_NAME No coverage configuration found in CI workflows, test config, or .standards.yml"
    exit 1
fi
