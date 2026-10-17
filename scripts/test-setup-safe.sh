#!/bin/bash
# Functional tests for Standards 1.2 safe-setup behavior.
# Each test creates a temp project, runs setup.sh, and asserts outcomes.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup.sh"
SYNC="$REPO_ROOT/scripts/sync-standards.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

TMPDIR_BASE="$(mktemp -d "${TMPDIR:-/tmp}/test-setup-safe.XXXXXX")"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

pass() { echo -e "${GREEN}✓${NC}"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}✗${NC}"; echo "  Error: $1"; FAIL=$((FAIL + 1)); }

make_project() {
    local name="$1"
    local dir="$TMPDIR_BASE/$name"
    mkdir -p "$dir"
    (cd "$dir" && git init -q \
        && git -c user.email="test@test.local" -c user.name="Test" \
               commit -q --allow-empty -m "init")
    echo "$dir"
}

# Stage a fake .standards/ checkout (symlinks into this repo) so the scripts
# under test resolve templates, blocks, Cursor commands and Gemini settings.
fake_standards() {
    local proj="$1"
    mkdir -p "$proj/.standards"
    ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
    ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
    ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
    ln -s "$REPO_ROOT/.cursor"   "$proj/.standards/.cursor"
    ln -s "$REPO_ROOT/.gemini"   "$proj/.standards/.gemini"
}

# Write a minimal .standards.yml declaring the given agents.
write_standards_yml() {
    local proj="$1"; shift
    {
        echo "version: 1"
        echo "languages:"
        echo "  - typescript"
        echo "agents:"
        for a in "$@"; do echo "  - $a"; done
        echo "role: service"
    } > "$proj/.standards.yml"
}

# Make $proj/.standards its own git repo, so `git rev-parse --show-toplevel`
# from inside it resolves to the submodule path (the #182 failure mode).
make_inner_standards_repo() {
    local proj="$1"
    mkdir -p "$proj/.standards"
    (cd "$proj/.standards" && git init -q \
        && git -c user.email="test@test.local" -c user.name="Test" \
               commit -q --allow-empty -m "init")
}

echo -e "${BLUE}Testing Standards 1.2 safe-setup behavior${NC}"
echo ""

echo -n "Test 1: setup.sh exists and is executable... "
if [ -x "$SETUP" ]; then pass; else fail "$SETUP not executable"; fi

echo -n "Test 2: lib/assembly.sh exposes assemble_agent_config_guarded... "
if bash -c "source '$REPO_ROOT/scripts/lib/assembly.sh' && type assemble_agent_config_guarded" >/dev/null 2>&1; then
    pass
else
    fail "assemble_agent_config_guarded not defined after sourcing lib/assembly.sh"
fi

echo -n "Test 3: sync-standards still passes shellcheck/syntax after refactor... "
if bash -n "$REPO_ROOT/scripts/sync-standards.sh" 2>/dev/null; then
    pass
else
    fail "sync-standards.sh has syntax errors"
fi

echo -n "Test 4: sync-standards references assembly lib... "
if grep -q "lib/assembly.sh" "$REPO_ROOT/scripts/sync-standards.sh"; then
    pass
else
    fail "sync-standards.sh does not source lib/assembly.sh"
fi

echo -n "Test 5: setup.sh preserves pre-existing AGENTS.md (no clobber)... "
proj=$(make_project "preserve-agents")
cat > "$proj/AGENTS.md" <<'EOF'
# My Custom AGENTS.md
This content must survive setup.sh.
EOF
# Stage a fake .standards/ checkout pointing at our repo so setup.sh can find templates.
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/.gemini"   "$proj/.standards/.gemini" 2>/dev/null || true
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
if grep -q "must survive setup.sh" "$proj/AGENTS.md" 2>/dev/null; then
    pass
else
    fail "AGENTS.md was clobbered by setup.sh"
fi
if [ -f "$proj/.standards-pending/AGENTS.md" ]; then
    pass_pending=true
else
    pass_pending=false
fi

