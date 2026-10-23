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

# --- assemble-skills: the profile gate and removal -------------------------

SKILLS="$REPO_ROOT/scripts/assemble-skills.sh"
# skills <proj> <profiles> <agents...>; stdout+stderr to <proj>/.skills.out
skills() {
    local proj="$1" profiles="$2"; shift 2
    "$SKILLS" --project-root "$proj" --skills-dir "$FIX/skills" --profiles "$profiles" "$@" > "$proj/.skills.out" 2>&1
}

proj=$(make_project "sk-gate")
echo -n "Test 14: --profiles '' installs plain and not gated for claude-code... "
skills "$proj" "" claude-code
if [ -f "$proj/.claude/skills/plain/SKILL.md" ] && [ ! -f "$proj/.claude/skills/gated/SKILL.md" ]; then pass; else fail "$(cat "$proj/.skills.out")"; fi

echo -n "Test 15: --profiles ui-surface installs both and records the gated checksum... "
skills "$proj" "ui-surface" claude-code
if [ -f "$proj/.claude/skills/gated/SKILL.md" ] && grep -q '^\.claude/skills/gated/SKILL\.md ' "$proj/.standards-checksums"; then pass; else fail "$(cat "$proj/.skills.out"; cat "$proj/.standards-checksums" 2>/dev/null)"; fi

echo -n "Test 16: un-declaring removes an unmodified gated skill, drops its checksum, keeps plain... "
skills "$proj" "" claude-code
if [ ! -f "$proj/.claude/skills/gated/SKILL.md" ] && ! grep -q 'gated/SKILL' "$proj/.standards-checksums" \
   && grep -qi 'removed' "$proj/.skills.out" && [ -f "$proj/.claude/skills/plain/SKILL.md" ]; then pass; else fail "$(cat "$proj/.skills.out"; ls -R "$proj/.claude" 2>/dev/null)"; fi

proj=$(make_project "sk-custom")
skills "$proj" "ui-surface" claude-code
echo "project note" >> "$proj/.claude/skills/gated/SKILL.md"
echo -n "Test 17: un-declaring keeps a customized gated skill and warns it is no longer managed... "
skills "$proj" "" claude-code
if [ -f "$proj/.claude/skills/gated/SKILL.md" ] && grep -q 'no longer managed' "$proj/.skills.out" \
   && grep -q '^\.claude/skills/gated/SKILL\.md ' "$proj/.standards-checksums"; then pass; else fail "$(cat "$proj/.skills.out")"; fi

proj=$(make_project "sk-dry")
skills "$proj" "ui-surface" claude-code
echo -n "Test 18: --dry-run announces the removal and removes nothing... "
"$SKILLS" --project-root "$proj" --skills-dir "$FIX/skills" --profiles "" --dry-run claude-code > "$proj/.skills.out" 2>&1
if grep -q 'Would remove: .*gated/SKILL.md' "$proj/.skills.out" && [ -f "$proj/.claude/skills/gated/SKILL.md" ]; then pass; else fail "$(cat "$proj/.skills.out")"; fi

proj=$(make_project "sk-agents")
echo -n "Test 19: cursor and copilot follow the same gate... "
skills "$proj" "" cursor copilot
if [ -f "$proj/.cursor/commands/plain.md" ] && [ ! -f "$proj/.cursor/commands/gated.md" ] \
   && [ -f "$proj/.github/prompts/plain.prompt.md" ] && [ ! -f "$proj/.github/prompts/gated.prompt.md" ]; then pass; else fail "$(cat "$proj/.skills.out")"; fi

proj=$(make_project "sk-direct")
printf 'version: 1\nlanguages: []\nagents: [claude-code]\nprofiles: [ui-surface]\n' > "$proj/.standards.yml"
skills "$proj" "ui-surface" claude-code
echo -n "Test 19b: a direct run with no --profiles and no STANDARDS_PROFILES reads the declared profiles and keeps the skill... "
env -u STANDARDS_PROFILES "$SKILLS" --project-root "$proj" --skills-dir "$FIX/skills" claude-code > "$proj/.skills.out" 2>&1
if [ -f "$proj/.claude/skills/gated/SKILL.md" ] && ! grep -qi 'removed' "$proj/.skills.out"; then pass; else fail "$(cat "$proj/.skills.out")"; fi

# --- sync-standards / diff-standards: block selection and pass-through -----

SYNC="$REPO_ROOT/scripts/sync-standards.sh"
DIFF="$REPO_ROOT/scripts/diff-standards.sh"

