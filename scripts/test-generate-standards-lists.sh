#!/bin/bash
# Functional tests for generate-standards-lists.sh and lib/standards-lists.sh —
# the generator that keeps the enumerable sections of agent configs (standards
# file lists, language-detection maps) in sync with the standards/ tree, and
# the --check drift gate CI runs on every PR.
#
# Each test builds a fixture repo with a known standards/ tree and asserts
# rendering, splicing, and check outcomes. The last tests dogfood the real repo.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GEN="$REPO_ROOT/scripts/generate-standards-lists.sh"
LIB="$REPO_ROOT/scripts/lib/standards-lists.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-generate-standards-lists.XXXXXX")"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

BEGIN_LIST='<!-- BEGIN GENERATED: standards-list -->'
END_LIST='<!-- END GENERATED: standards-list -->'
BEGIN_LANG='<!-- BEGIN GENERATED: language-detection -->'
END_LANG='<!-- END GENERATED: language-detection -->'

# make_fixture <name> — builds a minimal repo-shaped tree with a standards/
# directory, a catalog, and agent configs carrying generated regions.
make_fixture() {
    local dir="$TMP_BASE/$1"
    mkdir -p "$dir/standards/architecture" "$dir/standards/languages" \
             "$dir/standards/process" "$dir/standards/security" \
             "$dir/standards/shared" "$dir/.github" "$dir/.gemini"
    printf '# Project Standards & Architecture\n' > "$dir/standards/architecture/arch-01_project_standards_and_architecture.md"
    printf '# Document 2: Automation & Workflows\n' > "$dir/standards/architecture/arch-02_automation_standards.md"
    printf '# Python Standards\n' > "$dir/standards/languages/lang-01_python_standards.md"
    printf '# Ruby on Rails Standards\n' > "$dir/standards/languages/lang-02_rails_standards.md"
    printf '# Documentation Standards\n' > "$dir/standards/process/proc-01_documentation_standards.md"
    printf '# Security Standards\n' > "$dir/standards/security/sec-01_security_standards.md"
    printf '# Core Standards\n' > "$dir/standards/shared/core-standards.md"
    # Not a standard: must never be enumerated.
    printf '# Schema\n' > "$dir/standards/shared/standards-yml-schema.md"
    printf '# Notes\n' > "$dir/standards/architecture/README.md"
    cat > "$dir/standards/catalog.tsv" <<'EOF'
# path	description	triggers
architecture/arch-01_project_standards_and_architecture.md	Core architecture, SOLID principles
languages/lang-01_python_standards.md	Python (uv, ruff, mypy, pytest)	`.py` files
EOF
    cat > "$dir/.cursorrules" <<EOF
# Cursor rules

Intro paragraph that must survive.

$BEGIN_LIST
stale content that must be replaced
$END_LIST

## Language Detection

$BEGIN_LANG
$END_LANG

Trailing paragraph that must survive.
EOF
    cp "$dir/.cursorrules" "$dir/AGENTS.md"
    cp "$dir/.cursorrules" "$dir/CLAUDE.md"
    cp "$dir/.cursorrules" "$dir/.github/copilot-instructions.md"
    cp "$dir/.cursorrules" "$dir/.gemini/GEMINI.md"
    echo "$dir"
}

echo -e "${BLUE}Testing generate-standards-lists.sh and lib/standards-lists.sh${NC}"
echo ""

# --- Existence / syntax ------------------------------------------------------

echo -n "Test 1: generate-standards-lists.sh exists and is executable... "
if [ -x "$GEN" ]; then pass; else fail "$GEN not executable"; fi

echo -n "Test 2: lib/standards-lists.sh is sourceable and exposes the API... "
if bash -c "source '$LIB' && type list_standards_files render_region splice_generated_regions" >/dev/null 2>&1; then
    pass
else
    fail "expected functions not defined after sourcing $LIB"
fi

echo -n "Test 3: lib and generator pass bash -n... "
if bash -n "$LIB" && bash -n "$GEN"; then pass; else fail "syntax error"; fi

# --- Enumeration --------------------------------------------------------------

fx=$(make_fixture "enum")

echo -n "Test 4: list_standards_files enumerates prefixed files + core-standards only... "
out=$(bash -c "source '$LIB' && list_standards_files '$fx/standards'")
expected="architecture/arch-01_project_standards_and_architecture.md
architecture/arch-02_automation_standards.md
languages/lang-01_python_standards.md
languages/lang-02_rails_standards.md
process/proc-01_documentation_standards.md
security/sec-01_security_standards.md
shared/core-standards.md"
if [ "$out" = "$expected" ]; then pass; else fail "unexpected enumeration:
$out"; fi