echo -n "Test 6: setup.sh stages pending AGENTS.md in .standards-pending/... "
if [ "$pass_pending" = true ]; then pass; else fail "no pending AGENTS.md written"; fi

echo -n "Test 7: detect-agents returns claude-code when CLAUDE.md exists... "
proj=$(make_project "detect-claude")
touch "$proj/CLAUDE.md"
result=$(bash -c "source '$REPO_ROOT/scripts/lib/detect-agents.sh' && detect_installed_agents '$proj'")
if echo "$result" | grep -qw "claude-code"; then pass; else fail "got: $result"; fi

echo -n "Test 8: detect-agents returns empty for greenfield project... "
proj=$(make_project "detect-empty")
result=$(bash -c "source '$REPO_ROOT/scripts/lib/detect-agents.sh' && detect_installed_agents '$proj'")
if [ -z "$(echo "$result" | tr -d '[:space:]')" ]; then pass; else fail "got: $result"; fi

echo -n "Test 9: setup.sh --agents detect installs only detected agents... "
proj=$(make_project "detect-only")
touch "$proj/CLAUDE.md"
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
(cd "$proj" && "$SETUP" --agents detect --languages typescript >/dev/null 2>&1) || true
if [ ! -f "$proj/.cursorrules" ] && [ ! -f "$proj/.aiderrc" ]; then
    pass
else
    fail "unused-agent configs installed (cursorrules or aiderrc present)"
fi

echo -n "Test 10: {{PROJECT_NAME}} resolves from package.json... "
proj=$(make_project "vars-pkg-json")
cat > "$proj/package.json" <<'EOF'
{ "name": "acme-widget", "version": "1.0.0" }
EOF
result=$(bash -c "source '$REPO_ROOT/scripts/lib/template-vars.sh' && resolve_project_name '$proj'")
if [ "$result" = "acme-widget" ]; then pass; else fail "got: $result"; fi

echo -n "Test 11: {{PROJECT_NAME}} falls back to directory name... "
proj=$(make_project "fallback-dirname")
result=$(bash -c "source '$REPO_ROOT/scripts/lib/template-vars.sh' && resolve_project_name '$proj'")
if [ "$result" = "fallback-dirname" ]; then pass; else fail "got: $result"; fi

echo -n "Test 12: assembled CLAUDE.md has no literal {{vars}}... "
proj=$(make_project "no-literal-vars")
cat > "$proj/package.json" <<'EOF'
{ "name": "testproj" }
EOF
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
if [ -f "$proj/CLAUDE.md" ] && ! grep -q "{{" "$proj/CLAUDE.md"; then
    pass
else
    fail "CLAUDE.md contains literal {{...}} or was not written"
fi

echo -n "Test 13: setup.sh does NOT install standards-review.yml by default... "
proj=$(make_project "no-workflow")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/.github"   "$proj/.standards/.github"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
if [ ! -f "$proj/.github/workflows/standards-review.yml" ]; then pass; else fail "workflow installed without --workflow"; fi

echo -n "Test 14: setup.sh --workflow DOES install standards-review.yml... "
proj=$(make_project "with-workflow")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/.github"   "$proj/.standards/.github"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript --workflow >/dev/null 2>&1) || true
if [ -f "$proj/.github/workflows/standards-review.yml" ]; then pass; else fail "workflow not installed with --workflow"; fi

echo -n "Test 15: MERGE_PLAN.md is written when pending files exist... "
proj=$(make_project "merge-plan")
cat > "$proj/AGENTS.md" <<'EOF'
# Existing AGENTS.md (customized)
EOF
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
if [ -f "$proj/.standards-pending/MERGE_PLAN.md" ] \
   && grep -q "AGENTS.md" "$proj/.standards-pending/MERGE_PLAN.md"; then
    pass
else
    fail "MERGE_PLAN.md missing or does not list AGENTS.md"
fi

echo -n "Test 16: MERGE_PLAN.md NOT written when no pending files... "
proj=$(make_project "no-merge-plan")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
if [ ! -f "$proj/.standards-pending/MERGE_PLAN.md" ]; then pass; else fail "unexpected MERGE_PLAN.md"; fi