# fake_standards <proj> — .standards/ pointing at the real tree (symlinks).
fake_standards() {
    mkdir -p "$1/.standards"
    ln -s "$REPO_ROOT/standards" "$1/.standards/standards"
    ln -s "$REPO_ROOT/scripts"   "$1/.standards/scripts"
    ln -s "$REPO_ROOT/templates" "$1/.standards/templates"
}
# fake_standards_with_profiles <proj> — .standards/ whose standards/ is a copy
# of the real tree plus the two profile blocks and a gated skill, so the
# end-to-end path can be exercised before the content layer lands.
fake_standards_with_profiles() {
    mkdir -p "$1/.standards"
    cp -R "$REPO_ROOT/standards" "$1/.standards/standards"
    echo "Shared core rule." > "$1/.standards/standards/shared/blocks/profile-shared-core.md"
    echo "UI surface rule." > "$1/.standards/standards/shared/blocks/profile-ui-surface.md"
    cp "$FIX/skills/gated.md" "$1/.standards/standards/skills/gated.md"
    ln -s "$REPO_ROOT/scripts"   "$1/.standards/scripts"
    ln -s "$REPO_ROOT/templates" "$1/.standards/templates"
}
# write_yml <proj> "<agents yaml list>" "<profiles line or empty>"
write_yml() {
    {
        echo "version: 1"
        echo "languages: [typescript]"
        echo "agents: [$2]"
        echo "role: app"
        [ -n "$3" ] && echo "$3"
    } > "$1/.standards.yml"
}