echo -n "Test 5: list_standards_files filters by category... "
out=$(bash -c "source '$LIB' && list_standards_files '$fx/standards' languages")
if [ "$out" = "languages/lang-01_python_standards.md
languages/lang-02_rails_standards.md" ]; then pass; else fail "got: $out"; fi

# --- Rendering ----------------------------------------------------------------

echo -n "Test 6: standards-list uses the catalog description when present... "
out=$(bash -c "source '$LIB' && render_region standards-list '$fx/standards' 'standards/'")
if echo "$out" | grep -qF -- '- `standards/languages/lang-01_python_standards.md` — Python (uv, ruff, mypy, pytest)'; then
    pass
else
    fail "catalog description missing from:
$out"
fi

echo -n "Test 7: standards-list falls back to the H1 title (minus 'Document N:' prefix)... "
if echo "$out" | grep -qF -- '- `standards/architecture/arch-02_automation_standards.md` — Automation & Workflows'; then
    pass
else
    fail "H1 fallback missing from:
$out"
fi

echo -n "Test 8: standards-list groups by category with labels and includes shared core... "
if echo "$out" | grep -qF '**Architecture Standards:**' \
   && echo "$out" | grep -qF '**Language Standards:**' \
   && echo "$out" | grep -qF '**Process Standards:**' \
   && echo "$out" | grep -qF '**Security Standards:**' \
   && echo "$out" | grep -qF '**Shared Standards:**' \
   && echo "$out" | grep -qF -- '- `standards/shared/core-standards.md`'; then
    pass
else
    fail "category labels / shared entry missing from:
$out"
fi

echo -n "Test 9: standards-list never enumerates non-standard files... "
if echo "$out" | grep -qE 'standards-yml-schema|architecture/README'; then
    fail "non-standard file leaked into list"
else
    pass
fi

echo -n "Test 10: language-detection uses catalog triggers and a name fallback... "
out=$(bash -c "source '$LIB' && render_region language-detection '$fx/standards' 'standards/'")
if echo "$out" | grep -qF -- '- `.py` files → `standards/languages/lang-01_python_standards.md`' \
   && echo "$out" | grep -qF -- '- Ruby on Rails source files → `standards/languages/lang-02_rails_standards.md`'; then
    pass
else
    fail "language-detection output wrong:
$out"
fi

echo -n "Test 11: render_region rejects an unknown region id... "
if bash -c "source '$LIB' && render_region bogus-region '$fx/standards' 'standards/'" >/dev/null 2>&1; then
    fail "unknown region did not fail"
else
    pass
fi

# --- Splicing -----------------------------------------------------------------

echo -n "Test 12: generator replaces region bodies and preserves surrounding text... "
"$GEN" --root "$fx" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] \
   && grep -qF 'Intro paragraph that must survive.' "$fx/.cursorrules" \
   && grep -qF 'Trailing paragraph that must survive.' "$fx/.cursorrules" \
   && ! grep -qF 'stale content that must be replaced' "$fx/.cursorrules" \
   && grep -qF 'lang-02_rails_standards.md' "$fx/.cursorrules" \
   && grep -qF -- "$BEGIN_LIST" "$fx/.cursorrules" \
   && grep -qF -- "$END_LIST" "$fx/.cursorrules" \
   && grep -qF -- '- `.py` files →' "$fx/.cursorrules"; then
    pass
else
    fail "splice result wrong (rc=$rc):
$(cat "$fx/.cursorrules")"
fi

echo -n "Test 13: generator is idempotent (second run changes nothing)... "
cp "$fx/.cursorrules" "$TMP_BASE/first.cursorrules"
"$GEN" --root "$fx" >/dev/null 2>&1
if cmp -s "$fx/.cursorrules" "$TMP_BASE/first.cursorrules"; then pass; else fail "second run altered output"; fi

echo -n "Test 14: generator regenerates every file carrying a sentinel... "
if grep -qF 'lang-02_rails_standards.md' "$fx/AGENTS.md" \
   && grep -qF 'lang-02_rails_standards.md' "$fx/CLAUDE.md" \
   && grep -qF 'lang-02_rails_standards.md' "$fx/.github/copilot-instructions.md" \
   && grep -qF 'lang-02_rails_standards.md' "$fx/.gemini/GEMINI.md"; then
    pass
else
    fail "not every target was regenerated"
fi

echo -n "Test 15: unterminated region is an error, file left untouched... "
bad=$(make_fixture "unterminated")
printf '# X\n%s\nbody\n' "$BEGIN_LIST" > "$bad/CLAUDE.md"
cp "$bad/CLAUDE.md" "$TMP_BASE/bad.before"
if "$GEN" --root "$bad" >/dev/null 2>&1; then
    fail "unterminated region did not fail"