echo -n "Test 17: MERGE_PLAN.md renders comma-separated agents as separate bullets... "
proj=$(make_project "multi-agent")
cat > "$proj/AGENTS.md" <<'EOF'
# Existing AGENTS.md (customized)
EOF
cat > "$proj/CLAUDE.md" <<'EOF'
# Existing CLAUDE.md (customized)
EOF
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
(cd "$proj" && "$SETUP" --agents claude-code,codex --languages typescript >/dev/null 2>&1) || true
plan="$proj/.standards-pending/MERGE_PLAN.md"
if [ -f "$plan" ] && grep -q "^- claude-code$" "$plan" && grep -q "^- codex$" "$plan" && ! grep -q "claude-code,codex" "$plan"; then
    pass
else
    fail "multi-agent list not rendered as separate bullets"
fi

echo -n "Test 18: {{PROJECT_NAME}} resolves safely for scoped npm name... "
proj=$(make_project "scoped-name")
cat > "$proj/package.json" <<'EOF'
{ "name": "@acme/widget" }
EOF
result=$(bash -c "source '$REPO_ROOT/scripts/lib/template-vars.sh' && resolve_project_name '$proj'")
if [ "$result" = "@acme/widget" ]; then pass; else fail "got: $result"; fi

echo -n "Test 19: template-vars handles & in project name without sed breakage... "
proj=$(make_project "amp-name")
# Simulate a dirname-fallback case by removing package.json and renaming dir
mv "$proj" "$TMPDIR_BASE/a&b"
proj="$TMPDIR_BASE/a&b"
tmpfile=$(mktemp)
printf '# {{PROJECT_NAME}} — Guide\n' > "$tmpfile"
bash -c "source '$REPO_ROOT/scripts/lib/template-vars.sh' && resolve_template_vars '$tmpfile' '$proj'"
if grep -q "^# a&b — Guide$" "$tmpfile"; then pass; else fail "got: $(cat "$tmpfile")"; fi
rm -f "$tmpfile"

echo -n "Test 20: template vars resolve from project root even when assembling to pending/... "
proj=$(make_project "pending-vars")
cat > "$proj/package.json" <<'EOF'
{ "name": "pending-proj" }
EOF
cat > "$proj/CLAUDE.md" <<'EOF'
# Existing CLAUDE.md
EOF
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
if [ -f "$proj/.standards-pending/CLAUDE.md" ] && grep -q "^# pending-proj — Claude Code Guide$" "$proj/.standards-pending/CLAUDE.md" && ! grep -q "{{" "$proj/.standards-pending/CLAUDE.md"; then
    pass
else
    fail "pending CLAUDE.md did not resolve {{PROJECT_NAME}} from consumer project"
fi

echo -n "Test 21: setup installs .trufflehog-ignore when absent... "
proj=$(make_project "th-install")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
if [ -f "$proj/.trufflehog-ignore" ]; then pass; else fail ".trufflehog-ignore not installed"; fi

echo -n "Test 22: setup does NOT clobber an existing .trufflehog-ignore... "
proj=$(make_project "th-preserve")
printf '# my custom allowlist\n(^|/)secret-fixtures/\n' > "$proj/.trufflehog-ignore"
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
if grep -q "my custom allowlist" "$proj/.trufflehog-ignore"; then pass; else fail "existing .trufflehog-ignore was clobbered"; fi

echo -n "Test 23: setup does NOT install trufflehog.yml without --workflow... "
proj=$(make_project "th-no-workflow")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
if [ ! -f "$proj/.github/workflows/trufflehog.yml" ]; then pass; else fail "trufflehog.yml installed without --workflow"; fi

echo -n "Test 24: setup --workflow DOES install trufflehog.yml... "
proj=$(make_project "th-workflow")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript --workflow >/dev/null 2>&1) || true
if [ -f "$proj/.github/workflows/trufflehog.yml" ]; then pass; else fail "trufflehog.yml not installed with --workflow"; fi

