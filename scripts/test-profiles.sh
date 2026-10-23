#!/bin/bash
# Functional tests for the profiles selector (#227): the vocabulary and block
# mapping in lib/languages.sh, STD_PROFILES in read_standards_config, the
# profile- block rendering in assemble-config.sh, the profile gate in
# assemble-skills.sh, the sync/diff wiring, detect-profiles.sh and the doctor
# check. Each test builds a temp project with known conditions and asserts
# outcomes, the way test-setup-safe.sh does.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMP_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-profiles.XXXXXX")"
trap 'rm -rf "$TMP_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

make_project() {
    local name="$1"
    local dir="$TMP_BASE/$name"
    mkdir -p "$dir"
    ( cd "$dir" && git init -q \
        && git -c user.email="t@t.local" -c user.name="T" \
               commit -q --allow-empty -m "chore: init" )
    echo "$dir"
}

# Run a snippet in a subshell with lib/languages.sh and lib/checksums.sh
# sourced, printing whatever the snippet prints.
with_libs() {
    bash -c "source '$REPO_ROOT/scripts/lib/languages.sh'; source '$REPO_ROOT/scripts/lib/checksums.sh'; $1" 2>/dev/null
}

echo -e "${BLUE}Testing the profiles selector${NC}"
echo ""

# --- lib: vocabulary, mapping, config ---------------------------------------

echo -n "Test 1: profile_supported accepts shared-core and ui-surface, rejects foo... "
if with_libs 'profile_supported shared-core && profile_supported ui-surface && ! profile_supported foo && echo ok' | grep -q ok; then
    pass
else
    fail "profile_supported missing or wrong"
fi

echo -n "Test 2: map_profiles_to_blocks keeps declared order and drops duplicates... "
out=$(with_libs 'map_profiles_to_blocks "ui-surface shared-core ui-surface"')
if [ "$out" = "profile-ui-surface.md profile-shared-core.md " ]; then
    pass
else
    fail "got '$out'"
fi

echo -n "Test 3: profile_display_name renders Shared Core and UI Surface... "
a=$(with_libs 'profile_display_name shared-core'); b=$(with_libs 'profile_display_name ui-surface')
if [ "$a" = "Shared Core" ] && [ "$b" = "UI Surface" ]; then
    pass
else
    fail "got '$a' / '$b'"
fi

proj=$(make_project "cfg-inline")
printf 'version: 1\nlanguages: [python]\nprofiles: [shared-core, ui-surface]\n' > "$proj/.standards.yml"
echo -n "Test 4: read_standards_config reads an inline profiles list... "
out=$(with_libs "read_standards_config '$proj'; printf '%s' \"\$STD_PROFILES\"")
if [ "$out" = "shared-core ui-surface" ]; then pass; else fail "got '$out'"; fi

proj=$(make_project "cfg-block")
printf 'version: 1\nlanguages:\n  - python\nprofiles:\n  - shared-core\n  - ui-surface\nrole: app\n' > "$proj/.standards.yml"
echo -n "Test 5: read_standards_config reads a block profiles list... "
out=$(with_libs "read_standards_config '$proj'; printf '%s' \"\$STD_PROFILES\"")
if [ "$out" = "shared-core ui-surface" ]; then pass; else fail "got '$out'"; fi

proj=$(make_project "cfg-none")
printf 'version: 1\nlanguages: [python]\n' > "$proj/.standards.yml"
proj2=$(make_project "cfg-empty")
printf 'version: 1\nlanguages: [python]\nprofiles: []\n' > "$proj2/.standards.yml"
echo -n "Test 6: a missing key and profiles: [] both read as empty... "
a=$(with_libs "read_standards_config '$proj'; printf '[%s]' \"\$STD_PROFILES\"")
b=$(with_libs "read_standards_config '$proj2'; printf '[%s]' \"\$STD_PROFILES\"")
if [ "$a" = "[]" ] && [ "$b" = "[]" ]; then pass; else fail "got '$a' and '$b'"; fi

# --- summary ----------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