elif cmp -s "$bad/CLAUDE.md" "$TMP_BASE/bad.before"; then
    pass
else
    fail "file was modified despite the error"
fi

# --- Check mode ---------------------------------------------------------------

ok=$(make_fixture "check-ok")
"$GEN" --root "$ok" >/dev/null 2>&1

echo -n "Test 16: --check passes on a consistent tree and emits PASS lines... "
out=$("$GEN" --root "$ok" --check 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '^PASS ' && ! echo "$out" | grep -q '^FAIL '; then
    pass
else
    fail "expected clean check (rc=$rc):
$out"
fi

echo -n "Test 17: --check FAILs when a generated region is stale... "
stale=$(make_fixture "check-stale")
"$GEN" --root "$stale" >/dev/null 2>&1
printf '# Go Standards\n' > "$stale/standards/languages/lang-03_go_standards.md"
out=$("$GEN" --root "$stale" --check 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q '^FAIL ' && echo "$out" | grep -q 'generate-standards-lists'; then
    pass
else
    fail "stale region not detected (rc=$rc):
$out"
fi

echo -n "Test 18: --check FAILs when a config references a standards file that does not exist... "
broken=$(make_fixture "check-broken-ref")
"$GEN" --root "$broken" >/dev/null 2>&1
printf '\nSee `standards/languages/lang-99_cobol_standards.md`.\n' >> "$broken/CLAUDE.md"
out=$("$GEN" --root "$broken" --check 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q '^FAIL ' && echo "$out" | grep -q 'lang-99_cobol_standards.md'; then
    pass
else
    fail "broken reference not detected (rc=$rc):
$out"
fi

echo -n "Test 19: --check FAILs when an agent config omits an existing standards file... "
omit=$(make_fixture "check-omit")
"$GEN" --root "$omit" >/dev/null 2>&1
# An agent config with no generated region at all cannot be regenerated, so it
# must be caught by the completeness check instead.
printf '# AGENTS.md\n\nOnly `standards/languages/lang-01_python_standards.md` here.\n' > "$omit/AGENTS.md"
out=$("$GEN" --root "$omit" --check 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q '^FAIL ' && echo "$out" | grep -q 'AGENTS.md' && echo "$out" | grep -q 'sec-01_security_standards.md'; then
    pass
else
    fail "omission not detected (rc=$rc):
$out"
fi

echo -n "Test 20: --check FAILs when the catalog lists a file that does not exist... "
cat_bad=$(make_fixture "check-catalog")
"$GEN" --root "$cat_bad" >/dev/null 2>&1
printf 'languages/lang-77_fortran_standards.md\tFortran\t`.f90` files\n' >> "$cat_bad/standards/catalog.tsv"
out=$("$GEN" --root "$cat_bad" --check 2>&1); rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q '^FAIL ' && echo "$out" | grep -q 'lang-77_fortran_standards.md'; then
    pass
else
    fail "stale catalog entry not detected (rc=$rc):
$out"
fi

echo -n "Test 21: --check WARNs (not FAILs) for a standards file without a catalog entry... "
out=$("$GEN" --root "$ok" --check 2>&1)
if echo "$out" | grep -q '^WARN .*arch-02_automation_standards.md'; then pass; else fail "expected WARN for uncatalogued file:
$out"; fi

echo -n "Test 22: --check never modifies files... "
cp "$stale/.cursorrules" "$TMP_BASE/stale.before"
"$GEN" --root "$stale" --check >/dev/null 2>&1 || true
if cmp -s "$stale/.cursorrules" "$TMP_BASE/stale.before"; then pass; else fail "--check modified .cursorrules"; fi

# --- Dogfood: the real repository ----------------------------------------------

echo -n "Test 23: the repo's own agent configs pass --check (no drift)... "
out=$("$GEN" --root "$REPO_ROOT" --check 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then pass; else fail "repo is out of sync — run make generate-standards-lists:
$out"; fi

echo -n "Test 24: every real agent config carries a generated standards-list region... "
missing=""
for f in .cursorrules .github/copilot-instructions.md .gemini/GEMINI.md AGENTS.md CLAUDE.md standards/README.md; do
    grep -qF -- "$BEGIN_LIST" "$REPO_ROOT/$f" || missing="$missing $f"
done
if [ -z "$missing" ]; then pass; else fail "no standards-list region in:$missing"; fi

echo -n "Test 25: every real language standard has catalog triggers (no name fallback in detection maps)... "
if grep -q 'source files →' "$REPO_ROOT/.cursorrules"; then
    fail "a language is missing its triggers column in standards/catalog.tsv"
else
    pass
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}All $PASS tests passed!${NC}"
    exit 0
else
    echo -e "${RED}$FAIL of $((PASS + FAIL)) tests failed.${NC}"
    exit 1
fi
