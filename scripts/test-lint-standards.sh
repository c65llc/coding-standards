#!/bin/bash
# Functional tests for lint-standards.sh, its output formats, and the
# lint-checks modules — the product surface consumers hit in CI.
#
# Each test builds a temp project with known conditions and asserts outcomes.
# Prioritizes the linter's JSON/SARIF output (the standards-review action's
# contract) and a representative sample of check modules.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$REPO_ROOT/scripts/lint-standards.sh"
CHECKS="$REPO_ROOT/scripts/lint-checks"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-lint-standards.XXXXXX")"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

# Pick a JSON validator (python3 preferred; fall back to node).
json_valid() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$1" 2>/dev/null
    elif command -v node >/dev/null 2>&1; then
        node -e "JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'))" "$1" 2>/dev/null
    else
        echo "no JSON validator (python3/node) available" >&2
        return 2
    fi
}

make_project() {
    local name="$1"
    local dir="$TMP_BASE/$name"
    mkdir -p "$dir"
    ( cd "$dir" && git init -q \
        && git -c user.email="t@t.local" -c user.name="T" \
               commit -q --allow-empty -m "chore: init" )
    echo "$dir"
}

echo -e "${BLUE}Testing lint-standards.sh and lint-checks modules${NC}"
echo ""

# --- Runner + output formats ------------------------------------------------

echo -n "Test 1: lint-standards.sh exists and is executable... "
if [ -x "$LINT" ]; then pass; else fail "$LINT not executable"; fi

proj=$(make_project "basic")

echo -n "Test 2: --format text runs and exits cleanly (0 or 1)... "
"$LINT" --format text "$proj" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ]; then pass; else fail "unexpected exit $rc"; fi

echo -n "Test 3: --format json emits valid JSON... "
"$LINT" --format json "$proj" > "$TMP_BASE/out.json" 2>/dev/null || true
if json_valid "$TMP_BASE/out.json"; then pass; else fail "invalid JSON output"; fi

echo -n "Test 4: --format json has summary.pass/warn/fail keys... "
if grep -q '"summary"' "$TMP_BASE/out.json" \
   && grep -q '"pass"' "$TMP_BASE/out.json" \
   && grep -q '"fail"' "$TMP_BASE/out.json"; then pass; else fail "missing summary keys"; fi

echo -n "Test 5: --format sarif emits valid JSON (regression: bash 3.2 unbound array)... "
"$LINT" --format sarif "$proj" > "$TMP_BASE/out.sarif" 2>/dev/null || true
if json_valid "$TMP_BASE/out.sarif"; then pass; else fail "invalid SARIF output (see #132)"; fi

echo -n "Test 6: SARIF declares version 2.1.0 and a runs array... "
if grep -q '"version": "2.1.0"' "$TMP_BASE/out.sarif" \
   && grep -q '"runs"' "$TMP_BASE/out.sarif"; then pass; else fail "SARIF missing version/runs"; fi

echo -n "Test 7: unknown --format exits non-zero with a message... "
if ! "$LINT" --format bogus "$proj" >/dev/null 2>&1; then pass; else fail "bogus format did not fail"; fi

# --- Check modules ----------------------------------------------------------

echo -n "Test 8: no-secrets module PASSes a clean project... "
clean=$(make_project "clean")
echo "print('hello')" > "$clean/app.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$clean" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 9: no-secrets module FLAGS a hardcoded AWS key... "
secret=$(make_project "secret")
printf 'aws_secret_access_key = "AKIAIOSFODNN7EXAMPLE1234"\n' > "$secret/config.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$secret" 2>/dev/null || true)
if echo "$out" | grep -qE '^(FAIL|WARN)'; then pass; else fail "expected FAIL/WARN, got: $out"; fi

echo -n "Test 10: conventional-commits module PASSes conventional history... "
cc=$(make_project "cc-good")
( cd "$cc" && git -c user.email="t@t.local" -c user.name="T" \
    commit -q --allow-empty -m "feat(api): add endpoint" )
out=$(bash "$CHECKS/common/conventional-commits.sh" "$cc" 2>/dev/null || true)
if echo "$out" | grep -qE '^(PASS|WARN)'; then pass; else fail "expected PASS/WARN, got: $out"; fi

echo -n "Test 11: every check module emits a recognized status line... "
bad=""
for m in "$CHECKS"/*/*.sh; do
    out=$(bash "$m" "$proj" 2>/dev/null || true)
    if [ -n "$out" ] && ! echo "$out" | grep -qE '^(PASS|WARN|FAIL)'; then
        bad="$bad $(basename "$m")"
    fi
done
if [ -z "$bad" ]; then pass; else fail "modules with unrecognized output:$bad"; fi

# --- Sibling scripts smoke --------------------------------------------------

echo -n "Test 12: diff-standards.sh runs on a project without .standards.yml... "
if bash "$REPO_ROOT/scripts/diff-standards.sh" "$proj" >/dev/null 2>&1; then pass; else
    # diff-standards may exit non-zero; accept as long as it doesn't crash hard (>1)
    rc=$?; if [ "$rc" -le 1 ]; then pass; else fail "diff-standards crashed (exit $rc)"; fi
fi

echo -n "Test 13: doctor.sh runs without a hard crash... "
( cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -le 1 ]; then pass; else fail "doctor.sh crashed (exit $rc)"; fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All $PASS tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL of $((PASS + FAIL)) tests failed.${NC}"
    exit 1
fi