# --- #182: sync-standards honours agents:, aliases opt-in, submodule guard ---

echo -n "Test 25: sync-standards with agents: [codex] does NOT install Cursor/Gemini/Claude extras... "
proj=$(make_project "sync-gate-codex")
fake_standards "$proj"
write_standards_yml "$proj" codex
out=$(cd "$proj" && "$SYNC" 2>&1) || true
if [ ! -d "$proj/.cursor/commands" ] && [ ! -f "$proj/.gemini/settings.json" ] \
   && [ ! -f "$proj/.claude/settings.json" ] && [ ! -f "$proj/.claude/skills/merge-standards.md" ] \
   && [ -f "$proj/AGENTS.md" ]; then
    pass
else
    fail "undeclared agent side effects installed; output: $out"
fi

echo -n "Test 26: sync-standards with agents: [cursor, gemini, claude-code] installs their extras... "
proj=$(make_project "sync-gate-all")
fake_standards "$proj"
write_standards_yml "$proj" cursor gemini claude-code
out=$(cd "$proj" && "$SYNC" 2>&1) || true
if [ -d "$proj/.cursor/commands" ] && [ -f "$proj/.gemini/settings.json" ] \
   && [ -f "$proj/.claude/skills/merge-standards.md" ]; then
    pass
else
    fail "declared agent extras missing; output: $out"
fi

echo -n "Test 27: sync-standards never touches git aliases without --aliases... "
proj=$(make_project "sync-no-aliases")
fake_standards "$proj"
write_standards_yml "$proj" codex
out=$(cd "$proj" && "$SYNC" --dry-run 2>&1) || true
if ! echo "$out" | grep -qi "would set up git aliases" && ! echo "$out" | grep -qi "checking git aliases"; then
    pass
else
    fail "git alias setup ran without --aliases: $out"
fi

echo -n "Test 28: sync-standards --aliases opts in to git alias setup... "
out=$(cd "$proj" && "$SYNC" --dry-run --aliases 2>&1) || true
if echo "$out" | grep -qi "would set up git aliases"; then pass; else fail "--aliases did not enable alias setup: $out"; fi

echo -n "Test 29: sync-standards refuses to run from inside .standards/... "
proj=$(make_project "inside-submodule")
make_inner_standards_repo "$proj"
rc=0; out=$(cd "$proj/.standards" && "$SYNC" --dry-run 2>&1) || rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "inside" && echo "$out" | grep -q "./.standards/scripts/sync-standards.sh"; then
    pass
else
    fail "expected refusal (rc=$rc): $out"
fi

echo -n "Test 30: setup.sh refuses to run from inside .standards/... "
rc=0; out=$(cd "$proj/.standards" && "$SETUP" --dry-run 2>&1) || rc=$?
if [ "$rc" -ne 0 ] && echo "$out" | grep -q "inside" && echo "$out" | grep -q "./.standards/scripts/setup.sh"; then
    pass
else
    fail "expected refusal (rc=$rc): $out"
fi

echo -n "Test 31: sync-standards continues from the local checkout when the remote is unreachable... "
proj=$(make_project "sync-offline")
make_inner_standards_repo "$proj"
fake_standards "$proj"
# Cached origin/main that differs from HEAD, plus an unreachable remote: the
# fetch fails, and the stale comparison must not trigger a doomed pull.
(cd "$proj/.standards" \
    && git update-ref refs/remotes/origin/main HEAD \
    && git -c user.email="test@test.local" -c user.name="Test" commit -q --allow-empty -m "local" \
    && git remote add origin "$TMPDIR_BASE/does-not-exist.git")
write_standards_yml "$proj" codex
rc=0; out=$(cd "$proj" && "$SYNC" 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && [ -f "$proj/AGENTS.md" ] && echo "$out" | grep -q "Could not fetch"; then
    pass
else
    fail "expected sync to continue offline (rc=$rc): $out"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}$FAIL failures${NC}"
    exit 1
fi
echo -e "${GREEN}All $PASS tests passed!${NC}"
