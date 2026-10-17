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
   && grep -q '"warn"' "$TMP_BASE/out.json" \
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
# Build a valid-length AWS access key id (AKIA + 16 chars) at runtime by
# concatenation, so no key-shaped literal is committed to trip secret scanners.
aws_key="AKIA$(printf '%s' 'IOSFODNN7EXAMPLE')"   # 4 + 16 = 20 chars
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$secret/config.py"
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
    # Empty output is a failure too: a module that emits nothing is a silent
    # regression the runner would tally as zero results.
    if [ -z "$out" ] || ! echo "$out" | grep -qE '^(PASS|WARN|FAIL)'; then
        bad="$bad $(basename "$m")"
    fi
done
if [ -z "$bad" ]; then pass; else fail "modules with empty/unrecognized output:$bad"; fi

# --- quarantine-policy module (proc-05) --------------------------------------

# Portable date arithmetic for fixtures: GNU date first, then BSD/macOS date.
shift_date() {
    local days="$1"
    date -u -d "+${days} days" +%Y-%m-%d 2>/dev/null \
        || date -u -v+"${days}"d +%Y-%m-%d 2>/dev/null
}
TODAY="$(date -u +%Y-%m-%d)"
IN_10_DAYS="$(shift_date 10)"
IN_45_DAYS="$(shift_date 45)"

write_quarantine() {
    # $1 = file path, $2 = entries JSON (array body)
    printf '{\n  "version": 1,\n  "entries": [\n%s\n  ]\n}\n' "$2" > "$1"
}

echo -n "Test 12: quarantine-policy PASSes a project with no quarantine registry... "
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$proj" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 13: quarantine-policy PASSes a valid registry (all fields, window <= 30 days)... "
qp=$(make_project "quarantine-ok")
write_quarantine "$qp/test-quarantine.json" "    {\"test\": \"tests/api/test_users.py::test_list_users\", \"issue\": \"#123\", \"owner\": \"@alice\", \"reason\": \"flaky under parallel DB fixture\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qp" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 14: quarantine-policy FAILs an expired (past-due) entry... "
qe=$(make_project "quarantine-expired")
write_quarantine "$qe/test-quarantine.json" "    {\"test\": \"tests/api/test_users.py::test_list_users\", \"issue\": \"#123\", \"owner\": \"@alice\", \"reason\": \"flaky\", \"added\": \"2026-01-01\", \"expires\": \"2026-01-15\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qe" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -qi 'expired'; then pass; else fail "expected FAIL mentioning expired, got: $out"; fi

echo -n "Test 15: quarantine-policy FAILs an entry missing a required field (owner)... "
qm=$(make_project "quarantine-missing")
write_quarantine "$qm/test-quarantine.json" "    {\"test\": \"tests/api/test_users.py::test_list_users\", \"issue\": \"#123\", \"reason\": \"flaky\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qm" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'owner'; then pass; else fail "expected FAIL naming owner, got: $out"; fi

echo -n "Test 16: quarantine-policy FAILs a quarantine window longer than 30 days... "
qw=$(make_project "quarantine-window")
write_quarantine "$qw/test-quarantine.json" "    {\"test\": \"tests/api/test_users.py::test_list_users\", \"issue\": \"#123\", \"owner\": \"@alice\", \"reason\": \"flaky\", \"added\": \"$TODAY\", \"expires\": \"$IN_45_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '30'; then pass; else fail "expected FAIL mentioning 30-day limit, got: $out"; fi

