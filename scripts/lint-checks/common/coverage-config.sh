#!/bin/bash
# Check: verify CI has coverage gates configured, and that any scoped floors
#        declared in .standards.yml coverage.scopes are coherent (proc-05 § 6)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# coverage.scopes rules enforced here:
#   - every scope has a path and an integer minimum in 0..100
#   - a scope with layer domain/core must have minimum 100
#   - a scope whose minimum is below the overall minimum must state a reason
#     (this is how inherited / native / generated code is carved out auditable)
#   - scope paths are unique
#
# Gate rules (proc-05 § 7): the scope parser self-tests on every run and the
# check FAILs rather than reporting a clean result if the parser has rotted.

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
        if ($0 ~ /^[ ]+scopes:[ \t]*$/) { inscopes = 1; sind = ind; next }
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

is_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# Self-test: prove the parser still parses before trusting its output
# ---------------------------------------------------------------------------

self_test() {
    local fixture out min_count scope_count rec
    fixture="$(mktemp "${TMPDIR:-/tmp}/coverage-config-selftest.XXXXXX")" || return 1
    cat > "$fixture" <<'YML'
version: 1
coverage:
  minimum: 95   # overall
  domain: 100
  scopes:
    - path: src/domain
      layer: domain
      minimum: 100
    - path: "vendor/engine"
      layer: inherited
      minimum: 0
      reason: inherited engine, measured upstream
architecture: clean
YML
    out=$(parse_coverage_block "$fixture")
    rm -f "$fixture"
    min_count=$(printf '%s\n' "$out" | grep -c "^MIN$(printf '\037')95\$" || true)
    scope_count=$(printf '%s\n' "$out" | grep -c '^SCOPE' || true)
    [ "$min_count" -eq 1 ] || { echo "overall minimum not parsed (got $min_count match)"; return 1; }
    [ "$scope_count" -eq 2 ] || { echo "expected 2 scopes, parsed $scope_count"; return 1; }
    rec=$(printf '%s\n' "$out" | grep '^SCOPE' | sed -n '2p')
    IFS="$(printf '\037')" read -r _ s_path s_layer s_min s_reason <<EOF
$rec
EOF
    [ "$s_path" = "vendor/engine" ] || { echo "quoted path not unquoted ('$s_path')"; return 1; }
    [ "$s_layer" = "inherited" ] || { echo "layer not parsed ('$s_layer')"; return 1; }
    [ "$s_min" = "0" ] || { echo "minimum not parsed ('$s_min')"; return 1; }
    [ "$s_reason" = "inherited engine, measured upstream" ] || { echo "reason not parsed ('$s_reason')"; return 1; }
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
SCOPE_PROBLEMS=""
SCOPE_PROBLEM_COUNT=0
SEEN_PATHS=""

add_scope_problem() {
    SCOPE_PROBLEM_COUNT=$((SCOPE_PROBLEM_COUNT + 1))
    if [ "$SCOPE_PROBLEM_COUNT" -le 4 ]; then
        if [ -n "$SCOPE_PROBLEMS" ]; then SCOPE_PROBLEMS="$SCOPE_PROBLEMS; $1"; else SCOPE_PROBLEMS="$1"; fi
    fi
}

if [ -f "$PROJECT_ROOT/.standards.yml" ] && grep -qE '^coverage:' "$PROJECT_ROOT/.standards.yml" 2>/dev/null; then
    PARSED=$(parse_coverage_block "$PROJECT_ROOT/.standards.yml")
    US="$(printf '\037')"
    while IFS="$US" read -r tag f1 f2 f3 f4; do
        case "$tag" in
            MIN) STD_MIN="$f1" ;;
            SCOPE)
                SCOPE_COUNT=$((SCOPE_COUNT + 1))
                s_path="$f1"; s_layer="$f2"; s_min="$f3"; s_reason="$f4"
                label="${s_path:-scope #$SCOPE_COUNT}"
                if [ -z "$s_path" ]; then
                    add_scope_problem "$label has no path"
                    continue
                fi
                case " $SEEN_PATHS " in
                    *" $s_path "*) add_scope_problem "$label is declared more than once" ;;
                esac
                SEEN_PATHS="$SEEN_PATHS $s_path"
                if ! is_int "$s_min" || [ "$s_min" -gt 100 ]; then
                    add_scope_problem "$label has invalid minimum '${s_min:-<missing>}' (integer 0-100 required)"
                    continue
                fi
                case "$s_layer" in
                    domain|core)
                        if [ "$s_min" -ne 100 ]; then
                            add_scope_problem "$label is a $s_layer scope with floor ${s_min}% (domain/core must stay at 100%)"
                        fi
                        ;;
                esac
                overall="${STD_MIN:-$DEFAULT_MINIMUM}"
                is_int "$overall" || overall="$DEFAULT_MINIMUM"
                if [ "$s_min" -lt "$overall" ] && [ -z "$s_reason" ]; then
                    add_scope_problem "$label lowers the floor to ${s_min}% without a stated reason"
                fi
                ;;
        esac
    done <<EOF
$PARSED
EOF
fi

if [ "$SCOPE_PROBLEM_COUNT" -gt 0 ]; then
    more=""
    if [ "$SCOPE_PROBLEM_COUNT" -gt 4 ]; then more=" (+$((SCOPE_PROBLEM_COUNT - 4)) more)"; fi
    echo "FAIL $CHECK_NAME coverage.scopes in .standards.yml has $SCOPE_PROBLEM_COUNT problem(s): $SCOPE_PROBLEMS$more"
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