# fake_standards_without_block <proj> — a copied tree with the shared-core
# block deleted, so the "block absent" path stays testable now that the real
# tree ships the block.
fake_standards_without_block() {
    mkdir -p "$1/.standards"
    cp -R "$REPO_ROOT/standards" "$1/.standards/standards"
    rm -f "$1/.standards/standards/shared/blocks/profile-shared-core.md"
    ln -s "$REPO_ROOT/scripts"   "$1/.standards/scripts"
    ln -s "$REPO_ROOT/templates" "$1/.standards/templates"
}
proj=$(make_project "sync-missing-block")
fake_standards_without_block "$proj"; write_yml "$proj" "claude-code" "profiles: [shared-core]"
echo -n "Test 20: sync with a declared profile whose block is absent warns, skips and still assembles... "
out=$(cd "$proj" && "$SYNC" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q 'profile block profile-shared-core.md not found; skipping' && [ -f "$proj/CLAUDE.md" ]; then pass; else fail "rc=$rc; $(echo "$out" | tail -5)"; fi

proj=$(make_project "sync-block")
fake_standards_with_profiles "$proj"; write_yml "$proj" "claude-code" "profiles: [shared-core]"
echo -n "Test 20b: sync puts the declared profile block under '## Profiles' in CLAUDE.md... "
out=$(cd "$proj" && "$SYNC" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && grep -q '^## Profiles$' "$proj/CLAUDE.md" && grep -q '^### Shared Core$' "$proj/CLAUDE.md" && ! grep -q 'UI surface rule' "$proj/CLAUDE.md"; then pass; else fail "rc=$rc; $(grep -n '^## ' "$proj/CLAUDE.md" 2>/dev/null | tail -4)"; fi

proj=$(make_project "sync-bogus")
fake_standards "$proj"; write_yml "$proj" "claude-code" "profiles: [bogus]"
echo -n "Test 21: sync rejects an unknown profile before writing anything... "
out=$(cd "$proj" && "$SYNC" 2>&1); rc=$?
if [ "$rc" -eq 2 ] && echo "$out" | grep -q 'Unknown profile: bogus (expected one of: shared-core, ui-surface)' && [ ! -f "$proj/CLAUDE.md" ]; then pass; else fail "rc=$rc; $(echo "$out" | tail -3)"; fi

proj=$(make_project "sync-skills")
fake_standards_with_profiles "$proj"; write_yml "$proj" "claude-code, codex" "profiles: [ui-surface]"
echo -n "Test 22: sync passes the declared profiles to the skill assembler and the Skills index... "
out=$(cd "$proj" && "$SYNC" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$proj/.claude/skills/gated/SKILL.md" ] && grep -q '^### gated$' "$proj/AGENTS.md"; then pass; else fail "rc=$rc; $(echo "$out" | tail -4)"; fi

proj=$(make_project "sync-skills-none")
fake_standards_with_profiles "$proj"; write_yml "$proj" "claude-code, codex" ""
echo -n "Test 22b: without the profile the gated skill is neither installed nor indexed... "
out=$(cd "$proj" && "$SYNC" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ ! -f "$proj/.claude/skills/gated/SKILL.md" ] && ! grep -q '^### gated$' "$proj/AGENTS.md"; then pass; else fail "rc=$rc; $(echo "$out" | tail -4)"; fi

proj=$(make_project "diff-profiles")
fake_standards_with_profiles "$proj"; write_yml "$proj" "claude-code" ""
( cd "$proj" && "$SYNC" >/dev/null 2>&1 )
write_yml "$proj" "claude-code" "profiles: [shared-core, ui-surface]"
echo -n "Test 23: diff-standards --exit-code sees the drift when profiles are declared after a sync... "
out=$(cd "$proj" && "$DIFF" --exit-code 2>&1); rc=$?
if [ "$rc" -eq 1 ] && echo "$out" | grep -q 'Shared Core' && ! echo "$out" | grep -q 'unknown prefix\|Unknown profile'; then pass; else fail "rc=$rc; $(echo "$out" | tail -4)"; fi

# Same basename in two parents: the project name is derived from the directory.
p1=$(make_project "nokey/proj"); fake_standards "$p1"; write_yml "$p1" "claude-code, codex" ""
p2=$(make_project "empty/proj"); fake_standards "$p2"; write_yml "$p2" "claude-code, codex" "profiles: []"
echo -n "Test 23b: no profiles key and profiles: [] assemble byte-identical CLAUDE.md and AGENTS.md... "
( cd "$p1" && "$SYNC" >/dev/null 2>&1 ); ( cd "$p2" && "$SYNC" >/dev/null 2>&1 )
if cmp -s "$p1/CLAUDE.md" "$p2/CLAUDE.md" && cmp -s "$p1/AGENTS.md" "$p2/AGENTS.md" && [ -f "$p1/AGENTS.md" ]; then pass; else fail "$(diff "$p1/CLAUDE.md" "$p2/CLAUDE.md" | head -5)"; fi

# --- detect-profiles.sh and doctor check_profiles ---------------------------

DETECT="$REPO_ROOT/scripts/detect-profiles.sh"
DOCTOR="$REPO_ROOT/scripts/doctor.sh"

proj=$(make_project "det-empty")
echo -n "Test 24: detect-profiles prints nothing for an empty project... "
out=$(bash "$DETECT" "$proj" 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then pass; else fail "rc=$rc out='$out'"; fi

proj=$(make_project "det-uniffi")
printf '[package]\nname = "x"\n[dependencies]\nuniffi = "0.29"\n' > "$proj/Cargo.toml"
echo -n "Test 25: detect-profiles suggests shared-core for a uniffi dependency... "
out=$(bash "$DETECT" "$proj" 2>/dev/null)
if [ "$out" = "$(printf 'shared-core\tuniffi in Cargo.toml')" ]; then pass; else fail "out='$out'"; fi

proj=$(make_project "det-shells")
mkdir -p "$proj/crates/core" "$proj/shells/apple" "$proj/apps/web"
echo -n "Test 26: detect-profiles suggests shared-core once for crates/ beside platform shells... "
out=$(bash "$DETECT" "$proj" 2>/dev/null)
if [ "$(echo "$out" | grep -c '^shared-core')" = 1 ] && echo "$out" | grep -q 'beside platform shells'; then pass; else fail "out='$out'"; fi

proj=$(make_project "det-ui")
touch "$proj/manifest.webmanifest"
printf 'version: 1\nlanguages: [typescript]\nrole: app\n' > "$proj/.standards.yml"
echo -n "Test 27: detect-profiles suggests ui-surface once for a manifest and role: app... "
out=$(bash "$DETECT" "$proj" 2>/dev/null)
if [ "$(echo "$out" | grep -c '^ui-surface')" = 1 ] && echo "$out" | grep -q 'web app manifest'; then pass; else fail "out='$out'"; fi

proj=$(make_project "doc-bogus")
printf 'version: 1\nlanguages: []\nagents: [codex]\nprofiles: [bogus]\n' > "$proj/.standards.yml"
echo -n "Test 28: doctor FAILs an unknown declared profile... "
out=$(cd "$proj" && bash "$DOCTOR" 2>&1) || true
if echo "$out" | grep 'Profiles' | grep -q "FAIL.*Unknown profile 'bogus'"; then pass; else fail "$(echo "$out" | grep Profiles)"; fi

proj=$(make_project "doc-missing-skill")
printf 'version: 1\nlanguages: []\nagents: [claude-code]\nprofiles: [ui-surface]\n' > "$proj/.standards.yml"
echo -n "Test 29: doctor WARNs when a declared profile's skill is not installed for claude-code... "
out=$(cd "$proj" && bash "$DOCTOR" 2>&1) || true
if echo "$out" | grep 'Profiles' | grep -q 'WARN.*ui-surface.*sync-standards'; then pass; else fail "$(echo "$out" | grep Profiles)"; fi

proj=$(make_project "doc-suggest")
printf '[package]\nname = "x"\n[dependencies]\nuniffi = "0.29"\n' > "$proj/Cargo.toml"
printf 'version: 1\nlanguages: [rust]\nagents: [codex]\n' > "$proj/.standards.yml"
base=$(make_project "doc-baseline")
printf 'version: 1\nlanguages: [rust]\nagents: [codex]\n' > "$base/.standards.yml"
echo -n "Test 30: doctor INFO-suggests a detected profile without changing its exit status... "
out=$(cd "$proj" && bash "$DOCTOR" 2>&1); rc=$?
(cd "$base" && bash "$DOCTOR" >/dev/null 2>&1); rc_base=$?
if echo "$out" | grep 'Profiles' | grep -q 'INFO.*shared-core looks applicable' && [ "$rc" -eq "$rc_base" ]; then pass; else fail "rc=$rc base=$rc_base; $(echo "$out" | grep Profiles)"; fi

# --- summary ----------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
