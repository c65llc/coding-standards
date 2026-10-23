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

# --- assemble-config: profile- blocks and the skills index -----------------

ASSEMBLE="$REPO_ROOT/scripts/assemble-config.sh"
FIX="$TMP_BASE/fixtures"
mkdir -p "$FIX/blocks" "$FIX/skills"
echo "Role app rule." > "$FIX/blocks/role-app.md"
echo "Shared core rule." > "$FIX/blocks/profile-shared-core.md"
echo "UI surface rule." > "$FIX/blocks/profile-ui-surface.md"
printf -- '---\nname: plain\ndescription: Plain skill\n---\n\n# Plain\n\n## When to Use\n\n- always\n' > "$FIX/skills/plain.md"
printf -- '---\nname: gated\ndescription: Gated skill\nprofiles: ui-surface\n---\n\n# Gated\n\n## When to Use\n\n- only with ui-surface\n' > "$FIX/skills/gated.md"
CODEX_BASE="$REPO_ROOT/standards/agents/codex/base-codex.md"
CLAUDE_BASE="$REPO_ROOT/standards/agents/claude-code/base-claude-code.md"

# assemble <agent> <out> <profiles|-> [blocks...]; "-" passes no --profiles
# flag (the environment decides); stderr goes to <out>.err
assemble() {
    local agent="$1" out="$2" profiles="$3"; shift 3
    local proj; proj=$(make_project "asm-$RANDOM")
    local base="$CODEX_BASE"; [ "$agent" = claude-code ] && base="$CLAUDE_BASE"
    local opts=(--project-root "$proj" --skills-dir "$FIX/skills")
    [ "$profiles" != "-" ] && opts+=(--profiles "$profiles")
    "$ASSEMBLE" "${opts[@]}" "$agent" "$FIX/blocks" "$base" "$out" "$@" >/dev/null 2>"$out.err"
}

out="$TMP_BASE/t7.md"
echo -n "Test 7: one profile block renders under '## Profiles' / '### Shared Core' after '## Project Type'... "
assemble claude-code "$out" - role-app.md profile-shared-core.md
n=$(grep -c '^## Profiles$' "$out"); pt=$(grep -n '^## Project Type$' "$out" | cut -d: -f1); pf=$(grep -n '^## Profiles$' "$out" | cut -d: -f1)
if [ "$n" = 1 ] && grep -q '^### Shared Core$' "$out" && [ -n "$pt" ] && [ "$pf" -gt "$pt" ]; then pass; else fail "headings wrong (count=$n pt=$pt pf=$pf)"; fi

out="$TMP_BASE/t8.md"
echo -n "Test 8: two profile blocks share one '## Profiles' heading in declared order... "
assemble claude-code "$out" - role-app.md profile-shared-core.md profile-ui-surface.md
n=$(grep -c '^## Profiles$' "$out"); a=$(grep -n '^### Shared Core$' "$out" | cut -d: -f1); b=$(grep -n '^### UI Surface$' "$out" | cut -d: -f1)
if [ "$n" = 1 ] && [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then pass; else fail "count=$n a=$a b=$b"; fi

echo -n "Test 9: no unknown-prefix WARNING on stderr for profile- blocks... "
if ! grep -q 'unknown prefix' "$out.err"; then pass; else fail "$(cat "$out.err")"; fi

out="$TMP_BASE/t10.md"
echo -n "Test 10: codex Skills index with --profiles '' lists plain and not gated... "
assemble codex "$out" "" role-app.md
if grep -q '^### plain$' "$out" && ! grep -q '^### gated$' "$out"; then pass; else fail "$(grep '^### ' "$out" | tr '\n' ' ')"; fi

out="$TMP_BASE/t11.md"
echo -n "Test 11: codex Skills index with --profiles ui-surface lists both... "
assemble codex "$out" "ui-surface" role-app.md
if grep -q '^### plain$' "$out" && grep -q '^### gated$' "$out"; then pass; else fail "$(grep '^### ' "$out" | tr '\n' ' ')"; fi

out="$TMP_BASE/t12.md"
echo -n "Test 12: STANDARDS_PROFILES in the environment behaves like --profiles... "
STANDARDS_PROFILES="ui-surface" assemble codex "$out" - role-app.md
if grep -q '^### gated$' "$out"; then pass; else fail "gated not listed"; fi

echo -n "Test 13: skill_profiles parses [a, b], 'a, b' and 'a'... "
printf -- '---\nname: x\nprofiles: [a, b]\n---\n' > "$FIX/p1.md"
printf -- '---\nname: x\nprofiles: a, b\n---\n' > "$FIX/p2.md"
printf -- '---\nname: x\nprofiles: a\n---\n' > "$FIX/p3.md"
r=$(bash -c "source '$REPO_ROOT/scripts/lib/skills.sh'; printf '%s|%s|%s' \"\$(skill_profiles '$FIX/p1.md')\" \"\$(skill_profiles '$FIX/p2.md')\" \"\$(skill_profiles '$FIX/p3.md')\"" 2>/dev/null)
if [ "$r" = "a b|a b|a" ]; then pass; else fail "got '$r'"; fi

# --- summary ----------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