echo -n "Test 17: quarantine-policy FAILs closed when .standards.yml declares a missing registry... "
qd=$(make_project "quarantine-declared")
printf 'version: 1\ntests:\n  quarantine_file: ci/test-quarantine.json\n' > "$qd/.standards.yml"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qd" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 18: quarantine-policy FAILs closed on a malformed registry... "
qb=$(make_project "quarantine-bad")
printf '{ "entries": [ { "test": "x" \n' > "$qb/test-quarantine.json"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qb" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 19: quarantine-policy honors tests.quarantine_file and counts entries... "
qc=$(make_project "quarantine-custom")
mkdir -p "$qc/ci"
printf 'version: 1\ntests:\n  quarantine_file: ci/test-quarantine.json\n' > "$qc/.standards.yml"
write_quarantine "$qc/ci/test-quarantine.json" "    {\"test\": \"a::b\", \"issue\": \"#1\", \"owner\": \"@a\", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"},
    {\"test\": \"c::d\", \"issue\": \"#2\", \"owner\": \"@b\", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qc" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out" | grep -q '2 '; then pass; else fail "expected PASS counting 2 entries, got: $out"; fi

echo -n "Test 19a: quarantine-policy FAILs closed on syntactically invalid JSON (missing comma)... "
qj=$(make_project "quarantine-badjson")
write_quarantine "$qj/test-quarantine.json" "    {\"test\": \"a::b\" \"issue\": \"#1\", \"owner\": \"@a\", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qj" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'not valid JSON'; then pass; else fail "expected FAIL mentioning invalid JSON, got: $out"; fi

echo -n "Test 19b: quarantine-policy FAILs an entries element that is not a quarantine entry... "
qo=$(make_project "quarantine-foreign")
write_quarantine "$qo/test-quarantine.json" "    {\"test\": \"a::b\", \"issue\": \"#1\", \"owner\": \"@a\", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"},
    {\"foo\": \"bar\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qo" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'entry #2'; then pass; else fail "expected FAIL naming entry #2, got: $out"; fi

echo -n "Test 19c: quarantine-policy FAILs an impossible calendar date (2027-02-31)... "
qx=$(make_project "quarantine-caldate")
write_quarantine "$qx/test-quarantine.json" "    {\"test\": \"a::b\", \"issue\": \"#1\", \"owner\": \"@a\", \"reason\": \"r\", \"added\": \"2027-02-31\", \"expires\": \"2027-03-10\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qx" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '2027-02-31'; then pass; else fail "expected FAIL naming the bad date, got: $out"; fi

echo -n "Test 19d: quarantine-policy FAILs a future-dated added entry... "
qf=$(make_project "quarantine-future")
write_quarantine "$qf/test-quarantine.json" "    {\"test\": \"a::b\", \"issue\": \"#1\", \"owner\": \"@a\", \"reason\": \"r\", \"added\": \"2099-01-01\", \"expires\": \"2099-01-20\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qf" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'future'; then pass; else fail "expected FAIL mentioning future, got: $out"; fi

echo -n "Test 19e: quarantine-policy FAILs closed when tests.quarantine_file is declared with no value... "
qv=$(make_project "quarantine-emptypath")
printf 'version: 1\ntests:\n  quarantine_file:\n' > "$qv/.standards.yml"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qv" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'no value'; then pass; else fail "expected FAIL mentioning no value, got: $out"; fi

echo -n "Test 19f: quarantine-policy FAILs a whitespace-only owner... "
qs=$(make_project "quarantine-blank")
write_quarantine "$qs/test-quarantine.json" "    {\"test\": \"a::b\", \"issue\": \"#1\", \"owner\": \"  \", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'owner'; then pass; else fail "expected FAIL naming owner, got: $out"; fi

echo -n "Test 19g: quarantine-policy PASSes an empty entries array and says 0 quarantined... "
qz=$(make_project "quarantine-zero")
write_quarantine "$qz/test-quarantine.json" ""
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qz" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out" | grep -q '0 quarantined'; then pass; else fail "expected PASS with 0 quarantined, got: $out"; fi

echo -n "Test 19h: quarantine-policy does not confuse an id with a word inside another id (spaces)... "
qw2=$(make_project "quarantine-spaces")
write_quarantine "$qw2/test-quarantine.json" "    {\"test\": \"suite applies promo\", \"issue\": \"#1\", \"owner\": \"@a\", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"},
    {\"test\": \"applies\", \"issue\": \"#2\", \"owner\": \"@b\", \"reason\": \"r\", \"added\": \"$TODAY\", \"expires\": \"$IN_10_DAYS\"}"
out=$(bash "$CHECKS/common/quarantine-policy.sh" "$qw2" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out" | grep -q '2 '; then pass; else fail "expected PASS counting 2 entries, got: $out"; fi

# --- coverage-config scopes (proc-05) ------------------------------------------

echo -n "Test 20: coverage-config PASSes a legacy single-number .standards.yml gate... "
cl=$(make_project "cov-legacy")
printf 'version: 1\ncoverage:\n  minimum: 95\n  domain: 100\n' > "$cl/.standards.yml"
out=$(bash "$CHECKS/common/coverage-config.sh" "$cl" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out" | grep -q '95'; then pass; else fail "expected PASS with 95, got: $out"; fi

echo -n "Test 21: coverage-config PASSes coverage.scopes and reports the scope count... "
cs=$(make_project "cov-scopes")
cat > "$cs/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  domain: 100
  scopes:
    - path: src/domain
      layer: domain
      minimum: 100
    - path: src/app
      layer: application
      minimum: 95
    - path: vendor/engine
      layer: inherited
      minimum: 0
      reason: inherited engine code, measured upstream
architecture: clean
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out" | grep -q '3 scope'; then pass; else fail "expected PASS with 3 scopes, got: $out"; fi

echo -n "Test 22: coverage-config FAILs a domain scope below 100%... "
cd1=$(make_project "cov-domain-low")
cat > "$cd1/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  scopes:
    - path: src/domain
      layer: domain
      minimum: 90
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cd1" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'src/domain'; then pass; else fail "expected FAIL naming src/domain, got: $out"; fi

echo -n "Test 23: coverage-config FAILs a lowered scope with no stated reason... "
cr=$(make_project "cov-no-reason")
cat > "$cr/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  scopes:
    - path: native/metal
      layer: native
      minimum: 0
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cr" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'reason'; then pass; else fail "expected FAIL mentioning reason, got: $out"; fi

echo -n "Test 24: coverage-config FAILs a scope entry with no path... "
cp1=$(make_project "cov-no-path")
cat > "$cp1/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  scopes:
    - layer: application
      minimum: 95
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cp1" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'path'; then pass; else fail "expected FAIL mentioning path, got: $out"; fi

echo -n "Test 24a: coverage-config enters scopes: even with a trailing YAML comment... "
cc1=$(make_project "cov-scopes-comment")
cat > "$cc1/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  scopes: # per-module floors
    - path: src/domain
      layer: domain
      minimum: 0
      reason: should not matter for a domain scope
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cc1" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'src/domain'; then pass; else fail "expected FAIL naming src/domain, got: $out"; fi

echo -n "Test 24b: coverage-config applies a minimum declared after scopes... "
cm=$(make_project "cov-min-late")
cat > "$cm/.standards.yml" <<'YML'
version: 1
coverage:
  scopes:
    - path: src/app
      layer: application
      minimum: 95
  minimum: 100
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cm" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'reason'; then pass; else fail "expected FAIL mentioning reason (95 < 100), got: $out"; fi

echo -n "Test 24c: coverage-config FAILs an unknown layer name... "
cu=$(make_project "cov-layer-typo")
cat > "$cu/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  scopes:
    - path: src/domain
      layer: domian
      minimum: 0
      reason: typo
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$cu" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'unknown layer'; then pass; else fail "expected FAIL mentioning unknown layer, got: $out"; fi

echo -n "Test 24d: coverage-config FAILs an oversized minimum instead of erroring through to PASS... "
ch=$(make_project "cov-huge")
cat > "$ch/.standards.yml" <<'YML'
version: 1
coverage:
  minimum: 95
  scopes:
    - path: src/app
      minimum: 99999999999999999999999
YML
out=$(bash "$CHECKS/common/coverage-config.sh" "$ch" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'invalid minimum'; then pass; else fail "expected FAIL mentioning invalid minimum, got: $out"; fi

# --- Sibling scripts smoke --------------------------------------------------

echo -n "Test 25: diff-standards.sh runs on a project without .standards.yml... "
if bash "$REPO_ROOT/scripts/diff-standards.sh" "$proj" >/dev/null 2>&1; then pass; else
    # diff-standards may exit non-zero; accept as long as it doesn't crash hard (>1)
    rc=$?; if [ "$rc" -le 1 ]; then pass; else fail "diff-standards crashed (exit $rc)"; fi
fi

echo -n "Test 26: doctor.sh runs without a hard crash... "
( cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -le 1 ]; then pass; else fail "doctor.sh crashed (exit $rc)"; fi

# --- #182: diff-standards.sh contract ---------------------------------------

fake_standards() {
    local proj="$1"
    mkdir -p "$proj/.standards"
    ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
    ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
}

echo -n "Test 14: diff-standards.sh exits 0 without --exit-code even when changes are pending... "
proj=$(make_project "diff-pending")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\n' > "$proj/.standards.yml"
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0, got $rc"; fi

echo -n "Test 15: diff-standards.sh --exit-code exits 1 when a config would be created... "
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "expected 1, got $rc"; fi

echo -n "Test 16: diff-standards.sh prints the sync script path (not a Make target) with no literal escapes... "
out=$( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" 2>&1 ) || true
if echo "$out" | grep -q "./.standards/scripts/sync-standards.sh" \
   && ! echo "$out" | grep -q "make sync-standards" \
   && ! echo "$out" | grep -qF '\033'; then
    pass
else
    fail "hint/escape problem in output: $out"
fi

echo -n "Test 17: diff-standards.sh --exit-code exits 0 once configs are up to date... "
( cd "$proj" && bash "$REPO_ROOT/scripts/setup.sh" --agents codex --languages typescript >/dev/null 2>&1 ) || true
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "expected 0 after setup, got $rc"; fi

echo -n "Test 18: diff-standards.sh --exit-code exits 0 when only the project-specific section was edited... "
# Content below the BEGIN PROJECT-SPECIFIC marker is owned by the consumer and
# preserved by sync; it must never register as drift.
printf '\n## Local notes\n\nProject-owned content.\n' >> "$proj/AGENTS.md"
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "project-specific section counted as drift (rc=$rc)"; fi

echo -n "Test 19: diff-standards.sh --exit-code exits 1 after the standards-owned section drifts... "
# Insert a line right after the assembly header, i.e. above the sentinel.
{ head -1 "$proj/AGENTS.md"; echo "# local drift"; tail -n +2 "$proj/AGENTS.md"; } > "$proj/AGENTS.md.tmp" \
    && mv "$proj/AGENTS.md.tmp" "$proj/AGENTS.md"
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 1 ]; then pass; else fail "expected 1 after drift, got $rc"; fi

echo -n "Test 20: diff-standards.sh [project-root] resolves template vars against that root, not the cwd... "
alpha=$(make_project "diff-alpha")
fake_standards "$alpha"
printf '{ "name": "alpha-pkg" }\n' > "$alpha/package.json"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - claude-code\nrole: service\n' > "$alpha/.standards.yml"
( cd "$alpha" && bash "$REPO_ROOT/scripts/setup.sh" --agents claude-code --languages typescript >/dev/null 2>&1 ) || true
beta=$(make_project "diff-beta")
( cd "$beta" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code "$alpha" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ] && grep -q "alpha-pkg" "$alpha/CLAUDE.md"; then pass; else
    fail "expected 0 when run from another repo with explicit root, got $rc"
fi

echo -n "Test 21: diff-standards.sh refuses to run from inside .standards/... "
inside=$(make_project "diff-inside")
mkdir -p "$inside/.standards"
( cd "$inside/.standards" && git init -q \
    && git -c user.email="t@t.local" -c user.name="T" commit -q --allow-empty -m "chore: init" )
out=$( cd "$inside/.standards" && bash "$REPO_ROOT/scripts/diff-standards.sh" 2>&1 ); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "inside"; then pass; else fail "expected refusal (rc=$rc): $out"; fi

echo -n "Test 22: diff-standards.sh rejects an unknown option with exit 2... "
( cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --bogus >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 2 ]; then pass; else fail "expected 2, got $rc"; fi

# --- Rust check modules -----------------------------------------------------

echo -n "Test 23: rust/clippy-ci PASSes when CI runs clippy with -D warnings... "
rs=$(make_project "rust-clippy-good")
mkdir -p "$rs/.github/workflows"
cat > "$rs/.github/workflows/ci.yml" <<'EOF'
jobs:
  lint:
    steps:
      - run: cargo clippy --workspace --all-targets --all-features -- -D warnings
EOF
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/clippy-ci'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 24: rust/clippy-ci WARNs when clippy runs without -D warnings... "
rs=$(make_project "rust-clippy-warn")
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  lint:\n    steps:\n      - run: cargo clippy --all-targets\n' > "$rs/.github/workflows/ci.yml"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/clippy-ci'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 25: rust/clippy-ci FAILs when no CI workflow runs clippy... "
rs=$(make_project "rust-clippy-none")
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: cargo test\n' > "$rs/.github/workflows/ci.yml"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/clippy-ci'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 26: rust/deny-config PASSes with a deny.toml license allow-list... "
rs=$(make_project "rust-deny-good")
printf '[licenses]\nallow = ["MIT", "Apache-2.0"]\n' > "$rs/deny.toml"
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/deny-config'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 27: rust/deny-config WARNs when deny.toml has no license allow-list... "
rs=$(make_project "rust-deny-nolicense")
printf '[advisories]\nvulnerability = "deny"\n' > "$rs/deny.toml"
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/deny-config'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 28: rust/deny-config FAILs when deny.toml is missing... "
rs=$(make_project "rust-deny-missing")
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/deny-config'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 29: rust/toolchain-pin PASSes when toolchain, rust-version and CI agree... "
rs=$(make_project "rust-pin-good")
printf '[toolchain]\nchannel = "1.99.0"\ncomponents = ["clippy", "rustfmt"]\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nversion = "0.1.0"\nedition = "2021"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
mkdir -p "$rs/.github/workflows"
cat > "$rs/.github/workflows/ci.yml" <<'EOF'
jobs:
  test:
    steps:
      - uses: dtolnay/rust-toolchain@master
        with:
          toolchain: 1.99.0
      - run: cargo test
EOF
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/toolchain-pin'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 30: rust/toolchain-pin FAILs when CI pins a different toolchain... "
rs=$(make_project "rust-pin-ci-drift")
printf '[toolchain]\nchannel = "1.99.0"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - uses: dtolnay/rust-toolchain@1.98.0\n' > "$rs/.github/workflows/ci.yml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/toolchain-pin'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 31: rust/toolchain-pin FAILs when rust-version is newer than the pinned toolchain... "
rs=$(make_project "rust-pin-msrv-newer")
printf '[toolchain]\nchannel = "1.98.0"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/toolchain-pin'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 32: rust/toolchain-pin WARNs when rust-toolchain.toml is missing... "
rs=$(make_project "rust-pin-missing")
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/toolchain-pin'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 33: rust/ffi-no-unwrap PASSes when facade files are panic-free... "
rs=$(make_project "rust-ffi-good")
mkdir -p "$rs/src"
cat > "$rs/src/ffi.rs" <<'EOF'
#![deny(clippy::disallowed_methods)]
// unwrap() in this comment must not count
#[no_mangle]
pub extern "C" fn demo_parse(input: *const u8) -> i32 {
    match parse(input) { Ok(_) => 0, Err(_) => -1 }
}
EOF
printf 'pub fn helper() -> i32 { Some(1).unwrap() }\n' > "$rs/src/lib.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/ffi-no-unwrap'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 34: rust/ffi-no-unwrap FAILs on unwrap()/expect() in ffi.rs or wasm.rs... "
rs=$(make_project "rust-ffi-bad")
mkdir -p "$rs/src"
printf 'pub extern "C" fn demo() -> i32 { parse().unwrap() }\n' > "$rs/src/ffi.rs"
printf '#[wasm_bindgen]\npub fn demo() -> u32 { parse().expect("boom") }\n' > "$rs/src/wasm.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/ffi-no-unwrap' && echo "$out" | grep -q 'ffi.rs' && echo "$out" | grep -q 'wasm.rs'; then
    pass
else
    fail "expected FAIL naming both files, got: $out"
fi

echo -n "Test 35: rust/ffi-no-unwrap PASSes when no facade files exist... "
rs=$(make_project "rust-ffi-none")
mkdir -p "$rs/src"; printf 'fn main() {}\n' > "$rs/src/main.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/ffi-no-unwrap'; then pass; else fail "expected PASS, got: $out"; fi

# --- Swift check modules ----------------------------------------------------

echo -n "Test 36: swift/swift-format-config PASSes with a .swift-format file... "
sw=$(make_project "swift-format-good")
printf '{ "version": 1, "lineLength": 120 }\n' > "$sw/.swift-format"
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/swift-format-config'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 37: swift/swift-format-config WARNs when only .swiftlint.yml exists... "
sw=$(make_project "swift-format-swiftlint-only")
printf 'disabled_rules: []\n' > "$sw/.swiftlint.yml"
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN swift/swift-format-config'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 38: swift/swift-format-config FAILs with no formatter config... "
sw=$(make_project "swift-format-none")
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/swift-format-config'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 39: swift/package-resolved PASSes when Package.resolved is committed... "
sw=$(make_project "swift-resolved-good")
printf '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")])\n' > "$sw/Package.swift"
printf '{ "pins": [], "version": 3 }\n' > "$sw/Package.resolved"
( cd "$sw" && git add Package.swift Package.resolved \
    && git -c user.email="t@t.local" -c user.name="T" commit -q -m "chore: add package" )
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/package-resolved'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 40: swift/package-resolved FAILs when Package.resolved is gitignored... "
sw=$(make_project "swift-resolved-ignored")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")])\n' > "$sw/Package.swift"
printf '{ "pins": [] }\n' > "$sw/Package.resolved"
printf 'Package.resolved\n' > "$sw/.gitignore"
( cd "$sw" && git add Package.swift .gitignore \
    && git -c user.email="t@t.local" -c user.name="T" commit -q -m "chore: add package" )
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/package-resolved'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 41: swift/package-resolved FAILs when an executable has dependencies but no Package.resolved... "
sw=$(make_project "swift-resolved-missing")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")], targets: [.executableTarget(name: "Demo")])\n' > "$sw/Package.swift"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/package-resolved'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 42: swift/package-resolved PASSes for a dependency-free package... "
sw=$(make_project "swift-resolved-nodeps")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", targets: [.target(name: "Demo")])\n' > "$sw/Package.swift"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/package-resolved'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 43: swift/warnings-as-errors PASSes when CI passes -warnings-as-errors... "
sw=$(make_project "swift-wae-ci")
mkdir -p "$sw/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: swift build -Xswiftc -warnings-as-errors\n' > "$sw/.github/workflows/ci.yml"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/warnings-as-errors'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 44: swift/warnings-as-errors PASSes when project.yml sets SWIFT_TREAT_WARNINGS_AS_ERRORS... "
sw=$(make_project "swift-wae-xcodegen")
printf 'settings:\n  base:\n    SWIFT_TREAT_WARNINGS_AS_ERRORS: YES\n' > "$sw/project.yml"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS swift/warnings-as-errors'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 45: swift/warnings-as-errors FAILs when nothing enables it... "
sw=$(make_project "swift-wae-none")
mkdir -p "$sw/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: swift test\n' > "$sw/.github/workflows/ci.yml"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/warnings-as-errors'; then pass; else fail "expected FAIL, got: $out"; fi

# --- Runner wiring for the new language directories --------------------------

echo -n "Test 46: runner activates rust/ and swift/ checks from .standards.yml languages... "
wired=$(make_project "wired-rust-swift")
printf 'version: 1\nlanguages:\n  - rust\n  - swift\n' > "$wired/.standards.yml"
"$LINT" --format json "$wired" > "$TMP_BASE/wired.json" 2>/dev/null || true
if grep -q '"check": "rust/clippy-ci"' "$TMP_BASE/wired.json" \
   && grep -q '"check": "rust/toolchain-pin"' "$TMP_BASE/wired.json" \
   && grep -q '"check": "swift/swift-format-config"' "$TMP_BASE/wired.json" \
   && grep -q '"check": "swift/package-resolved"' "$TMP_BASE/wired.json"; then
    pass
else
    fail "rust/ or swift/ checks missing from JSON output"
fi

# --- Review follow-ups (#207): precision fixes to the rust/ and swift/ modules

echo -n "Test 47: rust/clippy-ci FAILs when only a Makefile runs clippy and no CI definition exists... "
rs=$(make_project "rust-clippy-makefile-only")
printf 'lint:\n\tcargo clippy --all-targets -- -D warnings\n' > "$rs/Makefile"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/clippy-ci'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 48: rust/clippy-ci PASSes when CI delegates to a Makefile that runs clippy -D warnings... "
rs=$(make_project "rust-clippy-via-make")
mkdir -p "$rs/.github/workflows"
printf 'jobs:\n  lint:\n    steps:\n      - run: make lint\n' > "$rs/.github/workflows/ci.yml"
printf 'lint:\n\tcargo clippy --all-targets -- -D warnings\n' > "$rs/Makefile"
out=$(bash "$CHECKS/rust/clippy-ci.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/clippy-ci'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 49: rust/deny-config PASSes with single-quoted TOML license strings... "
rs=$(make_project "rust-deny-single-quotes")
printf "[licenses]\nallow = ['MIT', 'Apache-2.0']\n" > "$rs/deny.toml"
out=$(bash "$CHECKS/rust/deny-config.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS rust/deny-config.*2 license'; then pass; else fail "expected PASS with 2 licenses, got: $out"; fi

echo -n "Test 50: rust/toolchain-pin WARNs when the channel lacks a patch component... "
rs=$(make_project "rust-pin-no-patch")
printf '[toolchain]\nchannel = "1.99"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN rust/toolchain-pin.*major.minor.patch'; then pass; else fail "expected WARN about patch component, got: $out"; fi

echo -n "Test 51: rust/toolchain-pin FAILs when .gitlab-ci.yml pins a different toolchain... "
rs=$(make_project "rust-pin-gitlab-drift")
printf '[toolchain]\nchannel = "1.99.0"\n' > "$rs/rust-toolchain.toml"
printf '[package]\nname = "demo"\nrust-version = "1.99"\n' > "$rs/Cargo.toml"
printf 'test:\n  script:\n    - rustup default 1.98.0\n    - cargo test\n' > "$rs/.gitlab-ci.yml"
out=$(bash "$CHECKS/rust/toolchain-pin.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/toolchain-pin.*gitlab-ci.yml'; then pass; else fail "expected FAIL naming .gitlab-ci.yml, got: $out"; fi

echo -n "Test 52: rust/ffi-no-unwrap FAILs even when the unwrap line carries an allow() annotation... "
rs=$(make_project "rust-ffi-allow-text")
mkdir -p "$rs/src"
printf '#[allow(clippy::unwrap_used)] pub extern "C" fn demo() -> i32 { parse().unwrap() }\n' > "$rs/src/ffi.rs"
out=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$rs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL rust/ffi-no-unwrap'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 53: swift/swift-format-config WARNs when only .swift-format.json exists (not auto-discovered)... "
sw=$(make_project "swift-format-json-only")
printf '{ "version": 1 }\n' > "$sw/.swift-format.json"
out=$(bash "$CHECKS/swift/swift-format-config.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN swift/swift-format-config.*--configuration'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 54: swift/package-resolved WARNs (not FAIL) for a library with dependencies and no CI build... "
sw=$(make_project "swift-resolved-library")
printf '// swift-tools-version: 6.0\nlet package = Package(name: "Demo", dependencies: [.package(url: "https://example.com/x", from: "1.0.0")], targets: [.target(name: "Demo")])\n' > "$sw/Package.swift"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN swift/package-resolved'; then pass; else fail "expected WARN, got: $out"; fi

echo -n "Test 55: swift/package-resolved FAILs for a library with dependencies and a CI build but no lockfile... "
mkdir -p "$sw/.github/workflows"
printf 'jobs:\n  test:\n    steps:\n      - run: swift test\n' > "$sw/.github/workflows/ci.yml"
out=$(bash "$CHECKS/swift/package-resolved.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/package-resolved'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 56: swift/warnings-as-errors FAILs when only an unrelated C -Werror flag exists... "
sw=$(make_project "swift-wae-cflags")
printf 'CFLAGS = -Wall -Werror\n\nbuild:\n\tswift build\n' > "$sw/Makefile"
out=$(bash "$CHECKS/swift/warnings-as-errors.sh" "$sw" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL swift/warnings-as-errors'; then pass; else fail "expected FAIL, got: $out"; fi

# --- CI hygiene modules (arch-08 §3 / §6) ----------------------------------

# Helper: write a workflow file (from stdin) into a project's .github/workflows/.
write_workflow() {
    local proj="$1" name="$2"
    mkdir -p "$proj/.github/workflows"
    cat > "$proj/.github/workflows/$name"
}

echo -n "Test 57: headless-ci PASSes a workflow with no GUI/login-keychain steps... "
hl_clean=$(make_project "headless-clean")
write_workflow "$hl_clean" "release.yml" <<'EOF'
name: Release
on:
  push:
    tags: ['v*']
jobs:
  notarize:
    runs-on: [self-hosted, macOS]
    steps:
      - run: xcrun notarytool submit app.zip --apple-id "$ID" --team-id "$TEAM" --password "$PW" --wait
EOF
out=$(bash "$CHECKS/common/headless-ci.sh" "$hl_clean" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 58: headless-ci WARNs on notarytool store-credentials... "
hl_store=$(make_project "headless-store")
write_workflow "$hl_store" "release.yml" <<'EOF'
name: Release
on: push
jobs:
  notarize:
    runs-on: macos-latest
    steps:
      - run: xcrun notarytool store-credentials "AC_PASSWORD" --apple-id "$ID" --team-id "$TEAM" --password "$PW"
EOF
out=$(bash "$CHECKS/common/headless-ci.sh" "$hl_store" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'store-credentials'; then pass; else fail "expected WARN naming store-credentials, got: $out"; fi

echo -n "Test 59: headless-ci WARNs on osascript, open -a, and login-keychain unlock... "
hl_gui=$(make_project "headless-gui")
write_workflow "$hl_gui" "ui.yml" <<'EOF'
name: UI
on: push
jobs:
  ui:
    runs-on: macos-latest
    steps:
      - run: security unlock-keychain -p "$PW" ~/Library/Keychains/login.keychain-db
      - run: osascript -e 'tell application "Simulator" to activate'
      - run: open -a Simulator
EOF
out=$(bash "$CHECKS/common/headless-ci.sh" "$hl_gui" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' \
   && echo "$out" | grep -q 'osascript' \
   && echo "$out" | grep -q 'open -a' \
   && echo "$out" | grep -q 'unlock-keychain'; then pass; else fail "expected WARN naming all three, got: $out"; fi

echo -n "Test 60: headless-ci ignores commented-out mentions and job-scoped keychains... "
hl_comment=$(make_project "headless-comment")
write_workflow "$hl_comment" "release.yml" <<'EOF'
name: Release
on: push
jobs:
  sign:
    runs-on: macos-latest
    steps:
      # Never call osascript or store-credentials here: runners are headless.
      - run: |
          security create-keychain -p "$PW" "$RUNNER_TEMP/ci.keychain-db"
          security unlock-keychain -p "$PW" "$RUNNER_TEMP/ci.keychain-db"
EOF
out=$(bash "$CHECKS/common/headless-ci.sh" "$hl_comment" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 61: ci-workflow-hygiene PASSes a compliant pull_request workflow... "
hy_good=$(make_project "hygiene-good")
write_workflow "$hy_good" "ci.yml" <<'EOF'
name: CI
on:
  pull_request:
    paths:
      - 'src/**'
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - run: make ci
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_good" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 62: ci-workflow-hygiene WARNs and names concurrency, timeout, and paths when all are missing... "
hy_bad=$(make_project "hygiene-bad")
write_workflow "$hy_bad" "ci.yml" <<'EOF'
name: CI
on:
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: make ci
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_bad" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' \
   && echo "$out" | grep -q 'ci.yml' \
   && echo "$out" | grep -q 'concurrency' \
   && echo "$out" | grep -q 'timeout-minutes' \
   && echo "$out" | grep -q 'path'; then pass; else fail "expected WARN naming all three gaps, got: $out"; fi

echo -n "Test 63: ci-workflow-hygiene ignores workflows that do not run on pull_request... "
hy_push=$(make_project "hygiene-push")
write_workflow "$hy_push" "deploy.yml" <<'EOF'
name: Deploy
on:
  push:
    branches: [main]
  workflow_call:
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: make deploy
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_push" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 64: ci-workflow-hygiene accepts paths-filter + gate and an explicit paths-exempt marker... "
hy_alt=$(make_project "hygiene-alt")
write_workflow "$hy_alt" "ci.yml" <<'EOF'
name: CI
on: [push, pull_request]
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  changes:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      web: ${{ steps.filter.outputs.web }}
    steps:
      - uses: dorny/paths-filter@de90cc6fb38fc0963ad72b210f1f284cd68cea36 # v3.0.2
        id: filter
        with:
          filters: .github/ci/routing.yml
  web:
    needs: changes
    if: needs.changes.outputs.web == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - run: make ci-web
  ci-gate:
    needs: [changes, web]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: test "${{ needs.web.result }}" != "failure"
EOF
write_workflow "$hy_alt" "labeler.yml" <<'EOF'
name: Labeler
# ci-hygiene: paths-exempt — labels every PR from its title, independent of changed paths
on: pull_request
concurrency:
  group: labeler-${{ github.ref }}
  cancel-in-progress: false
jobs:
  label:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - run: echo label
  reusable:
    uses: org/repo/.github/workflows/shared.yml@main
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_alt" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 65: ci-workflow-hygiene flags a job that lacks timeout-minutes when a sibling has one... "
hy_partial=$(make_project "hygiene-partial")
write_workflow "$hy_partial" "ci.yml" <<'EOF'
name: CI
on:
  pull_request:
    paths: ['src/**']
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  fast:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - run: make lint
  slow:
    runs-on: ubuntu-latest
    steps:
      - run: make test
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_partial" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'timeout-minutes' \
   && ! echo "$out" | grep -q 'concurrency'; then pass; else fail "expected WARN about timeout only, got: $out"; fi

echo -n "Test 66: ci-workflow-hygiene ignores a nested paths: key that is not on the PR trigger... "
hy_nested=$(make_project "hygiene-nested")
write_workflow "$hy_nested" "ci.yml" <<'EOF'
name: CI
on:
  push:
    paths: ['src/**']
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  scan:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: org/some-scanner@v1
        with:
          paths:
            - 'src/**'
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_nested" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'path scoping'; then pass; else fail "expected WARN about path scoping, got: $out"; fi

echo -n "Test 67: ci-workflow-hygiene flags job-level concurrency that covers only some jobs... "
hy_jobconc=$(make_project "hygiene-jobconc")
write_workflow "$hy_jobconc" "ci.yml" <<'EOF'
name: CI
on:
  pull_request:
    paths: ['src/**']
jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    concurrency:
      group: lint-${{ github.ref }}
      cancel-in-progress: true
    steps:
      - run: make lint
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - run: make test
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_jobconc" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q '1/2 job(s) lack concurrency' \
   && ! echo "$out" | grep -q 'timeout-minutes'; then pass; else fail "expected WARN about partial concurrency only, got: $out"; fi

echo -n "Test 68: ci-workflow-hygiene accepts job-level concurrency when every job declares it... "
hy_alljobs=$(make_project "hygiene-alljobs")
write_workflow "$hy_alljobs" "ci.yml" <<'EOF'
name: CI
on:
  pull_request:
    paths-ignore: ['docs/**']
jobs:
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    concurrency:
      group: lint-${{ github.ref }}
      cancel-in-progress: true
    steps:
      - run: make lint
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    concurrency:
      group: test-${{ github.ref }}
      cancel-in-progress: true
    steps:
      - run: make test
EOF
out=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$hy_alljobs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 69: headless-ci catches an absolute-path open -a but not --open -a or xdg-open -a... "
hl_abs=$(make_project "headless-abs")
write_workflow "$hl_abs" "ui.yml" <<'EOF'
name: UI
on: push
jobs:
  ui:
    runs-on: macos-latest
    steps:
      - run: /usr/bin/open -a Simulator
EOF
write_workflow "$hl_abs" "docs.yml" <<'EOF'
name: Docs
on: push
jobs:
  docs:
    runs-on: ubuntu-latest
    steps:
      - run: mdbook serve --open -a 127.0.0.1
      - run: xdg-open -a something
EOF
out=$(bash "$CHECKS/common/headless-ci.sh" "$hl_abs" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'ui.yml: open -a' \
   && ! echo "$out" | grep -q 'docs.yml'; then pass; else fail "expected WARN naming ui.yml only, got: $out"; fi

echo -n "Test 70: this repo's own workflows pass headless-ci and ci-workflow-hygiene (dogfood)... "
out_h=$(bash "$CHECKS/common/headless-ci.sh" "$REPO_ROOT" 2>/dev/null || true)
out_c=$(bash "$CHECKS/common/ci-workflow-hygiene.sh" "$REPO_ROOT" 2>/dev/null || true)
if echo "$out_h" | grep -q '^PASS' && echo "$out_c" | grep -q '^PASS'; then pass; else fail "dogfood failed: $out_h / $out_c"; fi

# --- conventional-commits module options (#185) -----------------------------

# Helper: one (possibly non-conventional) empty commit in a temp project.
cc_commit() {
    ( cd "$1" && git -c user.email="t@t.local" -c user.name="T" \
        commit -q --allow-empty -m "$2" )
}

CC_MOD="$CHECKS/common/conventional-commits.sh"

echo -n "Test 71: conventional-commits default window is wider than 10 commits... "
win=$(make_project "cc-window")
cc_commit "$win" "Prose title that is not conventional (#1)"
i=0; while [ "$i" -lt 11 ]; do cc_commit "$win" "feat(core): change $i"; i=$((i + 1)); done
out=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
# 13 commits total: init + 1 bad + 11 good. A 10-commit window would miss the bad one.
if echo "$out" | grep -qE '^(WARN|FAIL) conventional-commits 1 of' && echo "$out" | grep -q '13'; then pass; else
    fail "expected the bad commit at depth 12 to be counted, got: $out"; fi

echo -n "Test 72: commits.window in .standards.yml narrows the window... "
printf 'version: 1\ncommits:\n  window: 5\n' > "$win/.standards.yml"
out=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS with window 5, got: $out"; fi
rm -f "$win/.standards.yml"

echo -n "Test 73: --window flag overrides the default... "
out=$(bash "$CC_MOD" --window 5 "$win" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS with --window 5, got: $out"; fi

echo -n "Test 74: --since <ref> checks only commits after the ref... "
( cd "$win" && git tag cc-base HEAD~3 )
out=$(bash "$CC_MOD" --since cc-base "$win" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out" | grep -q 'cc-base'; then pass; else fail "expected PASS mentioning cc-base, got: $out"; fi

echo -n "Test 75: --since <ref> flags a bad commit inside the range... "
cc_commit "$win" "fixed stuff"
out=$(bash "$CC_MOD" --since cc-base "$win" 2>/dev/null || true)
if echo "$out" | grep -qE '^(WARN|FAIL) conventional-commits 1 of 4'; then pass; else fail "expected 1 of 4 flagged, got: $out"; fi

echo -n "Test 76: --since with an unknown ref WARNs (exit 2) instead of crashing... "
out=$(bash "$CC_MOD" --since no-such-ref "$win" 2>/dev/null); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q '^WARN'; then pass; else fail "expected WARN/exit 2, got exit $rc: $out"; fi

echo -n "Test 77: commits.since in .standards.yml is honoured... "
printf 'version: 1\ncommits:\n  since: cc-base\n' > "$win/.standards.yml"
out=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
if echo "$out" | grep -qE '^(WARN|FAIL)' && echo "$out" | grep -q 'cc-base'; then pass; else fail "expected finding since cc-base, got: $out"; fi
rm -f "$win/.standards.yml"

echo -n "Test 78: commits.scopes allow-list PASSes commits using listed scopes... "
sc=$(make_project "cc-scopes")
cc_commit "$sc" "feat(api): add endpoint"
cc_commit "$sc" "fix: unscoped commits stay allowed"
printf 'version: 1\ncommits:\n  scopes:\n    - api\n    - domain\n' > "$sc/.standards.yml"
out=$(bash "$CC_MOD" "$sc" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 79: commits.scopes allow-list flags a scope outside the list... "
cc_commit "$sc" "feat(edit/macos): scope drift"
out=$(bash "$CC_MOD" "$sc" 2>/dev/null || true)
if echo "$out" | grep -qE '^(WARN|FAIL)' && echo "$out" | grep -qi 'scope'; then pass; else fail "expected scope finding, got: $out"; fi

echo -n "Test 80: inline commits.scopes list form is parsed... "
printf 'version: 1\ncommits:\n  scopes: [api, domain, edit/macos]\n' > "$sc/.standards.yml"
out=$(bash "$CC_MOD" "$sc" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS with inline list, got: $out"; fi

echo -n "Test 81: merge commits are not counted against the window... "
mg=$(make_project "cc-merge")
( cd "$mg" && git checkout -q -b topic )
cc_commit "$mg" "feat(x): topic work"
( cd "$mg" && git checkout -q - )
cc_commit "$mg" "chore: mainline work"
( cd "$mg" && git -c user.email="t@t.local" -c user.name="T" merge -q --no-ff --no-edit topic >/dev/null 2>&1 )
out=$(bash "$CC_MOD" "$mg" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS ignoring merge commit, got: $out"; fi

# --- check-commit-message.sh (hook + PR-title validator) --------------------

CHK="$REPO_ROOT/scripts/check-commit-message.sh"

echo -n "Test 82: check-commit-message.sh accepts a Conventional Commit subject... "
if bash "$CHK" "feat(api): add endpoint" >/dev/null 2>&1; then pass; else fail "valid subject rejected"; fi

echo -n "Test 83: check-commit-message.sh rejects a prose subject with an explanation... "
out=$(bash "$CHK" "Phase 1: repository scaffold and core (Tasks 7-9)" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -qi 'conventional'; then pass; else fail "expected rejection, got exit $rc: $out"; fi

echo -n "Test 84: check-commit-message.sh --file reads a commit message file (hook mode)... "
printf 'fix(ui): align header\n\nLonger body here.\n' > "$TMP_BASE/msg"
if bash "$CHK" --file "$TMP_BASE/msg" >/dev/null 2>&1; then pass; else fail "valid message file rejected"; fi

echo -n "Test 85: check-commit-message.sh skips fixup!/merge messages... "
printf 'fixup! feat: wip\n' > "$TMP_BASE/msg-fixup"
printf "Merge branch 'topic'\n" > "$TMP_BASE/msg-merge"
if bash "$CHK" --file "$TMP_BASE/msg-fixup" >/dev/null 2>&1 \
   && bash "$CHK" --file "$TMP_BASE/msg-merge" >/dev/null 2>&1; then pass; else fail "fixup!/merge messages should pass"; fi

echo -n "Test 86: check-commit-message.sh enforces commits.scopes from the project root... "
if ! bash "$CHK" --project-root "$sc" "feat(web): scope not in allow-list" >/dev/null 2>&1 \
   && bash "$CHK" --project-root "$sc" "feat(api): allowed scope" >/dev/null 2>&1; then pass; else
    fail "scope allow-list not enforced"; fi

# --- doctor.sh hook-manager detection ---------------------------------------

echo -n "Test 87: doctor.sh recognises lefthook.yml as the hook manager... "
lh=$(make_project "doctor-lefthook")
printf 'commit-msg:\n  commands:\n    conventional-commits:\n      run: .standards/scripts/check-commit-message.sh --file {1}\n' > "$lh/lefthook.yml"
out=$(cd "$lh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -qi 'lefthook' && ! echo "$out" | grep -q 'post-merge hook not installed'; then pass; else
    fail "lefthook not recognised: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 88: doctor.sh recognises .husky/ as the hook manager... "
hk=$(make_project "doctor-husky")
mkdir -p "$hk/.husky"
printf '#!/bin/sh\n.standards/scripts/check-commit-message.sh --file "$1"\n' > "$hk/.husky/commit-msg"
out=$(cd "$hk" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -qi 'husky' && ! echo "$out" | grep -q 'post-merge hook not installed'; then pass; else
    fail "husky not recognised: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 89: doctor.sh still reports a missing native post-merge hook... "
nh=$(make_project "doctor-native")
out=$(cd "$nh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep -q 'post-merge hook not installed'; then pass; else fail "native hook check regressed: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 90: doctor.sh warns when the hook manager has no commit-msg hook... "
lh2=$(make_project "doctor-lefthook-nomsg")
printf 'pre-commit:\n  commands:\n    lint:\n      run: make lint\n' > "$lh2/lefthook.yml"
out=$(cd "$lh2" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'WARN' && echo "$out" | grep 'Git Hooks' | grep -qi 'commit-msg'; then pass; else
    fail "expected commit-msg WARN: $(echo "$out" | grep 'Git Hooks')"; fi

# --- review follow-ups (#201) -----------------------------------------------

echo -n "Test 43: STANDARDS_COMMITS_SINCE (PR range) beats commits.window... "
# With commits.window pinned, the module must still report "commits since
# cc-base" (the CI PR range), not "commits (window 1)".
printf 'version: 1\ncommits:\n  window: 1\n' > "$win/.standards.yml"
out=$(cd "$win" && STANDARDS_COMMITS_SINCE=cc-base bash "$CC_MOD" "$win" 2>/dev/null || true)
if echo "$out" | grep -q 'since cc-base' && echo "$out" | grep -qE '^(WARN|FAIL)'; then pass; else
    fail "expected the PR range to win over commits.window, got: $out"; fi
rm -f "$win/.standards.yml"

echo -n "Test 44: commits.since beats STANDARDS_COMMITS_SINCE... "
( cd "$win" && git tag cc-head HEAD )
printf 'version: 1\ncommits:\n  since: cc-head\n' > "$win/.standards.yml"
out=$(cd "$win" && STANDARDS_COMMITS_SINCE=cc-base bash "$CC_MOD" "$win" 2>/dev/null || true)
if echo "$out" | grep -q 'cc-head'; then pass; else fail "expected commits.since to win, got: $out"; fi
rm -f "$win/.standards.yml"

echo -n "Test 45: single-quoted YAML scalars are parsed (window: '5', since: 'ref')... "
printf "version: 1\ncommits:\n  window: '5'\n" > "$win/.standards.yml"
out1=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
printf "version: 1\ncommits:\n  since: 'cc-base'\n" > "$win/.standards.yml"
out2=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
rm -f "$win/.standards.yml"
if echo "$out1" | grep -q 'window 5' && echo "$out2" | grep -q 'since cc-base'; then pass; else
    fail "quoted scalars not parsed: [$out1] [$out2]"; fi

echo -n "Test 46: a scope containing whitespace cannot match two allow-list entries... "
printf 'version: 1\ncommits:\n  scopes: [api, domain]\n' > "$sc/.standards.yml"
if ! bash "$CHK" --project-root "$sc" "feat(api domain): bypass" >/dev/null 2>&1; then pass; else
    fail "'api domain' was accepted against [api, domain]"; fi

echo -n "Test 47: check-commit-message.sh --no-exempt rejects merge/fixup/revert-style titles... "
if ! bash "$CHK" --no-exempt "Merge branch 'topic'" >/dev/null 2>&1 \
   && ! bash "$CHK" --no-exempt "fixup! feat: wip" >/dev/null 2>&1 \
   && ! bash "$CHK" --no-exempt 'Revert "feat: thing"' >/dev/null 2>&1 \
   && bash "$CHK" --no-exempt 'revert: "feat: thing"' >/dev/null 2>&1; then pass; else
    fail "--no-exempt did not reject exempt-style subjects"; fi

echo -n "Test 48: doctor.sh warns when lefthook.yml exists but hooks are not installed... "
out=$(cd "$lh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'not installed'; then pass; else
    fail "expected 'not installed' WARN: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 49: doctor.sh passes once lefthook hooks are installed (core.hooksPath set)... "
( cd "$lh" && git config core.hooksPath .lefthook-hooks )
out=$(cd "$lh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'hooks installed' && ! echo "$out" | grep 'Git Hooks' | grep -q 'not installed'; then pass; else
    fail "expected installed PASS: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 50: block-form commits.scopes survives blank and comment lines... "
printf 'version: 1\ncommits:\n  scopes:\n    # core areas\n    - api\n\n    # shared kernel\n    - domain\n' > "$sc/.standards.yml"
if bash "$CHK" --project-root "$sc" "feat(domain): after a comment line" >/dev/null 2>&1 \
   && ! bash "$CHK" --project-root "$sc" "feat(web): still enforced" >/dev/null 2>&1; then pass; else
    fail "block list truncated or emptied by comment/blank lines"; fi

echo -n "Test 51: doctor.sh does not credit lefthook for a core.hooksPath owned by another manager... "
mkdir -p "$lh2/.husky/_"
( cd "$lh2" && git config core.hooksPath .husky/_ )
out=$(cd "$lh2" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'lefthook hooks are not installed'; then pass; else
    fail "expected lefthook 'not installed' with husky hooksPath: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 52: doctor.sh requires a native commit-msg hook to be executable... "
printf '#!/bin/sh\nexit 0\n' > "$nh/.git/hooks/commit-msg"
chmod -x "$nh/.git/hooks/commit-msg"
out1=$(cd "$nh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
chmod +x "$nh/.git/hooks/commit-msg"
out2=$(cd "$nh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out1" | grep 'Git Hooks' | grep -q 'not executable' && echo "$out2" | grep 'Git Hooks' | grep -q 'commit-msg hook installed'; then pass; else
    fail "executable-bit check wrong: [$(echo "$out1" | grep commit-msg)] [$(echo "$out2" | grep commit-msg)]"; fi

echo -n "Test 53: doctor.sh reads native hooks from core.hooksPath when it is set... "
hp=$(make_project "doctor-hookspath")
mkdir -p "$hp/githooks"
printf '#!/bin/sh\nexit 0\n' > "$hp/githooks/commit-msg"
chmod +x "$hp/githooks/commit-msg"
printf '#!/bin/sh\nmake check-standards\n' > "$hp/githooks/post-merge"
chmod +x "$hp/githooks/post-merge"
( cd "$hp" && git config core.hooksPath githooks )
out=$(cd "$hp" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'commit-msg hook installed' \
   && echo "$out" | grep 'Git Hooks' | grep -q 'post-merge hook contains standards sync'; then pass; else
    fail "hooks under core.hooksPath not seen: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 54: doctor.sh requires the lefthook post-merge block to run the standards sync... "
lh3=$(make_project "doctor-lefthook-postmerge")
printf 'post-merge:\n  commands:\n    notify:\n      run: echo merged\n' > "$lh3/lefthook.yml"
out=$(cd "$lh3" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
printf 'post-merge:\n  commands:\n    standards-sync-reminder:\n      run: make check-standards\n' > "$lh3/lefthook.yml"
out2=$(cd "$lh3" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'does not run the standards sync' \
   && echo "$out2" | grep 'Git Hooks' | grep -q 'post-merge hook contains standards sync'; then pass; else
    fail "lefthook post-merge content check wrong: [$(echo "$out" | grep post-merge)] [$(echo "$out2" | grep post-merge)]"; fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All $PASS tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL of $((PASS + FAIL)) tests failed.${NC}"
    exit 1
fi
