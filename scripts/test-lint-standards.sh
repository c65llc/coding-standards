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

# --- doc-lint module --------------------------------------------------------

DOC_LINT="$CHECKS/common/doc-lint.sh"

echo -n "Test 25: doc-lint module exists and is executable... "
if [ -x "$DOC_LINT" ]; then pass; else fail "$DOC_LINT missing or not executable"; fi

echo -n "Test 26: doc-lint PASSes an ADR with bullet metadata and required sections... "
adr_ok=$(make_project "adr-ok")
mkdir -p "$adr_ok/docs/adr"
cat > "$adr_ok/docs/adr/0001-use-sqlite.md" <<'EOF'
# ADR 0001: Use SQLite for local state

- **Status:** Accepted
- **Date:** 2026-10-17
- **Related:** #42

## Context

We need a local store.

## Decision

Use SQLite.

## Consequences

Single-file database; no server to run.
EOF
out=$(bash "$DOC_LINT" "$adr_ok" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 27: doc-lint FAILs an ADR missing Date and Consequences... "
adr_bad=$(make_project "adr-bad")
mkdir -p "$adr_bad/docs/adr"
cat > "$adr_bad/docs/adr/0002-incomplete.md" <<'EOF'
# ADR 0002: Incomplete

- **Status:** Proposed

## Context

Something.

## Decision

Something else.
EOF
out=$(bash "$DOC_LINT" "$adr_bad" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '0002-incomplete.md' \
   && echo "$out" | grep -qi 'date' && echo "$out" | grep -qi 'consequences'; then pass; else
    fail "expected FAIL naming the ADR and the missing fields, got: $out"; fi

echo -n "Test 28: doc-lint accepts the legacy heading-style ADR (## Status / ## Date)... "
adr_legacy=$(make_project "adr-legacy")
mkdir -p "$adr_legacy/docs/adr"
cat > "$adr_legacy/docs/adr/0001-legacy.md" <<'EOF'
# ADR 0001: Legacy shape

## Status

Accepted

## Date

2025-12-22

## Context

Text.

## Decision

Text.

## Consequences

Text.
EOF
out=$(bash "$DOC_LINT" "$adr_legacy" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 29: doc-lint FAILs a broken relative Markdown link... "
link_bad=$(make_project "link-bad")
mkdir -p "$link_bad/docs/guides"
printf '# Guide\n\nSee [the spec](../specs/missing-spec.md) and [home](../../README.md).\n' \
    > "$link_bad/docs/guides/intro.md"
echo "# Project" > "$link_bad/README.md"
out=$(bash "$DOC_LINT" "$link_bad" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing-spec.md'; then pass; else
    fail "expected FAIL naming missing-spec.md, got: $out"; fi

echo -n "Test 30: doc-lint resolves good relative links; ignores URLs, anchors, and code... "
link_ok=$(make_project "link-ok")
mkdir -p "$link_ok/docs/specs" "$link_ok/docs/guides"
echo "# Spec" > "$link_ok/docs/specs/2026-10-17-topic-design.md"
cat > "$link_ok/docs/guides/intro.md" <<'EOF'
# Guide

See [the spec](../specs/2026-10-17-topic-design.md#purpose), the [README](../../README.md "Project README"),
[GitHub](https://github.com/example/repo), [mail](mailto:dev@example.com), [section](#heading),
[site page](/docs/absolute/), and the [specs dir](../specs/).

```markdown
[placeholder](../does-not-exist.md)
```

Inline code `[also-placeholder](./nope.md)` is ignored too.

[ref-style]: ../specs/2026-10-17-topic-design.md
EOF
echo "# Project" > "$link_ok/README.md"
out=$(bash "$DOC_LINT" "$link_ok" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 31: doc-lint parses destinations with balanced parens and <angle> spaces... "
link_cm=$(make_project "link-commonmark")
mkdir -p "$link_cm/docs"
echo "# API v2" > "$link_cm/docs/API_(v2).md"
echo "# Guide" > "$link_cm/docs/my file.md"
cat > "$link_cm/docs/index.md" <<'EOF'
# Index

See [api](API_(v2).md), [guide](<my file.md>), [titled](<my file.md> "Guide title")
and [both](API_(v2).md "API title") plus ![img](<my file.md>).

[ref-angle]: <my file.md>
[ref-paren]: API_(v2).md
EOF
out=$(bash "$DOC_LINT" "$link_cm" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 32: doc-lint tracks fence delimiter/length so a nested shorter fence is content... "
link_fence=$(make_project "link-fence")
mkdir -p "$link_fence/docs"
cat > "$link_fence/docs/fences.md" <<'EOF'
# Fences

````markdown
```md
[placeholder](../does-not-exist.md)
```
[still inside the outer fence](./nope.md)
````

~~~
[tilde fence](./also-nope.md)
```
[backticks inside tildes do not close it](./nope-again.md)
~~~

Back to prose: [real](./fences.md).
EOF
out=$(bash "$DOC_LINT" "$link_fence" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 33: doc-lint FAILs an ADR whose Status/Date bullets are empty or not ISO... "
adr_empty=$(make_project "adr-empty")
mkdir -p "$adr_empty/docs/adr"
cat > "$adr_empty/docs/adr/0003-empty-meta.md" <<'EOF'
# ADR 0003: Empty metadata

- **Status:**
- **Date:** TBD

## Context

Text.

## Decision

Text.

## Consequences

Text.
EOF
out=$(bash "$DOC_LINT" "$adr_empty" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '0003-empty-meta.md' \
   && echo "$out" | grep -q 'Status' && echo "$out" | grep -q 'Date'; then pass; else
    fail "expected FAIL naming Status and Date, got: $out"; fi

echo -n "Test 34: doc-lint exempts only the ADR template file, not a decision about templates... "
adr_tpl=$(make_project "adr-template")
mkdir -p "$adr_tpl/docs/adr"
printf '# ADR NNNN: Title\n\n- **Status:** Proposed\n- **Date:** YYYY-MM-DD\n' > "$adr_tpl/docs/adr/template.md"
printf '# ADR 0000: Template\n' > "$adr_tpl/docs/adr/0000-template.md"
printf '# ADR 0007: Select template engine\n\nNo metadata, no sections.\n' \
    > "$adr_tpl/docs/adr/0007-select-template-engine.md"
out=$(bash "$DOC_LINT" "$adr_tpl" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '0007-select-template-engine.md' \
   && ! echo "$out" | grep -q 'template.md (' && echo "$out" | grep -q '^FAIL doc-lint 1 ADR'; then pass; else
    fail "expected exactly one FAIL for 0007-select-template-engine.md, got: $out"; fi

echo -n "Test 35: doc-lint checks Markdown files with non-ASCII names (core.quotePath)... "
link_utf=$(make_project "link-utf8")
mkdir -p "$link_utf/docs"
printf '# 日本語\n\nSee [missing](./missing-ü.md).\n' > "$link_utf/docs/日本語.md"
out=$(bash "$DOC_LINT" "$link_utf" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '日本語.md'; then pass; else
    fail "expected FAIL naming 日本語.md, got: $out"; fi

echo -n "Test 36: doc-lint honours CommonMark escapes, code spans, footnotes and 3-space fences... "
link_cm2=$(make_project "link-commonmark2")
mkdir -p "$link_cm2/docs"
echo "# API v2" > "$link_cm2/docs/API_(v2).md"
echo "# Hash" > "$link_cm2/docs/a#b.md"
cat > "$link_cm2/docs/index.md" <<'EOF'
# Index

Escaped destination [api](API_\(v2\).md) and escaped fragment [hash](a\#b.md).
Escaped opener \[label](not-a-link.md) renders literally, as does \[x\](nope.md).
Multi-backtick span ``[example](missing.md)`` and ``` `` [nested](also-missing.md) `` ``` are code.
Literal backtick \` then [real](index.md) still parsed.

   ```md
   [inside a 3-space-indented fence](fenced-nope.md)
   ```

[^1]: A footnote definition is not a reference link.
[ref]: API_\(v2\).md
EOF
out=$(bash "$DOC_LINT" "$link_cm2" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 37: doc-lint FAILs a space-prefixed destination and sees past 4-space-indented backticks... "
link_cm3=$(make_project "link-commonmark3")
mkdir -p "$link_cm3/docs"
cat > "$link_cm3/docs/index.md" <<'EOF'
# Index

A link with [space before the target]( missing.md) must still be checked.

    ```
Four spaces of indentation is indented code, not a fence opener, so this
[prose link after it](after-indent.md) is still linted.
EOF
out=$(bash "$DOC_LINT" "$link_cm3" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md' \
   && echo "$out" | grep -q 'after-indent.md' && echo "$out" | grep -q '2 broken'; then pass; else
    fail "expected FAIL naming missing.md and after-indent.md (2 broken), got: $out"; fi

echo -n "Test 38: doc-lint accepts ADR headings indented up to three spaces... "
adr_ind=$(make_project "adr-indented")
mkdir -p "$adr_ind/docs/adr"
cat > "$adr_ind/docs/adr/0004-indented.md" <<'EOF'
# ADR 0004: Indented headings

- **Status:** Rejected
- **Date:** 2026-10-17

  ## Context

Text.

   ## Decision

Text.

 ## Consequences

Text.
EOF
out=$(bash "$DOC_LINT" "$adr_ind" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 39: doc-lint lints mixed-case .Md files too... "
link_case=$(make_project "link-mixed-case")
mkdir -p "$link_case/docs"
printf '# Guide\n\nSee [missing](./nowhere.md).\n' > "$link_case/docs/GUIDE.Md"
out=$(bash "$DOC_LINT" "$link_case" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'GUIDE.Md'; then pass; else
    fail "expected FAIL naming GUIDE.Md, got: $out"; fi

echo -n "Test 40: doc-lint ignores a complete ADR example inside a fenced block when validating structure... "
adr_fenced=$(make_project "adr-fenced-example")
mkdir -p "$adr_fenced/docs/adr"
cat > "$adr_fenced/docs/adr/0005-draft.md" <<'EOF'
# ADR 0005: Still a draft

Here is what a finished ADR looks like:

```markdown
- **Status:** Accepted
- **Date:** 2026-01-01

## Context

## Decision

## Consequences
```

    - **Status:** Accepted
    - **Date:** 2026-01-01
    ## Context
    ## Decision
    ## Consequences

The real document has none of those yet.
EOF
out=$(bash "$DOC_LINT" "$adr_fenced" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '0005-draft.md' \
   && echo "$out" | grep -q 'Status' && echo "$out" | grep -q 'Consequences'; then pass; else
    fail "expected FAIL naming 0005-draft.md with Status and Consequences, got: $out"; fi

echo -n "Test 41: doc-lint skips indented code blocks and decodes percent-encoded destinations... "
link_ind=$(make_project "link-indented")
mkdir -p "$link_ind/docs"
echo "# Hash" > "$link_ind/docs/a#b.md"
echo "# Space" > "$link_ind/docs/my file.md"
cat > "$link_ind/docs/index.md" <<'EOF'
# Index

An indented code block follows a blank line:

    [example](missing.md)
    [ref-example]: also-missing.md

	[tab-indented](missing-too.md)

Percent-encoded [hash](a%23b.md) and [space](my%20file.md) resolve.
EOF
out=$(bash "$DOC_LINT" "$link_ind" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 42: doc-lint still lints a 4-space line that continues a paragraph (lazy continuation)... "
link_lazy=$(make_project "link-lazy")
mkdir -p "$link_lazy/docs"
cat > "$link_lazy/docs/index.md" <<'EOF'
# Index

This paragraph continues on the next line
    [and this is not code](missing.md) because no blank line precedes it.
EOF
out=$(bash "$DOC_LINT" "$link_lazy" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md'; then pass; else
    fail "expected FAIL naming missing.md, got: $out"; fi

echo -n "Test 43: doc-lint lints a 4-space continuation paragraph inside a list item, skips deeper code... "
link_list=$(make_project "link-list-continuation")
mkdir -p "$link_list/docs"
cat > "$link_list/docs/index.md" <<'EOF'
# Index

- item one

    [continuation paragraph](missing.md) is list content, not code.

      [six spaces inside a list is code](ignored.md)

1. numbered

    [also continuation](missing-two.md)
EOF
out=$(bash "$DOC_LINT" "$link_list" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md' && echo "$out" | grep -q 'missing-two.md' \
   && echo "$out" | grep -q '2 broken'; then pass; else
    fail "expected FAIL with exactly missing.md and missing-two.md, got: $out"; fi

echo -n "Test 44: doc-lint treats fences inside block quotes as code and decodes entities, titles, double backslashes... "
link_bq=$(make_project "link-blockquote")
mkdir -p "$link_bq/docs"
echo "# Amp" > "$link_bq/docs/a&b.md"
echo "# Existing" > "$link_bq/docs/existing.md"
cat > "$link_bq/docs/index.md" <<'EOF'
# Index

> A quoted example:
>
> ```markdown
> [quoted fenced example](missing.md)
> ```
>
> [quoted prose link](existing.md)

Entity [amp](a&amp;b.md) and numeric [amp2](a&#38;b.md) and hex [amp3](a&#x26;b.md).

A title containing a paren: [valid](existing.md "title ) then [example](missing.md)") is one link.
Single quotes too: [valid2](existing.md 'another ) paren') and parens: [valid3](existing.md (a ) b)).
EOF
out=$(bash "$DOC_LINT" "$link_bq" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 45: doc-lint counts backslash parity: \\\\[label](x) is a real link... "
link_par=$(make_project "link-parity")
mkdir -p "$link_par/docs"
cat > "$link_par/docs/index.md" <<'EOF'
# Index

Two backslashes leave the bracket active: \\[label](missing.md).
One backslash escapes it: \[label](not-a-link.md).
EOF
out=$(bash "$DOC_LINT" "$link_par" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md' && echo "$out" | grep -q '1 broken'; then pass; else
    fail "expected FAIL naming only missing.md, got: $out"; fi

echo -n "Test 46: doc-lint rejects impossible calendar dates in ADRs and accepts leap days... "
adr_dates=$(make_project "adr-dates")
mkdir -p "$adr_dates/docs/adr"
printf '# ADR 0006: Bad date\n\n- **Status:** Accepted\n- **Date:** 2026-02-31\n\n## Context\n\n## Decision\n\n## Consequences\n' \
    > "$adr_dates/docs/adr/0006-bad-date.md"
printf '# ADR 0007: Leap day\n\n- **Status:** Accepted\n- **Date:** 2024-02-29\n\n## Context\n\n## Decision\n\n## Consequences\n' \
    > "$adr_dates/docs/adr/0007-leap.md"
out=$(bash "$DOC_LINT" "$adr_dates" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '0006-bad-date.md' && ! echo "$out" | grep -q '0007-leap.md' \
   && echo "$out" | grep -q 'Date'; then pass; else
    fail "expected FAIL naming only 0006-bad-date.md for Date, got: $out"; fi

echo -n "Test 47: doc-lint tracks nested list indentation so an 8-space continuation under a nested item is content... "
link_nest=$(make_project "link-nested-list")
mkdir -p "$link_nest/docs"
cat > "$link_nest/docs/index.md" <<'EOF'
# Index

- outer
    - inner

        [continuation of inner](missing.md) is content.

            [twelve spaces under inner is code](ignored.md)

- sibling

    [continuation of sibling](missing-two.md)

        [eight spaces under a top-level item is code](ignored-too.md)
EOF
out=$(bash "$DOC_LINT" "$link_nest" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md' && echo "$out" | grep -q 'missing-two.md' \
   && echo "$out" | grep -q '2 broken'; then pass; else
    fail "expected FAIL with exactly missing.md and missing-two.md, got: $out"; fi

echo -n "Test 48: doc-lint ignores multi-line code spans and HTML comments (single and multi-line)... "
link_span=$(make_project "link-span-comment")
mkdir -p "$link_span/docs"
echo "# Real" > "$link_span/docs/real.md"
cat > "$link_span/docs/index.md" <<'EOF'
# Index

A span that opens here `and
[continues](missing.md) on the next line
and closes` here; then a [real link](real.md).

<!-- [commented out](missing-two.md) -->

<!--
A multi-line comment with [a link](missing-three.md)
and [another](missing-four.md)
--> but [this one after it](real.md) counts.

An unmatched backtick ` does not swallow the next paragraph:

[after a blank line](real.md)
EOF
out=$(bash "$DOC_LINT" "$link_span" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 49: doc-lint ignores a commented-out ADR section when validating structure... "
adr_cmt=$(make_project "adr-comment")
mkdir -p "$adr_cmt/docs/adr"
cat > "$adr_cmt/docs/adr/0008-commented.md" <<'EOF'
# ADR 0008: Commented

- **Status:** Accepted
- **Date:** 2026-10-17

## Context

## Decision

<!-- ## Consequences -->
EOF
out=$(bash "$DOC_LINT" "$adr_cmt" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'Consequences'; then pass; else
    fail "expected FAIL naming Consequences, got: $out"; fi

echo -n "Test 50: doc-lint honours LINT_FILE_LIST (changed-file scope) and PASSes an empty scope... "
link_scope=$(make_project "link-scope")
mkdir -p "$link_scope/docs"
printf '# Old\n\n[pre-existing breakage](missing.md)\n' > "$link_scope/docs/old.md"
printf '# New\n\nAll good: [index](../README.md).\n' > "$link_scope/docs/new.md"
echo "# Project" > "$link_scope/README.md"
( cd "$link_scope" && git add -A && git -c user.email="t@t.local" -c user.name="T" commit -q -m "chore: files" )
out_full=$(bash "$DOC_LINT" "$link_scope" 2>/dev/null || true)
scope_list=$(mktemp "${TMP_BASE}/scope.XXXXXX")
printf 'docs/new.md\0README.md\0' > "$scope_list"
out_scoped=$(LINT_FILE_LIST="$scope_list" bash "$DOC_LINT" "$link_scope" 2>/dev/null || true)
printf 'Makefile\0' > "$scope_list"
out_empty=$(LINT_FILE_LIST="$scope_list" bash "$DOC_LINT" "$link_scope" 2>/dev/null || true)
if echo "$out_full" | grep -q '^FAIL' && echo "$out_full" | grep -q 'missing.md' \
   && echo "$out_scoped" | grep -q '^PASS' && echo "$out_scoped" | grep -q '2 Markdown' \
   && echo "$out_empty" | grep -q '^PASS' && echo "$out_empty" | grep -qi 'changed-file scope'; then pass; else
    fail "expected FAIL(full)/PASS(scoped, 2 files)/PASS(empty scope); got: [$out_full] [$out_scoped] [$out_empty]"; fi

echo -n "Test 51: doc-lint consumes a multi-line comment containing a fence opener and still lints after it... "
link_cf=$(make_project "link-comment-fence")
mkdir -p "$link_cf/docs"
cat > "$link_cf/docs/index.md" <<'EOF'
# Index

<!--
```md
-->

[active after the comment](missing.md)
EOF
out=$(bash "$DOC_LINT" "$link_cf" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md'; then pass; else
    fail "expected FAIL naming missing.md, got: $out"; fi

echo -n "Test 52: doc-lint reports a Markdown filename containing a newline instead of skipping it... "
link_nl=$(make_project "link-newline-name")
mkdir -p "$link_nl/docs"
echo "# Project" > "$link_nl/README.md"
printf '# Bad\n\n[broken](missing.md)\n' > "$link_nl/docs/bad"$'\n'"name.md"
out=$(bash "$DOC_LINT" "$link_nl" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'cannot be scanned' && echo "$out" | grep -q 'bad\\nname.md'; then pass; else
    fail "expected FAIL naming the newline filename, got: $out"; fi

echo -n "Test 53: doc-lint ignores a block-quoted ADR example when validating structure... "
adr_q=$(make_project "adr-quoted")
mkdir -p "$adr_q/docs/adr"
cat > "$adr_q/docs/adr/0011-quoted.md" <<'EOF'
# ADR 0011: Quoted example only

> - **Status:** Accepted
> - **Date:** 2026-10-17
>
> ## Context
>
> ## Decision
>
> ## Consequences

Nothing of its own yet.
EOF
out=$(bash "$DOC_LINT" "$adr_q" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q '0011-quoted.md' && echo "$out" | grep -q 'Status' \
   && echo "$out" | grep -q 'Consequences'; then pass; else
    fail "expected FAIL naming 0011-quoted.md with Status and Consequences, got: $out"; fi

echo -n "Test 54: doc-lint rejects links that climb above the project root but accepts ../ inside it... "
link_esc=$(make_project "link-escape")
mkdir -p "$link_esc/docs/deep"
echo "# Project" > "$link_esc/README.md"
cat > "$link_esc/docs/deep/index.md" <<'EOF'
# Deep

Inside: [root readme](../../README.md) and [docs dir](../).
Outside: [host file](../../../../../../../../etc/passwd) and [way up](../../../README.md).
EOF
out=$(bash "$DOC_LINT" "$link_esc" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'etc/passwd' && echo "$out" | grep -q '2 broken'; then pass; else
    fail "expected FAIL with exactly the two escaping links, got: $out"; fi

echo -n "Test 55: doc-lint treats an unmatched backtick as literal text and still lints the link after it... "
link_stray=$(make_project "link-stray-backtick")
mkdir -p "$link_stray/docs"
cat > "$link_stray/docs/index.md" <<'EOF'
# Index

A stray ` then [link](missing.md) on the same line,
and another ``` run with no close before [second](missing-two.md).
EOF
out=$(bash "$DOC_LINT" "$link_stray" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'missing.md' && echo "$out" | grep -q 'missing-two.md' \
   && echo "$out" | grep -q '2 broken'; then pass; else
    fail "expected FAIL with exactly missing.md and missing-two.md, got: $out"; fi

echo -n "Test 56: doc-lint FAILs closed on a project with no Markdown at all (proc-05 §7.2)... "
out=$(bash "$DOC_LINT" "$proj" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'No Markdown files matched'; then pass; else
    fail "expected FAIL naming the empty scan, got: $out"; fi

# --- Sibling scripts smoke --------------------------------------------------

echo -n "Test 57: diff-standards.sh runs on a project without .standards.yml... "
if bash "$REPO_ROOT/scripts/diff-standards.sh" "$proj" >/dev/null 2>&1; then pass; else
    # diff-standards may exit non-zero; accept as long as it doesn't crash hard (>1)
    rc=$?; if [ "$rc" -le 1 ]; then pass; else fail "diff-standards crashed (exit $rc)"; fi
fi

echo -n "Test 58: doctor.sh runs without a hard crash... "
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

echo -n "Test 91: STANDARDS_COMMITS_SINCE (PR range) beats commits.window... "
# With commits.window pinned, the module must still report "commits since
# cc-base" (the CI PR range), not "commits (window 1)".
printf 'version: 1\ncommits:\n  window: 1\n' > "$win/.standards.yml"
out=$(cd "$win" && STANDARDS_COMMITS_SINCE=cc-base bash "$CC_MOD" "$win" 2>/dev/null || true)
if echo "$out" | grep -q 'since cc-base' && echo "$out" | grep -qE '^(WARN|FAIL)'; then pass; else
    fail "expected the PR range to win over commits.window, got: $out"; fi
rm -f "$win/.standards.yml"

echo -n "Test 92: commits.since beats STANDARDS_COMMITS_SINCE... "
( cd "$win" && git tag cc-head HEAD )
printf 'version: 1\ncommits:\n  since: cc-head\n' > "$win/.standards.yml"
out=$(cd "$win" && STANDARDS_COMMITS_SINCE=cc-base bash "$CC_MOD" "$win" 2>/dev/null || true)
if echo "$out" | grep -q 'cc-head'; then pass; else fail "expected commits.since to win, got: $out"; fi
rm -f "$win/.standards.yml"

echo -n "Test 93: single-quoted YAML scalars are parsed (window: '5', since: 'ref')... "
printf "version: 1\ncommits:\n  window: '5'\n" > "$win/.standards.yml"
out1=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
printf "version: 1\ncommits:\n  since: 'cc-base'\n" > "$win/.standards.yml"
out2=$(bash "$CC_MOD" "$win" 2>/dev/null || true)
rm -f "$win/.standards.yml"
if echo "$out1" | grep -q 'window 5' && echo "$out2" | grep -q 'since cc-base'; then pass; else
    fail "quoted scalars not parsed: [$out1] [$out2]"; fi

echo -n "Test 94: a scope containing whitespace cannot match two allow-list entries... "
printf 'version: 1\ncommits:\n  scopes: [api, domain]\n' > "$sc/.standards.yml"
if ! bash "$CHK" --project-root "$sc" "feat(api domain): bypass" >/dev/null 2>&1; then pass; else
    fail "'api domain' was accepted against [api, domain]"; fi

echo -n "Test 95: check-commit-message.sh --no-exempt rejects merge/fixup/revert-style titles... "
if ! bash "$CHK" --no-exempt "Merge branch 'topic'" >/dev/null 2>&1 \
   && ! bash "$CHK" --no-exempt "fixup! feat: wip" >/dev/null 2>&1 \
   && ! bash "$CHK" --no-exempt 'Revert "feat: thing"' >/dev/null 2>&1 \
   && bash "$CHK" --no-exempt 'revert: "feat: thing"' >/dev/null 2>&1; then pass; else
    fail "--no-exempt did not reject exempt-style subjects"; fi

echo -n "Test 96: doctor.sh warns when lefthook.yml exists but hooks are not installed... "
out=$(cd "$lh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'not installed'; then pass; else
    fail "expected 'not installed' WARN: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 97: doctor.sh passes once lefthook hooks are installed (core.hooksPath set)... "
mkdir -p "$lh/.lefthook-hooks"
printf '#!/bin/sh\n# lefthook\n' > "$lh/.lefthook-hooks/commit-msg"
( cd "$lh" && git config core.hooksPath .lefthook-hooks )
out=$(cd "$lh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'hooks installed' && ! echo "$out" | grep 'Git Hooks' | grep -q 'not installed'; then pass; else
    fail "expected installed PASS: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 98: block-form commits.scopes survives blank and comment lines... "
printf 'version: 1\ncommits:\n  scopes:\n    # core areas\n    - api\n\n    # shared kernel\n    - domain\n' > "$sc/.standards.yml"
if bash "$CHK" --project-root "$sc" "feat(domain): after a comment line" >/dev/null 2>&1 \
   && ! bash "$CHK" --project-root "$sc" "feat(web): still enforced" >/dev/null 2>&1; then pass; else
    fail "block list truncated or emptied by comment/blank lines"; fi

echo -n "Test 99: doctor.sh does not credit lefthook for a core.hooksPath owned by another manager... "
mkdir -p "$lh2/.husky/_"
( cd "$lh2" && git config core.hooksPath .husky/_ )
out=$(cd "$lh2" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'lefthook hooks are not installed'; then pass; else
    fail "expected lefthook 'not installed' with husky hooksPath: $(echo "$out" | grep 'Git Hooks')"; fi

echo -n "Test 100: doctor.sh requires a native commit-msg hook to be executable... "
printf '#!/bin/sh\nexit 0\n' > "$nh/.git/hooks/commit-msg"
chmod -x "$nh/.git/hooks/commit-msg"
out1=$(cd "$nh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
chmod +x "$nh/.git/hooks/commit-msg"
out2=$(cd "$nh" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out1" | grep 'Git Hooks' | grep -q 'not executable' && echo "$out2" | grep 'Git Hooks' | grep -q 'commit-msg hook installed'; then pass; else
    fail "executable-bit check wrong: [$(echo "$out1" | grep commit-msg)] [$(echo "$out2" | grep commit-msg)]"; fi

echo -n "Test 101: doctor.sh reads native hooks from core.hooksPath when it is set... "
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

echo -n "Test 102: doctor.sh requires the lefthook post-merge block to run the standards sync... "
lh3=$(make_project "doctor-lefthook-postmerge")
printf 'post-merge:\n  commands:\n    notify:\n      run: echo merged\n' > "$lh3/lefthook.yml"
out=$(cd "$lh3" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
printf 'post-merge:\n  commands:\n    standards-sync-reminder:\n      run: make check-standards\n' > "$lh3/lefthook.yml"
out2=$(cd "$lh3" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Git Hooks' | grep -q 'does not run the standards sync' \
   && echo "$out2" | grep 'Git Hooks' | grep -q 'post-merge hook contains standards sync'; then pass; else
    fail "lefthook post-merge content check wrong: [$(echo "$out" | grep post-merge)] [$(echo "$out2" | grep post-merge)]"; fi

echo -n "Test 103: commits with an empty subject (--allow-empty-message) count as violations... "
em=$(make_project "cc-empty-subject")
( cd "$em" && git -c user.email="t@t.local" -c user.name="T" commit -q --allow-empty --allow-empty-message -m "" )
out=$(bash "$CC_MOD" "$em" 2>/dev/null || true)
if echo "$out" | grep -qE '^(WARN|FAIL) conventional-commits 1 of 2' && echo "$out" | grep -q 'empty subject'; then pass; else
    fail "empty subject not counted: $out"; fi

echo -n "Test 104: check-commit-message.sh honours core.commentChar when stripping comment lines... "
cc=$(make_project "cc-commentchar")
( cd "$cc" && git config core.commentChar ';' && git config commit.cleanup strip )
printf '; Please enter the commit message\nfeat(api): after a custom comment line\n' > "$TMP_BASE/msg-cc"
printf '# not a comment with commentChar=;\n' > "$TMP_BASE/msg-cc2"
if bash "$CHK" --project-root "$cc" --file "$TMP_BASE/msg-cc" >/dev/null 2>&1 \
   && ! bash "$CHK" --project-root "$cc" --file "$TMP_BASE/msg-cc2" >/dev/null 2>&1; then pass; else
    fail "core.commentChar not honoured"; fi

echo -n "Test 105: check-commit-message.sh strips '#' lines only under commit.cleanup=strip... "
vb=$(make_project "cc-verbatim")
( cd "$vb" && git config commit.cleanup verbatim )
st=$(make_project "cc-strip")
( cd "$st" && git config commit.cleanup strip )
printf '# this line is kept unless cleanup is strip\nfeat: decoy\n' > "$TMP_BASE/msg-vb"
# verbatim keeps the '#' line (reject); explicit strip drops it (accept); with
# cleanup unset git strips in editor mode (accept) but keeps for -m/-F, which
# hooks see as GIT_EDITOR=: (reject).
if ! bash "$CHK" --project-root "$vb" --file "$TMP_BASE/msg-vb" >/dev/null 2>&1 \
   && bash "$CHK" --project-root "$st" --file "$TMP_BASE/msg-vb" >/dev/null 2>&1 \
   && env -u GIT_EDITOR bash "$CHK" --project-root "$em" --file "$TMP_BASE/msg-vb" >/dev/null 2>&1 \
   && ! env GIT_EDITOR=: bash "$CHK" --project-root "$em" --file "$TMP_BASE/msg-vb" >/dev/null 2>&1; then pass; else
    fail "commit.cleanup handling wrong"; fi

echo -n "Test 106: check-commit-message.sh never strips lines under core.commentChar=auto... "
au=$(make_project "cc-auto")
( cd "$au" && git config core.commentChar auto && git config commit.cleanup strip )
# git's auto choice cannot be reconstructed from the file, so a leading
# comment-looking line is judged as the subject (reject) rather than skipped
# in favour of a later line.
printf '# user heading, not a comment\nfeat: decoy\n; Please enter the commit message\n;\n' > "$TMP_BASE/msg-auto1"
# A conventional first line passes regardless of the help lines below it.
printf 'feat(auto): ok\n# Please enter the commit message\n#\n' > "$TMP_BASE/msg-auto2"
if ! bash "$CHK" --project-root "$au" --file "$TMP_BASE/msg-auto1" >/dev/null 2>&1 \
   && bash "$CHK" --project-root "$au" --file "$TMP_BASE/msg-auto2" >/dev/null 2>&1; then pass; else
    fail "commentChar=auto not handled conservatively"; fi

echo -n "Test 107: conventional-commits rejects empty or zero --since / --window operands (exit 2)... "
bash "$CC_MOD" --since "" "$win" >/dev/null 2>&1; rc1=$?
bash "$CC_MOD" --window "" "$win" >/dev/null 2>&1; rc2=$?
bash "$CC_MOD" --window 0 "$win" >/dev/null 2>&1; rc3=$?
if [ "$rc1" -eq 2 ] && [ "$rc2" -eq 2 ] && [ "$rc3" -eq 2 ]; then pass; else fail "expected exit 2, got $rc1/$rc2/$rc3"; fi

echo -n "Test 108: check-commit-message.sh honours multi-character core.commentString... "
cs=$(make_project "cc-commentstring")
( cd "$cs" && git config core.commentString '//' && git config commit.cleanup strip )
printf '// Please enter the commit message\nfeat(cs): after a // help line\n' > "$TMP_BASE/msg-cs"
if bash "$CHK" --project-root "$cs" --file "$TMP_BASE/msg-cs" >/dev/null 2>&1; then pass; else
    fail "core.commentString not honoured"; fi

echo -n "Test 109: check-commit-message.sh keeps leading whitespace of a stored subject (but trims PR titles)... "
printf '  feat: indented subject is stored indented\n' > "$TMP_BASE/msg-indent"
if ! bash "$CHK" --project-root "$st" --file "$TMP_BASE/msg-indent" >/dev/null 2>&1 \
   && bash "$CHK" --no-exempt "  feat: padded PR title  " >/dev/null 2>&1; then pass; else
    fail "leading whitespace handling wrong"; fi

echo -n "Test 110: a control character in a bad subject does not break --format json... "
cj=$(make_project "cc-json")
cc_commit "$cj" "$(printf 'bad\tsubject with tab')"
"$LINT" --format json "$cj" > "$TMP_BASE/cc-json.out" 2>/dev/null || true
if json_valid "$TMP_BASE/cc-json.out"; then pass; else fail "JSON output invalid: $(head -c 300 "$TMP_BASE/cc-json.out")"; fi

# --- File enumeration (#180) ------------------------------------------------
# A valid-length AWS access key id (AKIA + 16 chars), assembled at runtime so no
# key-shaped literal is committed to trip secret scanners.
aws_key="AKIA$(printf '%s' 'IOSFODNN7EXAMPLE')"

git_commit_all() {
    ( cd "$1" && git add -A && git -c user.email="t@t.local" -c user.name="T" \
        commit -q -m "${2:-feat: fixture}" )
}

echo -n "Test 111: no-secrets skips worktree/cache dirs in a git repo (untracked, not ignored)... "
wt=$(make_project "worktree-skip")
mkdir -p "$wt/.claude/worktrees/agent-1" "$wt/.worktrees/agent-2" "$wt/target/debug"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$wt/.claude/worktrees/agent-1/config.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$wt/.worktrees/agent-2/config.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$wt/target/debug/config.py"
echo "print('ok')" > "$wt/app.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$wt" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 112: no-secrets skips .worktrees/ outside a git repo (find fallback)... "
nogit="$TMP_BASE/no-git"
mkdir -p "$nogit/.worktrees/agent-1" "$nogit/DerivedData/x" "$nogit/src"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$nogit/.worktrees/agent-1/config.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$nogit/DerivedData/x/config.py"
echo "print('ok')" > "$nogit/src/app.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$nogit" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 113: no-secrets honours .gitignore (ignored path is never scanned)... "
ign=$(make_project "gitignored")
mkdir -p "$ign/generated"
echo "generated/" > "$ign/.gitignore"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$ign/generated/config.py"
echo "print('ok')" > "$ign/app.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$ign" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 114: no-secrets still flags a secret in an untracked, not-ignored file... "
ut=$(make_project "untracked-secret")
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$ut/config.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$ut" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 115: typescript/banned-functions skips docs/ mockups by default... "
docs=$(make_project "docs-mockup")
mkdir -p "$docs/docs/design/wireframes" "$docs/src"
echo 'el.innerHTML = "<b>mock</b>";' > "$docs/docs/design/wireframes/mock.js"
echo 'export const x = 1;' > "$docs/src/index.ts"
out=$(bash "$CHECKS/typescript/banned-functions.sh" "$docs" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 116: typescript/banned-functions still flags innerHTML in src/ and names the file... "
echo 'el.innerHTML = user;' > "$docs/src/bad.ts"
out=$(bash "$CHECKS/typescript/banned-functions.sh" "$docs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'src/bad.ts'; then pass; else fail "expected FAIL naming src/bad.ts, got: $out"; fi

echo -n "Test 117: python/banned-functions honours lint.exclude (prefix, trailing **, and **/ matching zero segments)... "
excl=$(make_project "lint-exclude")
mkdir -p "$excl/skills" "$excl/fixtures/sub"
printf 'version: 1\nlanguages:\n  - python\nlint:\n  exclude:\n    - skills/\n    - fixtures/**\n    - "**/*_gen.py"\n' > "$excl/.standards.yml"
echo 'eval("1+1")' > "$excl/skills/smoke.py"
echo 'eval("1+1")' > "$excl/fixtures/sub/gen.py"
echo 'eval("1+1")' > "$excl/fixtures/gen.py"
echo 'eval("1+1")' > "$excl/top_gen.py"     # "**/" must match zero segments
echo 'print("ok")' > "$excl/app.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$excl" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 118: no-secrets IGNORES lint.exclude (an excluded path cannot hide a tracked secret)... "
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$excl/skills/creds.py"
git_commit_all "$excl" "feat: fixtures"
out=$(bash "$CHECKS/common/no-secrets.sh" "$excl" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'skills/creds.py'; then pass; else fail "expected FAIL naming skills/creds.py, got: $out"; fi

echo -n "Test 119: no-secrets scans TRACKED files under built-in excluded dirs (vendor/)... "
vend=$(make_project "tracked-vendor")
mkdir -p "$vend/vendor/lib"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$vend/vendor/lib/config.py"
echo "print('ok')" > "$vend/app.py"
git_commit_all "$vend"
out=$(bash "$CHECKS/common/no-secrets.sh" "$vend" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'vendor/lib/config.py'; then pass; else fail "expected FAIL naming vendor/lib/config.py, got: $out"; fi

echo -n "Test 120: test-directory does not accept Tests/ for tests/ (case-sensitive)... "
cs=$(make_project "case-sensitive")
mkdir -p "$cs/Tests"
echo "x" > "$cs/Tests/ExampleTests.swift"
out=$(bash "$CHECKS/common/test-directory-structure.sh" "$cs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL'; then pass; else fail "expected FAIL, got: $out"; fi

echo -n "Test 121: test-directory accepts an exact-case tests/ directory... "
# Fresh project: on a case-insensitive filesystem Tests/ and tests/ would be
# the same directory, so the two cases cannot share a fixture.
cs2=$(make_project "case-exact")
mkdir -p "$cs2/tests"
echo "def test_x(): pass" > "$cs2/tests/test_x.py"
out=$(bash "$CHECKS/common/test-directory-structure.sh" "$cs2" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

# --- Path and suppression safety (security review) --------------------------

echo -n "Test 122: python/banned-functions flags a file whose NAME contains ':1:#' (anchored suppression)... "
odd=$(make_project "odd-names")
mkdir -p "$odd/src"
echo 'eval(user_input)' > "$odd/src/weird:1:#.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$odd" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -qF 'weird:1:#.py'; then pass; else fail "expected FAIL naming weird:1:#.py, got: $out"; fi

echo -n "Test 123: python/banned-functions: trailing '# :1: #' does not suppress; a real comment line does... "
odd2=$(make_project "odd-content")
printf 'eval(x)  # :1: #\n' > "$odd2/a.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$odd2" 2>/dev/null || true)
printf '# eval(x) is banned\nprint("ok")\n' > "$odd2/a.py"
out2=$(bash "$CHECKS/python/banned-functions.sh" "$odd2" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out2" | grep -q '^PASS'; then pass; else fail "inline='$out' comment='$out2'"; fi

echo -n "Test 124: typescript/banned-functions flags a file whose NAME contains ':1:*' (anchored suppression)... "
echo 'eval(user)' > "$odd/src/weird:1:*.ts"
out=$(bash "$CHECKS/typescript/banned-functions.sh" "$odd" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -qF 'weird:1:*.ts'; then pass; else fail "expected FAIL naming weird:1:*.ts, got: $out"; fi

echo -n "Test 125: no-secrets reports (not skips) a file whose name contains a newline... "
nl=$(make_project "newline-name")
echo "print('ok')" > "$nl/app.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$nl/odd"$'\n'"name.py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$nl" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'not scanned'; then pass; else fail "expected FAIL with 'not scanned', got: $out"; fi

echo -n "Test 126: no-secrets handles spaces and quotes in filenames exactly... "
sp=$(make_project "space-names")
mkdir -p "$sp/my dir"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$sp/my dir/it's \"config\".py"
out=$(bash "$CHECKS/common/no-secrets.sh" "$sp" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -qF "my dir/it's"; then pass; else fail "expected FAIL naming the file, got: $out"; fi

echo -n "Test 127: a newline-named file under an EXCLUDED path is not reported (docs/ for banned-functions, .worktrees/ for no-secrets)... "
# Two fixtures: no-secrets is strict and does scan docs/, so the docs/ case
# only applies to the per-check docs exclusion of banned-functions.
nx=$(make_project "newline-excluded-docs")
mkdir -p "$nx/docs"
echo "print('ok')" > "$nx/app.py"
echo 'eval("1")' > "$nx/docs/odd"$'\n'"mock.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$nx" 2>/dev/null || true)
nx2=$(make_project "newline-excluded-worktree")
mkdir -p "$nx2/.worktrees/a"
echo "print('ok')" > "$nx2/app.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$nx2/.worktrees/a/odd"$'\n'"creds.py"
out2=$(bash "$CHECKS/common/no-secrets.sh" "$nx2" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out2" | grep -q '^PASS'; then pass; else fail "banned='$out' secrets='$out2'"; fi

echo -n "Test 128: lint.exclude keeps a '#' inside a quoted value (\"gen#tmp/\" excludes gen#tmp/, not gen/)... "
hx=$(make_project "hash-exclude")
mkdir -p "$hx/gen#tmp" "$hx/gen"
printf 'version: 1\nlanguages:\n  - python\nlint:\n  exclude:\n    - "gen#tmp/"\n    - skills/   # trailing comment is still stripped\n' > "$hx/.standards.yml"
echo 'eval("1")' > "$hx/gen#tmp/x.py"
echo 'print("ok")' > "$hx/gen/ok.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$hx" 2>/dev/null || true)
echo 'eval("1")' > "$hx/gen/bad.py"
out2=$(bash "$CHECKS/python/banned-functions.sh" "$hx" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out2" | grep -q '^FAIL' && echo "$out2" | grep -q 'gen/bad.py'; then pass; else
    fail "excluded='$out' then='$out2'"; fi

echo -n "Test 129: a tracked symlink to a file outside the project is not scanned... "
sl=$(make_project "symlink")
mkdir -p "$TMP_BASE/outside"
echo 'eval("1")' > "$TMP_BASE/outside/evil.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$TMP_BASE/outside/creds.py"
echo "print('ok')" > "$sl/app.py"
ln -s "$TMP_BASE/outside/evil.py" "$sl/link.py"
ln -s "$TMP_BASE/outside/creds.py" "$sl/creds_link.py"
git_commit_all "$sl" "feat: links"
out=$(bash "$CHECKS/python/banned-functions.sh" "$sl" 2>/dev/null || true)
out2=$(bash "$CHECKS/common/no-secrets.sh" "$sl" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS' && echo "$out2" | grep -q '^PASS'; then pass; else fail "banned='$out' secrets='$out2'"; fi

# --- Runner: --since / --changed and --timeout (#180) -----------------------

# Extract the status of one check from the runner's JSON output.
json_check_status() {
    tr -d '\n' | grep -o "\"status\": \"[A-Z]*\",[[:space:]]*\"check\": \"$1\"" | head -1 | grep -o '"[A-Z]*"' | head -1 | tr -d '"'
}

echo -n "Test 130: --since <ref> scans only files changed since the ref... "
ch=$(make_project "changed-mode")
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$ch/legacy.py"
git_commit_all "$ch" "feat: legacy"
base=$(cd "$ch" && git rev-parse HEAD)
echo "print('new')" > "$ch/new.py"
git_commit_all "$ch" "feat: new file"
full_status=$("$LINT" --format json "$ch" 2>/dev/null | json_check_status no-secrets)
since_status=$("$LINT" --format json --since "$base" "$ch" 2>/dev/null | json_check_status no-secrets)
if [ "$full_status" = "FAIL" ] && [ "$since_status" = "PASS" ]; then pass; else
    fail "full='$full_status' since='$since_status'"; fi

echo -n "Test 131: --since still scans an untracked (new, uncommitted) file... "
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$ch/wip.py"
since_status=$("$LINT" --format json --since "$base" "$ch" 2>/dev/null | json_check_status no-secrets)
rm -f "$ch/wip.py"
if [ "$since_status" = "FAIL" ]; then pass; else fail "since='$since_status'"; fi

echo -n "Test 132: --since with a project root that is a SUBDIRECTORY of the repo finds its changed files... "
mono=$(make_project "monorepo")
mkdir -p "$mono/app"
echo "print('ok')" > "$mono/app/ok.py"
git_commit_all "$mono" "feat: app"
mbase=$(cd "$mono" && git rev-parse HEAD)
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$mono/app/bad.py"
git_commit_all "$mono" "feat: bad"
out=$("$LINT" --format json --since "$mbase" "$mono/app" 2>/dev/null || true)
if [ "$(echo "$out" | json_check_status no-secrets)" = "FAIL" ] && echo "$out" | grep -q 'bad.py'; then pass; else
    fail "status=$(echo "$out" | json_check_status no-secrets) out=$out"; fi

echo -n "Test 133: --since scopes go/error-handling and rust/ffi-no-unwrap too (pre-existing findings are out of scope)... "
gr=$(make_project "go-rust-scope")
mkdir -p "$gr/src"
printf 'version: 1\nlanguages:\n  - go\n  - rust\n' > "$gr/.standards.yml"
printf 'package main\nfunc main() {\n\t_ = run()\n}\n' > "$gr/main.go"
printf 'pub extern "C" fn f() { x.unwrap(); }\n' > "$gr/src/ffi.rs"
git_commit_all "$gr" "feat: legacy"
gbase=$(cd "$gr" && git rev-parse HEAD)
echo "// new" > "$gr/new.go"
git_commit_all "$gr" "feat: new"
full=$("$LINT" --format json "$gr" 2>/dev/null || true)
since=$("$LINT" --format json --since "$gbase" "$gr" 2>/dev/null || true)
if [ "$(echo "$full" | json_check_status go/error-handling)" = "WARN" ] \
   && [ "$(echo "$full" | json_check_status rust/ffi-no-unwrap)" = "FAIL" ] \
   && [ "$(echo "$since" | json_check_status go/error-handling)" = "PASS" ] \
   && [ "$(echo "$since" | json_check_status rust/ffi-no-unwrap)" = "PASS" ]; then pass; else
    fail "full go=$(echo "$full" | json_check_status go/error-handling) rust=$(echo "$full" | json_check_status rust/ffi-no-unwrap); since go=$(echo "$since" | json_check_status go/error-handling) rust=$(echo "$since" | json_check_status rust/ffi-no-unwrap)"; fi

echo -n "Test 134: go/error-handling skips untracked worktrees and honours lint.exclude... "
mkdir -p "$gr/.worktrees/a" "$gr/gen"
printf 'package w\nfunc g() { _ = run() }\n' > "$gr/.worktrees/a/w.go"
printf 'package g\nfunc g() { _ = run() }\n' > "$gr/gen/g.go"
printf 'version: 1\nlanguages:\n  - go\nlint:\n  exclude:\n    - gen/\n' > "$gr/.standards.yml"
( cd "$gr" && git rm -q --cached main.go && rm -f main.go )
out=$(bash "$CHECKS/go/error-handling.sh" "$gr" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 135: --changed with no base branch falls back to a full scan without crashing... "
# Rename the only branch so none of the auto-detected bases (origin/HEAD,
# origin/main, origin/master, main, master) exist.
( cd "$ch" && git branch -m feature/no-base )
"$LINT" --format json --changed "$ch" > "$TMP_BASE/changed.json" 2>/dev/null; rc=$?
if [ "$rc" -le 1 ] && json_valid "$TMP_BASE/changed.json" \
   && [ "$(json_check_status no-secrets < "$TMP_BASE/changed.json")" = "FAIL" ]; then pass; else
    fail "exit $rc / invalid JSON / status=$(json_check_status no-secrets < "$TMP_BASE/changed.json")"; fi

echo -n "Test 136: --timeout guards a hung check and reports WARN... "
slow_checks="$TMP_BASE/slow-checks/common"
mkdir -p "$slow_checks"
printf '#!/bin/bash\nsleep 30\necho "PASS slow never gets here"\n' > "$slow_checks/slow.sh"
chmod +x "$slow_checks/slow.sh"
start=$(date +%s)
out=$(LINT_CHECKS_DIR="$TMP_BASE/slow-checks" "$LINT" --format json --timeout 1 "$proj" 2>/dev/null || true)
elapsed=$(( $(date +%s) - start ))
if [ "$(echo "$out" | json_check_status slow)" = "WARN" ] && echo "$out" | grep -qi 'timed out' \
   && [ "$elapsed" -lt 10 ]; then pass; else fail "elapsed=${elapsed}s out=$out"; fi

echo -n "Test 137: a timed-out SECURITY check is FAIL, and --fail-on-timeout makes every timeout FAIL... "
sec_checks="$TMP_BASE/sec-checks/common"
mkdir -p "$sec_checks"
cp "$slow_checks/slow.sh" "$sec_checks/no-secrets.sh"
sec_status=$(LINT_CHECKS_DIR="$TMP_BASE/sec-checks" "$LINT" --format json --timeout 1 "$proj" 2>/dev/null | json_check_status no-secrets)
strict_status=$(LINT_CHECKS_DIR="$TMP_BASE/slow-checks" "$LINT" --format json --timeout 1 --fail-on-timeout "$proj" 2>/dev/null | json_check_status slow)
if [ "$sec_status" = "FAIL" ] && [ "$strict_status" = "FAIL" ]; then pass; else
    fail "security='$sec_status' fail-on-timeout='$strict_status'"; fi

echo -n "Test 138: --timeout escalates to SIGKILL for a check that ignores SIGTERM (no survivors)... "
stub_checks="$TMP_BASE/stubborn-checks/common"
mkdir -p "$stub_checks"
printf '#!/bin/bash\ntrap "" TERM\nsleep 30\necho "PASS stubborn never gets here"\n' > "$stub_checks/stubborn.sh"
chmod +x "$stub_checks/stubborn.sh"
start=$(date +%s)
out=$(LINT_CHECKS_DIR="$TMP_BASE/stubborn-checks" "$LINT" --format json --timeout 1 "$proj" 2>/dev/null || true)
elapsed=$(( $(date +%s) - start ))
leftover=$(pgrep -f "$stub_checks/stubborn.sh" 2>/dev/null | wc -l | tr -d ' ')
if [ "$(echo "$out" | json_check_status stubborn)" = "WARN" ] && [ "$elapsed" -lt 10 ] && [ "$leftover" -eq 0 ]; then pass; else
    fail "elapsed=${elapsed}s leftover=$leftover out=$out"; fi

# --- Review round 3: regex safety, generator methods, type changes ----------

echo -n "Test 139: an invalid lint.exclude pattern (trailing backslash) never empties the scan... "
bs=$(make_project "backslash-exclude")
mkdir -p "$bs/gen"
printf 'version: 1\nlanguages:\n  - python\nlint:\n  exclude:\n    - '"'"'generated\\'"'"'\n' > "$bs/.standards.yml"
echo 'eval("1")' > "$bs/gen/bad.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$bs" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'gen/bad.py'; then pass; else fail "expected FAIL naming gen/bad.py, got: $out"; fi

echo -n "Test 140: go/error-handling and rust/ffi-no-unwrap report (not skip) newline-named files... "
gn=$(make_project "go-rust-newline")
mkdir -p "$gn/src/ffi"
printf 'package main\nfunc main() {}\n' > "$gn/ok.go"
printf 'package main\nfunc g() { _ = run() }\n' > "$gn/odd"$'\n'"bad.go"
printf 'pub fn ok() {}\n' > "$gn/src/ffi/ok.rs"
printf 'pub fn f() { x.unwrap(); }\n' > "$gn/src/ffi/odd"$'\n'"bad.rs"
out=$(bash "$CHECKS/go/error-handling.sh" "$gn" 2>/dev/null || true)
out2=$(bash "$CHECKS/rust/ffi-no-unwrap.sh" "$gn" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'not scanned' \
   && echo "$out2" | grep -q '^FAIL' && echo "$out2" | grep -q 'not scanned'; then pass; else fail "go='$out' rust='$out2'"; fi

echo -n "Test 141: typescript/banned-functions flags a generator method line but still skips block-comment continuations... "
gm=$(make_project "generator-method")
printf 'class A {\n  *run() { eval(input); }\n}\n' > "$gm/a.ts"
out=$(bash "$CHECKS/typescript/banned-functions.sh" "$gm" 2>/dev/null || true)
printf '/**\n * eval(x) must not be used here\n */\nexport const ok = 1;\n' > "$gm/a.ts"
out2=$(bash "$CHECKS/typescript/banned-functions.sh" "$gm" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'a.ts' && echo "$out2" | grep -q '^PASS'; then pass; else fail "generator='$out' comment='$out2'"; fi

echo -n "Test 142: --since includes a symlink replaced by a regular file (type change)... "
tc=$(make_project "type-change")
echo "print('ok')" > "$tc/app.py"
echo "placeholder" > "$TMP_BASE/outside-target.txt"
ln -s "$TMP_BASE/outside-target.txt" "$tc/config.py"
git_commit_all "$tc" "feat: link"
tbase=$(cd "$tc" && git rev-parse HEAD)
rm "$tc/config.py"
printf 'aws_secret_access_key = "%s"\n' "$aws_key" > "$tc/config.py"
git_commit_all "$tc" "feat: real file"
since_status=$("$LINT" --format json --since "$tbase" "$tc" 2>/dev/null | json_check_status no-secrets)
if [ "$since_status" = "FAIL" ]; then pass; else fail "since='$since_status'"; fi

# --- Review round 4: decimal timeouts, quoted commas in inline lists ---------

echo -n "Test 143: --timeout with a leading zero (08) is decimal and still runs every check... "
out=$("$LINT" --format json --timeout 08 "$proj" 2>/dev/null || true)
total=$(echo "$out" | tr -d '\n' | grep -o '"total": *[0-9]*' | grep -o '[0-9]*$')
if [ -n "$out" ] && [ "${total:-0}" -gt 0 ]; then pass; else fail "total='$total' out=$out"; fi

echo -n "Test 144: an inline lint.exclude list keeps a quoted comma inside one value... "
ic=$(make_project "inline-comma")
mkdir -p "$ic/gen,old" "$ic/gen"
printf 'version: 1\nlanguages:\n  - python\nlint:\n  exclude: ["gen,old/", '"'"'skills/'"'"']\n' > "$ic/.standards.yml"
echo 'eval("1")' > "$ic/gen,old/x.py"
echo 'eval("1")' > "$ic/gen/bad.py"
out=$(bash "$CHECKS/python/banned-functions.sh" "$ic" 2>/dev/null || true)
if echo "$out" | grep -q '^FAIL' && echo "$out" | grep -q 'gen/bad.py' && ! echo "$out" | grep -q 'gen,old'; then pass; else
    fail "expected FAIL naming gen/bad.py only, got: $out"; fi

# --- Monorepo members (#179) --------------------------------------------------

DETECT="$REPO_ROOT/scripts/detect-languages.sh"

# Extract the status of one check for one member from the runner's JSON output.
# Field order in a result object is status, check, member, message.
json_member_status() {
    tr -d '\n' | grep -o "\"status\": \"[A-Z]*\",[[:space:]]*\"check\": \"$2\",[[:space:]]*\"member\": \"$1\"" | head -1 | grep -o '"[A-Z]*"' | head -1 | tr -d '"'
}

# Fixture: a monorepo with two members. server/ is Python (with a banned
# eval()), web/ is TypeScript (strict tsconfig). Decoys under node_modules/ and
# .worktrees/ carry a .standards.yml that auto-discovery must ignore.
# $2 = root .standards.yml body (defaults to a pure aggregator declaring the members).
make_monorepo() {
    local name="$1"
    local root_yml="${2:-$(printf 'version: 1\nlanguages: []\nmembers:\n  - server\n  - web\n')}"
    local m
    m=$(make_project "$name")
    mkdir -p "$m/server/src" "$m/server/tests" "$m/web/src" "$m/web/tests" \
             "$m/node_modules/pkg" "$m/.worktrees/agent"
    printf '%s\n' "$root_yml" > "$m/.standards.yml"
    printf 'version: 1\nlanguages:\n  - python\n' > "$m/server/.standards.yml"
    printf '[project]\nname = "server"\n' > "$m/server/pyproject.toml"
    echo 'eval("1")' > "$m/server/src/app.py"
    echo 'def test_ok(): pass' > "$m/server/tests/test_app.py"
    printf 'version: 1\nlanguages:\n  - typescript\n' > "$m/web/.standards.yml"
    printf '{"name":"web"}\n' > "$m/web/package.json"
    printf '{"compilerOptions":{"strict":true}}\n' > "$m/web/tsconfig.json"
    echo 'export const x = 1;' > "$m/web/src/index.ts"
    echo 'export const t = 1;' > "$m/web/tests/index.test.ts"
    printf 'version: 1\nlanguages:\n  - python\n' > "$m/node_modules/pkg/.standards.yml"
    printf 'version: 1\nlanguages:\n  - python\n' > "$m/.worktrees/agent/.standards.yml"
    printf 'node_modules/\n.worktrees/\n' > "$m/.gitignore"
    git_commit_all "$m" "feat: monorepo fixture"
    echo "$m"
}

mono=$(make_monorepo "members-declared")
mono_json=$("$LINT" --format json "$mono" 2>/dev/null || true)

echo -n "Test 145: --format json lists the members and tags every result with its member... "
printf '%s\n' "$mono_json" > "$TMP_BASE/members.json"
if json_valid "$TMP_BASE/members.json" \
   && echo "$mono_json" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *, *"web" *\]' \
   && echo "$mono_json" | grep -q '"member": "server"' \
   && echo "$mono_json" | grep -q '"member": "web"' \
   && echo "$mono_json" | grep -q '"member": "\."'; then pass; else fail "members/member fields missing: $mono_json"; fi

echo -n "Test 146: python checks run against member server (banned eval() is FAIL) and not against web... "
srv=$(echo "$mono_json" | json_member_status server python/banned-functions)
web=$(echo "$mono_json" | json_member_status web python/banned-functions)
if [ "$srv" = "FAIL" ] && echo "$mono_json" | grep -q 'src/app.py' && [ -z "$web" ]; then pass; else
    fail "server='$srv' web='$web'"; fi

echo -n "Test 147: typescript checks run against member web (strict tsconfig PASS) and not against server... "
web=$(echo "$mono_json" | json_member_status web typescript/strict-tsconfig)
srv=$(echo "$mono_json" | json_member_status server typescript/strict-tsconfig)
if [ "$web" = "PASS" ] && [ -z "$srv" ]; then pass; else fail "web='$web' server='$srv'"; fi

echo -n "Test 148: a root that declares no languages runs only repo-wide checks; project checks run per member... "
root_secrets=$(echo "$mono_json" | json_member_status '\.' no-secrets)
root_tests=$(echo "$mono_json" | json_member_status '\.' test-directory)
srv_tests=$(echo "$mono_json" | json_member_status server test-directory)
web_tests=$(echo "$mono_json" | json_member_status web test-directory)
srv_secrets=$(echo "$mono_json" | json_member_status server no-secrets)
if [ "$root_secrets" = "PASS" ] && [ -z "$root_tests" ] && [ -n "$srv_tests" ] && [ -n "$web_tests" ] && [ -z "$srv_secrets" ]; then pass; else
    fail "root: secrets='$root_secrets' tests='$root_tests'; server: tests='$srv_tests' secrets='$srv_secrets'; web tests='$web_tests'"; fi

echo -n "Test 149: a root that declares languages still runs every common check at the root... "
mono2=$(make_monorepo "members-root-langs" "$(printf 'version: 1\nlanguages:\n  - python\nmembers:\n  - server\n  - web\n')")
out=$("$LINT" --format json "$mono2" 2>/dev/null || true)
if [ -n "$(echo "$out" | json_member_status '\.' test-directory)" ] && [ -n "$(echo "$out" | json_member_status '\.' python/banned-functions)" ]; then pass; else
    fail "root checks missing: $out"; fi

echo -n "Test 150: without members: the runner auto-discovers */.standards.yml and skips node_modules and worktrees... "
mono3=$(make_monorepo "members-discovered" "$(printf 'version: 1\nlanguages: []\n')")
out=$("$LINT" --format json "$mono3" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *, *"web" *\]' && ! echo "$out" | grep -q 'node_modules\|worktrees'; then pass; else
    fail "discovery wrong: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]')"; fi

echo -n "Test 151: 'members: []' disables auto-discovery... "
mono4=$(make_monorepo "members-none" "$(printf 'version: 1\nlanguages: []\nmembers: []\n')")
out=$("$LINT" --format json "$mono4" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *\]' && ! echo "$out" | grep -q '"member": "server"'; then pass; else
    fail "expected only the root: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]')"; fi

echo -n "Test 152: a declared member that does not exist is reported as a WARN finding, not a crash... "
mono5=$(make_monorepo "members-missing" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - server\n  - ghost\n')")
"$LINT" --format json "$mono5" > "$TMP_BASE/missing.json" 2>/dev/null; rc=$?
if [ "$rc" -le 1 ] && json_valid "$TMP_BASE/missing.json" \
   && [ "$(json_member_status '\.' members < "$TMP_BASE/missing.json")" = "WARN" ] && grep -q 'ghost' "$TMP_BASE/missing.json"; then pass; else
    fail "rc=$rc status=$(json_member_status '\.' members < "$TMP_BASE/missing.json")"; fi

echo -n "Test 153: a path that escapes the root (..) is never accepted as a member... "
mono6=$(make_monorepo "members-escape" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - ../outside\n  - /etc\n  - server\n')")
out=$("$LINT" --format json "$mono6" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *\]'; then pass; else
    fail "members: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]')"; fi

echo -n "Test 154: --format sarif carries the member in properties and as the artifact location... "
"$LINT" --format sarif "$mono" > "$TMP_BASE/members.sarif" 2>/dev/null || true
if json_valid "$TMP_BASE/members.sarif" && tr -d '\n' < "$TMP_BASE/members.sarif" | grep -q '"properties": *{ *"member": *"server"' \
   && grep -q '"uri": "server"' "$TMP_BASE/members.sarif"; then pass; else fail "SARIF member fields missing"; fi

echo -n "Test 155: summary.total equals the number of results aggregated across members... "
total=$(echo "$mono_json" | tr -d '\n' | grep -o '"total": *[0-9]*' | grep -o '[0-9]*$')
count=$(echo "$mono_json" | grep -c '"status": "')
if [ -n "$total" ] && [ "$total" -eq "$count" ] && [ "$total" -gt 5 ]; then pass; else fail "total=$total count=$count"; fi

echo -n "Test 156: --since scopes file-scanning checks per member (paths re-based onto the member root)... "
sbase=$(cd "$mono" && git rev-parse HEAD)
echo 'eval("x")' > "$mono/web/src/bad.ts"
git_commit_all "$mono" "feat: web change"
since=$("$LINT" --format json --since "$sbase" "$mono" 2>/dev/null || true)
web_bf=$(echo "$since" | json_member_status web typescript/banned-functions)
srv_bf=$(echo "$since" | json_member_status server python/banned-functions)
if [ "$web_bf" = "FAIL" ] && echo "$since" | grep -q 'src/bad.ts' && [ "$srv_bf" = "PASS" ]; then pass; else
    fail "web banned-functions='$web_bf' server banned-functions='$srv_bf'"; fi

echo -n "Test 157: text output groups results under a heading per member... "
txt=$(NO_COLOR=1 "$LINT" --format text "$mono" 2>/dev/null || true)
if echo "$txt" | grep -q 'Members:' && echo "$txt" | grep -q '▸ server' && echo "$txt" | grep -q '▸ web'; then pass; else
    fail "no member headings: $(echo "$txt" | head -20)"; fi

echo -n "Test 158: lint-standards.sh run on a member directory directly behaves as a single-root project... "
out=$("$LINT" --format json "$mono/server" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *\]' && [ "$(echo "$out" | json_member_status '\.' python/banned-functions)" = "FAIL" ]; then pass; else
    fail "member run wrong: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]')"; fi

# detect-languages.sh walks the conventional monorepo sub-roots.
echo -n "Test 159: detect-languages.sh finds manifests under apps/*, packages/*, crates/*, core, server, web, shells/*... "
dl=$(make_project "detect-walk")
mkdir -p "$dl/apps/api" "$dl/packages/ui" "$dl/crates/core" "$dl/core" "$dl/server" "$dl/web" "$dl/shells/apple" "$dl/node_modules/x"
touch "$dl/apps/api/pyproject.toml" "$dl/crates/core/Cargo.toml" "$dl/core/CMakeLists.txt" "$dl/server/go.mod" \
      "$dl/web/package.json" "$dl/web/tsconfig.app.json" "$dl/shells/apple/Package.swift" "$dl/packages/ui/mix.exs" "$dl/node_modules/x/pubspec.yaml"
got=$(bash "$DETECT" "$dl" 2>/dev/null | tr '\n' ' ')
want_ok=true
for l in python rust cpp go javascript typescript swift elixir; do
    case " $got " in *" $l "*) ;; *) want_ok=false ;; esac
done
case " $got " in *" dart "*) want_ok=false ;; esac
if [ "$want_ok" = true ]; then pass; else fail "got: '$got'"; fi

echo -n "Test 160: detect-languages.sh emits each language once and --root-only disables the walk... "
dl2=$(make_project "detect-dedupe")
mkdir -p "$dl2/apps/a" "$dl2/apps/b"
touch "$dl2/apps/a/package.json" "$dl2/apps/b/package.json" "$dl2/Cargo.toml"
full=$(bash "$DETECT" "$dl2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
root_only=$(bash "$DETECT" --root-only "$dl2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
js_count=$(bash "$DETECT" "$dl2" 2>/dev/null | grep -c '^javascript$')
if [ "$js_count" -eq 1 ] && [ "$root_only" = "rust" ] && echo " $full " | grep -q ' rust ' && echo " $full " | grep -q ' javascript '; then pass; else
    fail "full='$full' root_only='$root_only' js_count=$js_count"; fi

echo -n "Test 161: detect-languages.sh --skip <dir> leaves that sub-root to its own member config... "
skipped=$(bash "$DETECT" --skip apps/a "$dl2" 2>/dev/null | tr '\n' ' ')
both_skipped=$(bash "$DETECT" --skip apps/a --skip apps/b "$dl2" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
if echo " $skipped " | grep -q ' javascript ' && [ "$both_skipped" = "rust" ]; then pass; else fail "skipped='$skipped' both='$both_skipped'"; fi

# doctor.sh on monorepos and unsupported language keys.
echo -n "Test 162: doctor.sh flags a declared language that has no standards or checks (cpp)... "
dc=$(make_project "doctor-cpp")
printf 'version: 1\nlanguages:\n  - cpp\n  - python\nagents: []\n' > "$dc/.standards.yml"
touch "$dc/pyproject.toml"
out=$(cd "$dc" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Languages' | grep -q 'WARN' && echo "$out" | grep 'Languages' | grep -q "cpp" \
   && echo "$out" | grep 'Languages' | grep -qi 'unsupported\|no standards'; then pass; else
    fail "cpp not flagged: $(echo "$out" | grep 'Languages')"; fi

echo -n "Test 163: doctor.sh reports the members and checks each member's languages... "
out=$(cd "$mono" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Members' | grep -q 'PASS' && echo "$out" | grep 'Members' | grep -q 'server' \
   && echo "$out" | grep -q 'Languages (server)' && echo "$out" | grep -q 'Languages (web)'; then pass; else
    fail "member lines missing: $(echo "$out" | grep -E 'Members|Languages')"; fi

echo -n "Test 164: doctor.sh does not blame the root for languages that belong to a member... "
# server/ is Python, declared in server/.standards.yml only; the root must not
# demand `python` in its own languages list.
if ! echo "$out" | grep 'Languages' | grep -v '(server)\|(web)' | grep -q "Detected 'python"; then pass; else
    fail "root nagged about member language: $(echo "$out" | grep 'Languages')"; fi

echo -n "Test 165: doctor.sh fails a declared member whose directory is missing and warns on one without .standards.yml... "
mkdir -p "$mono5/bare"
printf 'version: 1\nlanguages: []\nmembers:\n  - server\n  - ghost\n  - bare\n' > "$mono5/.standards.yml"
out=$(cd "$mono5" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep 'Members' | grep 'FAIL' | grep -q 'ghost' && echo "$out" | grep 'Members' | grep 'WARN' | grep -q 'bare'; then pass; else
    fail "member problems not reported: $(echo "$out" | grep 'Members')"; fi

# A declared member is PR-controlled, so a committed symlink must not let the
# scripts read or write outside the checkout: lexically valid paths are also
# resolved physically, and any symlink component is rejected.
echo -n "Test 166: a declared member that is a symlink to a directory outside the root is rejected with a WARN and never scanned... "
outside=$(mktemp -d "$TMP_BASE/outside.XXXXXX")
mkdir -p "$outside/src"
printf 'version: 1\nlanguages:\n  - python\n' > "$outside/.standards.yml"
echo "aws_access_key_id = \"$aws_key\"" > "$outside/src/leak.py"   # a pattern no-secrets would report if it scanned this tree
mono7=$(make_monorepo "members-symlink-out" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - server\n  - escape\n')")
ln -s "$outside" "$mono7/escape"
out=$("$LINT" --format json "$mono7" 2>/dev/null || true)
printf '%s\n' "$out" > "$TMP_BASE/symlink-out.json"
if json_valid "$TMP_BASE/symlink-out.json" \
   && echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *\]' \
   && [ "$(json_member_status '\.' members < "$TMP_BASE/symlink-out.json")" = "WARN" ] \
   && grep -q "declared member 'escape' rejected: 'escape' is a symlink" "$TMP_BASE/symlink-out.json" \
   && ! grep -q 'leak.py\|escape/src' "$TMP_BASE/symlink-out.json"; then pass; else
    fail "members=$(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') status=$(json_member_status '\.' members < "$TMP_BASE/symlink-out.json") $(grep -o '"message": "[^"]*symlink[^"]*"' "$TMP_BASE/symlink-out.json" | head -1)"; fi

echo -n "Test 167: an in-repo symlink (and a symlinked path component) is rejected with the same message while the real member is kept... "
mono8=$(make_monorepo "members-symlink-in" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - server\n  - alias\n  - link/web\n')")
ln -s server "$mono8/alias"
mkdir -p "$mono8/real"
mv "$mono8/web" "$mono8/real/web"
ln -s real "$mono8/link"
out=$("$LINT" --format json "$mono8" 2>/dev/null || true)
printf '%s\n' "$out" > "$TMP_BASE/symlink-in.json"
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *\]' \
   && grep -q "declared member 'alias' rejected: 'alias' is a symlink (members must be real directories inside the project)" "$TMP_BASE/symlink-in.json" \
   && grep -q "declared member 'link/web' rejected: 'link' is a symlink" "$TMP_BASE/symlink-in.json" \
   && [ "$(json_member_status 'server' python/banned-functions < "$TMP_BASE/symlink-in.json")" = "FAIL" ]; then pass; else
    fail "members=$(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') $(grep -o '"message": "[^"]*rejected[^"]*"' "$TMP_BASE/symlink-in.json")"; fi

echo -n "Test 168: doctor.sh fails a symlinked member, and member_escape_reason rejects the symlink while accepting real and missing members... "
out=$(cd "$mono7" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
# Exercise member_escape_reason directly with a root that is itself reached
# through a symlink, so the comparison must use physical paths on both sides.
lib_out=$(bash -c '
    source "$1/scripts/lib/members.sh"
    r=$(member_escape_reason "$2" "escape") && echo "escape:$r"
    member_escape_reason "$2" "server" || echo "server:ok"
    member_escape_reason "$2" "missing" || echo "missing:ok"
' _ "$REPO_ROOT" "$mono7")
if echo "$out" | grep 'Members' | grep 'FAIL' | grep -q "declared member 'escape' rejected" \
   && echo "$lib_out" | grep -q "^escape:declared member 'escape' rejected: 'escape' is a symlink" \
   && echo "$lib_out" | grep -q '^server:ok' && echo "$lib_out" | grep -q '^missing:ok'; then pass; else
    fail "doctor: $(echo "$out" | grep 'Members') lib: $lib_out"; fi

echo -n "Test 169: a trailing YAML comment on a members: entry (block or inline) is not split into bogus member names... "
mono9=$(make_monorepo "members-comments" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - server   # backend service\n  - web # front end\n  - # a comment-only entry\n')")
out=$("$LINT" --format json "$mono9" 2>/dev/null || true)
mono10=$(make_monorepo "members-inline-comment" "$(printf 'version: 1\nlanguages: []\nmembers: [server, web]  # both sub-roots\n')")
out2=$("$LINT" --format json "$mono10" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *, *"web" *\]' && ! echo "$out" | grep -q 'not found (no such directory)' \
   && echo "$out2" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *, *"web" *\]' && ! echo "$out2" | grep -q 'not found (no such directory)'; then pass; else
    fail "block: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') inline: $(echo "$out2" | tr -d '\n' | grep -o '"members": *\[[^]]*\]')"; fi

echo -n "Test 170: a root that is itself a project does not re-scan its members' files, while repo-wide checks still see them... "
mono11=$(make_monorepo "members-root-project" "$(printf 'version: 1\nlanguages:\n  - python\nmembers:\n  - server\n  - web\n')")
mkdir -p "$mono11/src" "$mono11/tests"
echo 'print("root ok")' > "$mono11/src/main.py"
echo 'def test_root(): pass' > "$mono11/tests/test_main.py"
printf 'version: 1\nlanguages:\n  - python\nlint:\n  exclude:\n    - src/app.py\n' > "$mono11/server/.standards.yml"
echo "aws_access_key_id = \"$aws_key\"" > "$mono11/server/src/cfg.py"   # a pattern no-secrets detects (AKIA + 16)
git_commit_all "$mono11" "feat: root project"
out=$("$LINT" --format json "$mono11" 2>/dev/null || true)
printf '%s\n' "$out" > "$TMP_BASE/root-project.json"
root_py=$(json_member_status '\.' python/banned-functions < "$TMP_BASE/root-project.json")
server_py=$(json_member_status 'server' python/banned-functions < "$TMP_BASE/root-project.json")
root_msg=$(tr -d '\n' < "$TMP_BASE/root-project.json" | grep -o '"check": "python/banned-functions",[[:space:]]*"member": "\.",[[:space:]]*"message": "[^"]*"' | head -1)
secrets_msg=$(tr -d '\n' < "$TMP_BASE/root-project.json" | grep -o '"check": "no-secrets",[[:space:]]*"member": "\.",[[:space:]]*"message": "[^"]*"' | head -1)
# The root's own scan passes (server/src/app.py's eval() is the member's file,
# and the member excludes it); the repo-wide no-secrets scan still reaches
# server/src/cfg.py.
if [ "$root_py" = "PASS" ] && [ "$server_py" = "PASS" ] && ! echo "$root_msg" | grep -q 'server/src/app.py' \
   && echo "$secrets_msg" | grep -q 'server/src/cfg.py'; then pass; else
    fail "root=$root_py server=$server_py root_msg=$root_msg secrets=$secrets_msg"; fi

echo -n "Test 171: an auto-discovered parent member does not re-scan the files of a member nested below it... "
nest=$(make_project "members-nested")
mkdir -p "$nest/packages/src" "$nest/packages/tests" "$nest/packages/web/src" "$nest/packages/web/tests"
printf 'version: 1\nlanguages: []\n' > "$nest/.standards.yml"
printf 'version: 1\nlanguages:\n  - python\n' > "$nest/packages/.standards.yml"
echo 'print("parent ok")' > "$nest/packages/src/lib.py"
echo 'def test_lib(): pass' > "$nest/packages/tests/test_lib.py"
printf 'version: 1\nlanguages:\n  - python\nlint:\n  exclude:\n    - src/bad.py\n' > "$nest/packages/web/.standards.yml"
echo 'eval("1")' > "$nest/packages/web/src/bad.py"   # the child's own lint.exclude hides it
echo 'def test_web(): pass' > "$nest/packages/web/tests/test_web.py"
git_commit_all "$nest" "feat: nested members"
out=$("$LINT" --format json "$nest" 2>/dev/null || true)
printf '%s\n' "$out" > "$TMP_BASE/nested.json"
parent_py=$(json_member_status 'packages' python/banned-functions < "$TMP_BASE/nested.json")
child_py=$(json_member_status 'packages/web' python/banned-functions < "$TMP_BASE/nested.json")
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"packages" *, *"packages/web" *\]' \
   && [ "$parent_py" = "PASS" ] && [ "$child_py" = "PASS" ]; then pass; else
    fail "members=$(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') parent=$parent_py child=$child_py"; fi

echo -n "Test 172: a trailing comment after a quoted members: entry is dropped too... "
mono12=$(make_monorepo "members-quoted-comment" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - "server" # backend service\n  - '"'"'web'"'"'   # front end\n')")
out=$("$LINT" --format json "$mono12" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *, *"web" *\]' && ! echo "$out" | grep -q 'not found (no such directory)'; then pass; else
    fail "members: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') $(grep -o '"message": "[^"]*not found[^"]*"' <<<"$out")"; fi

echo -n "Test 173: a member whose .standards.yml is a symlink is rejected when declared and skipped by discovery... "
cfg_outside=$(mktemp -d "$TMP_BASE/cfg-outside.XXXXXX")
printf 'version: 1\nlanguages:\n  - python\n' > "$cfg_outside/standards.yml"
mono13=$(make_monorepo "members-config-symlink")
rm -f "$mono13/server/.standards.yml"
ln -s "$cfg_outside/standards.yml" "$mono13/server/.standards.yml"
out=$("$LINT" --format json "$mono13" 2>/dev/null || true)
printf '%s\n' "$out" > "$TMP_BASE/config-symlink.json"
mono14=$(make_monorepo "members-config-symlink-discovery" "$(printf 'version: 1\nlanguages: []\n')")
rm -f "$mono14/web/.standards.yml"
ln -s "$cfg_outside/standards.yml" "$mono14/web/.standards.yml"
out2=$("$LINT" --format json "$mono14" 2>/dev/null || true)
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"web" *\]' \
   && grep -q "declared member 'server' rejected: its .standards.yml is a symlink" "$TMP_BASE/config-symlink.json" \
   && echo "$out2" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *\]'; then pass; else
    fail "declared: $(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') discovered: $(echo "$out2" | tr -d '\n' | grep -o '"members": *\[[^]]*\]')"; fi

echo -n "Test 174: doctor.sh judges the root by its own manifests, not by a tsconfig.json under apps/web... "
zc=$(make_project "doctor-root-only")
mkdir -p "$zc/apps/web"
printf 'version: 1\nlanguages:\n  - python\n' > "$zc/.standards.yml"
printf '[project]\nname = "root"\n' > "$zc/pyproject.toml"
printf '{"compilerOptions":{"strict":true}}\n' > "$zc/apps/web/tsconfig.json"
printf '{"name":"web"}\n' > "$zc/apps/web/package.json"
out=$(cd "$zc" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep -q 'Languages' && ! echo "$out" | grep 'Languages' | grep -q 'typescript'; then pass; else
    fail "root nagged about a sub-root language: $(echo "$out" | grep 'Languages')"; fi

echo -n "Test 175: dot segments in members: entries are canonicalised and duplicate declarations are checked once... "
mono15=$(make_monorepo "members-canonical" "$(printf 'version: 1\nlanguages: []\nmembers:\n  - server/.\n  - ./server/\n  - server\n  - ./web//\n')")
out=$("$LINT" --format json "$mono15" 2>/dev/null || true)
server_runs=$(printf '%s' "$out" | tr -d '\n' | grep -o '"check": "python/banned-functions",[[:space:]]*"member": "server"' | wc -l | tr -d ' ')
if echo "$out" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"server" *, *"web" *\]' && [ "$server_runs" = "1" ]; then pass; else
    fail "members=$(echo "$out" | tr -d '\n' | grep -o '"members": *\[[^]]*\]') server_runs=$server_runs"; fi

echo -n "Test 176: doctor.sh does not ask a CMake-only project to declare the unsupported 'cpp' key... "
cm=$(make_project "doctor-cmake-only")
printf 'version: 1\nlanguages: []\n' > "$cm/.standards.yml"
printf 'cmake_minimum_required(VERSION 3.20)\nproject(demo)\n' > "$cm/CMakeLists.txt"
out=$(cd "$cm" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep -q 'Languages' && ! echo "$out" | grep 'Languages' | grep -q 'cpp'; then pass; else
    fail "doctor suggested cpp: $(echo "$out" | grep 'Languages')"; fi

echo -n "Test 177: doctor.sh does not ask a parent member to declare a nested member's languages... "
nest2=$(make_project "doctor-nested-members")
mkdir -p "$nest2/packages/web"
printf 'version: 1\nlanguages: []\nmembers:\n  - packages\n  - packages/web\n' > "$nest2/.standards.yml"
printf 'version: 1\nlanguages: []\n' > "$nest2/packages/.standards.yml"
printf 'version: 1\nlanguages:\n  - typescript\n' > "$nest2/packages/web/.standards.yml"
printf '{"name":"web"}\n' > "$nest2/packages/web/package.json"
printf '{"compilerOptions":{"strict":true}}\n' > "$nest2/packages/web/tsconfig.json"
out=$(cd "$nest2" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1 || true)
if echo "$out" | grep -q 'Languages (packages)' && ! echo "$out" | grep 'Languages (packages)' | grep -q 'typescript'; then pass; else
    fail "parent nagged about child language: $(echo "$out" | grep 'Languages (packages')"; fi


echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All $PASS tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL of $((PASS + FAIL)) tests failed.${NC}"
    exit 1
fi
