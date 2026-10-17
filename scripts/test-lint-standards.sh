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

echo -n "Test 12: artifact-hygiene module PASSes a project with no binary artifacts... "
out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$clean" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 13: artifact-hygiene module PASSes a committed wasm with no home paths... "
hyg_ok=$(make_project "hygiene-ok")
mkdir -p "$hyg_ok/pkg"
# Minimal wasm magic + version header plus a remapped (host-agnostic) path.
printf '\000asm\001\000\000\000/rustc/1.80.0/library/core/src/lib.rs\000' > "$hyg_ok/pkg/core_bg.wasm"
( cd "$hyg_ok" && git add -A && git -c user.email="t@t.local" -c user.name="T" \
    commit -q -m "chore: commit clean wasm" )
out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$hyg_ok" 2>/dev/null || true)
if echo "$out" | grep -q '^PASS'; then pass; else fail "expected PASS, got: $out"; fi

echo -n "Test 14: artifact-hygiene module WARNs on committed artifacts embedding home paths... "
hyg_bad=$(make_project "hygiene-bad")
mkdir -p "$hyg_bad/pkg" "$hyg_bad/dist"
printf '\000asm\001\000\000\000/Users/alice/src/core/crates/core/src/lib.rs\000' > "$hyg_bad/pkg/core_bg.wasm"
printf '\177ELF\002\001\001\000/home/bob/work/core/build/libcore.so\000' > "$hyg_bad/dist/libcore.so"
( cd "$hyg_bad" && git add -A && git -c user.email="t@t.local" -c user.name="T" \
    commit -q -m "chore: commit tainted artifacts" )
out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$hyg_bad" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' \
   && echo "$out" | grep -q 'core_bg.wasm' \
   && echo "$out" | grep -q 'libcore.so'; then pass; else fail "expected WARN naming both artifacts, got: $out"; fi

echo -n "Test 15: artifact-hygiene module redacts the username from its report... "
if echo "$out" | grep -q '/Users/alice\|/home/bob'; then fail "username leaked in: $out"; else pass; fi

echo -n "Test 16: artifact-hygiene module falls back to a filesystem scan outside git... "
hyg_nogit="$TMP_BASE/hygiene-nogit"
mkdir -p "$hyg_nogit/lib"
printf 'PK\003\004/Users/carol/proj/build/libs/app.jar\000' > "$hyg_nogit/lib/app.jar"
out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$hyg_nogit" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'app.jar'; then pass; else fail "expected WARN naming app.jar, got: $out"; fi

echo -n "Test 17: artifact-hygiene module handles a project root containing '&' and '|'... "
hyg_amp=$(make_project "hygiene r&d|x")
mkdir -p "$hyg_amp/pkg"
printf '\000asm\001\000\000\000/Users/dave/src/core/src/lib.rs\000' > "$hyg_amp/pkg/core_bg.wasm"
( cd "$hyg_amp" && git add -A && git -c user.email="t@t.local" -c user.name="T" \
    commit -q -m "chore: commit tainted wasm" )
out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$hyg_amp" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'core_bg.wasm'; then pass; else fail "expected WARN naming core_bg.wasm, got: $out"; fi

echo -n "Test 18: artifact-hygiene fallback only excludes directories below the project root... "
hyg_anc="$TMP_BASE/target/exported-project"
mkdir -p "$hyg_anc/lib" "$hyg_anc/node_modules/dep"
printf '\177ELF\002\001\001\000/home/erin/work/core/build/libcore.so\000' > "$hyg_anc/lib/libcore.so"
printf '\177ELF\002\001\001\000/home/erin/.npm/libdep.so\000' > "$hyg_anc/node_modules/dep/libdep.so"
out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$hyg_anc" 2>/dev/null || true)
if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'libcore.so' \
   && ! echo "$out" | grep -q 'libdep.so'; then pass; else fail "expected WARN naming libcore.so only, got: $out"; fi

echo -n "Test 19: artifact-hygiene module inspects deflated JAR entries... "
if command -v python3 >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1; then
    hyg_jar=$(make_project "hygiene-jar")
    mkdir -p "$hyg_jar/build/libs"
    python3 -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", compression=zipfile.ZIP_DEFLATED) as z:
    z.writestr("META-INF/MANIFEST.MF", "Manifest-Version: 1.0\n")
    z.writestr("com/example/build.properties",
               "source=/Users/frank/src/app/src/main/java/com/example/App.java\n" * 8)
' "$hyg_jar/build/libs/app.jar"
    if LC_ALL=C grep -aq '/Users/frank' "$hyg_jar/build/libs/app.jar"; then
        fail "test fixture is not compressed; cannot prove inflation"
    else
        ( cd "$hyg_jar" && git add -A && git -c user.email="t@t.local" -c user.name="T" \
            commit -q -m "chore: commit jar" )
        out=$(bash "$CHECKS/common/artifact-hygiene.sh" "$hyg_jar" 2>/dev/null || true)
        if echo "$out" | grep -q '^WARN' && echo "$out" | grep -q 'app.jar'; then pass; else fail "expected WARN naming app.jar, got: $out"; fi
    fi
else
    echo "skipped (python3/unzip unavailable)"
fi

# --- Sibling scripts smoke --------------------------------------------------

echo -n "Test 20: diff-standards.sh runs on a project without .standards.yml... "
if bash "$REPO_ROOT/scripts/diff-standards.sh" "$proj" >/dev/null 2>&1; then pass; else
    # diff-standards may exit non-zero; accept as long as it doesn't crash hard (>1)
    rc=$?; if [ "$rc" -le 1 ]; then pass; else fail "diff-standards crashed (exit $rc)"; fi
fi

echo -n "Test 21: doctor.sh runs without a hard crash... "
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
