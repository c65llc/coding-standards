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
   && [ ! -f "$proj/.claude/settings.json" ] && [ ! -f "$proj/.claude/skills/merge-standards/SKILL.md" ] \
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
   && [ -f "$proj/.claude/skills/merge-standards/SKILL.md" ]; then
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

# --- CLI contract: --help / unknown options (issue #181) ---------------------

echo -n "Test 32: setup.sh --help exits 0 and prints usage... "
proj=$(make_project "help-exit")
help_rc=0
help_out=$(cd "$proj" && "$SETUP" --help 2>&1) || help_rc=$?
if [ "$help_rc" -eq 0 ] && echo "$help_out" | grep -q "^Usage:" && echo "$help_out" | grep -q -- "--agents"; then
    pass
else
    fail "rc=$help_rc, output: $help_out"
fi

echo -n "Test 33: setup.sh --help writes nothing to the project... "
leftover=$(cd "$proj" && git status --porcelain --untracked-files=all 2>/dev/null)
if [ -z "$leftover" ] && [ ! -f "$proj/.git/hooks/post-merge" ]; then
    pass
else
    fail "--help modified the project: $leftover"
fi

echo -n "Test 34: setup.sh -h is an alias for --help... "
if (cd "$proj" && "$SETUP" -h >/dev/null 2>&1); then pass; else fail "-h did not exit 0"; fi

echo -n "Test 35: unknown option exits 2 with 'Unknown option' + usage... "
proj=$(make_project "unknown-flag")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
unk_rc=0
unk_out=$(cd "$proj" && "$SETUP" --bogus 2>&1) || unk_rc=$?
if [ "$unk_rc" -eq 2 ] && echo "$unk_out" | grep -q "Unknown option: --bogus" && echo "$unk_out" | grep -q "^Usage:"; then
    pass
else
    fail "rc=$unk_rc, output: $unk_out"
fi

echo -n "Test 36: unknown option writes nothing to the project... "
leftover=$(cd "$proj" && git status --porcelain --untracked-files=all 2>/dev/null | grep -v '^?? .standards/' || true)
if [ -z "$leftover" ] && [ ! -f "$proj/.git/hooks/post-merge" ] && [ ! -f "$proj/.standards.yml" ]; then
    pass
else
    fail "unknown option modified the project: $leftover"
fi

echo -n "Test 37: option missing its value exits 2... "
miss_rc=0
(cd "$proj" && "$SETUP" --agents >/dev/null 2>&1) || miss_rc=$?
if [ "$miss_rc" -eq 2 ]; then pass; else fail "expected exit 2, got $miss_rc"; fi

echo -n "Test 37a: option followed by another flag (--languages --help) exits 2 and writes nothing... "
optval_rc=0
optval_out=$(cd "$proj" && "$SETUP" --languages --help 2>&1) || optval_rc=$?
leftover=$(cd "$proj" && git status --porcelain --untracked-files=all 2>/dev/null | grep -v '^?? .standards/' || true)
if [ "$optval_rc" -eq 2 ] && echo "$optval_out" | grep -q "requires a value" \
    && [ -z "$leftover" ] && [ ! -f "$proj/.standards.yml" ] && [ ! -d "$proj/.claude" ]; then
    pass
else
    fail "rc=$optval_rc, leftover='$leftover', output: $optval_out"
fi

echo -n "Test 37b: empty equals form (--agents=) exits 2 and writes nothing... "
eq_rc=0
eq_out=$(cd "$proj" && "$SETUP" --agents= 2>&1) || eq_rc=$?
leftover=$(cd "$proj" && git status --porcelain --untracked-files=all 2>/dev/null | grep -v '^?? .standards/' || true)
if [ "$eq_rc" -eq 2 ] && echo "$eq_out" | grep -q "requires a value" \
    && [ -z "$leftover" ] && [ ! -f "$proj/.standards.yml" ] && [ ! -f "$proj/.git/hooks/post-merge" ]; then
    pass
else
    fail "rc=$eq_rc, leftover='$leftover', output: $eq_out"
fi

echo -n "Test 37c: empty or whitespace-only agent fields (--agents=, / codex, / ,cursor / '   ' / 'codex, ,cursor') exit 2 and write nothing... "
empty_ok=true
empty_detail=""
for bad in "," "codex," ",cursor" "codex,,cursor" "   " "codex, ,cursor"; do
    bad_rc=0
    bad_out=$(cd "$proj" && "$SETUP" --agents="$bad" --languages=typescript 2>&1) || bad_rc=$?
    if [ "$bad_rc" -ne 2 ] || ! echo "$bad_out" | grep -q "empty agent name"; then
        empty_ok=false; empty_detail="$empty_detail [--agents=$bad rc=$bad_rc]"
    fi
done
leftover=$(cd "$proj" && git status --porcelain --untracked-files=all 2>/dev/null | grep -v '^?? .standards/' || true)
if [ "$empty_ok" = true ] && [ -z "$leftover" ] && [ ! -f "$proj/.standards.yml" ] && [ ! -f "$proj/.trufflehog-ignore" ]; then
    pass
else
    fail "leftover='$leftover'$empty_detail"
fi

# --- Agent-scoped install: explicit --agents installs only that agent's artifacts

echo -n "Test 37d: surrounding whitespace in agent fields is tolerated (--agents='codex , cursor')... "
ws_rc=0
ws_out=$(cd "$proj" && "$SETUP" --agents='codex , cursor' --languages=typescript --dry-run 2>&1) || ws_rc=$?
if [ "$ws_rc" -eq 0 ] && echo "$ws_out" | grep -q "AGENTS.md" && echo "$ws_out" | grep -q "cursorrules"; then
    pass
else
    fail "rc=$ws_rc, output: $ws_out"
fi

echo -n "Test 37e: setup.sh --help works from inside .standards/ (guard runs after parsing)... "
proj=$(make_project "help-inside-submodule")
make_inner_standards_repo "$proj"
hi_rc=0
hi_out=$(cd "$proj/.standards" && "$SETUP" --help 2>&1) || hi_rc=$?
if [ "$hi_rc" -eq 0 ] && echo "$hi_out" | grep -q "^Usage:"; then pass; else fail "rc=$hi_rc, output: $hi_out"; fi

echo -n "Test 38: --agents codex writes only AGENTS.md artifacts (no hooks, aliases, Cursor, .claude, .gemini)... "
proj=$(make_project "codex-only")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/.gemini"   "$proj/.standards/.gemini" 2>/dev/null || true
ln -s "$REPO_ROOT/.cursor"   "$proj/.standards/.cursor" 2>/dev/null || true
# Isolate global git config so we can prove no aliases were written.
fake_home="$TMPDIR_BASE/codex-only-home"; mkdir -p "$fake_home"
(cd "$proj" && HOME="$fake_home" GIT_CONFIG_GLOBAL="$fake_home/.gitconfig" \
    "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
codex_errs=""
[ -f "$proj/AGENTS.md" ]                         || codex_errs="$codex_errs AGENTS.md-missing"
[ -f "$proj/.standards.yml" ]                    || codex_errs="$codex_errs .standards.yml-missing"
[ ! -e "$proj/.git/hooks/post-merge" ]           || codex_errs="$codex_errs post-merge-hook"
[ ! -e "$proj/.cursor" ]                         || codex_errs="$codex_errs .cursor/"
[ ! -e "$proj/.cursorrules" ]                    || codex_errs="$codex_errs .cursorrules"
[ ! -e "$proj/.claude" ]                         || codex_errs="$codex_errs .claude/"
[ ! -e "$proj/CLAUDE.md" ]                       || codex_errs="$codex_errs CLAUDE.md"
[ ! -e "$proj/.gemini" ]                         || codex_errs="$codex_errs .gemini/"
[ ! -e "$proj/.aiderrc" ]                        || codex_errs="$codex_errs .aiderrc"
[ ! -e "$proj/.aider-instructions.md" ]          || codex_errs="$codex_errs .aider-instructions.md"
[ ! -e "$proj/.github/copilot-instructions.md" ] || codex_errs="$codex_errs copilot-instructions.md"
if [ -f "$fake_home/.gitconfig" ] && grep -q "^\[alias\]" "$fake_home/.gitconfig" 2>/dev/null; then
    codex_errs="$codex_errs git-aliases-written"
fi
if [ -z "$codex_errs" ]; then pass; else fail "unexpected artifacts:$codex_errs"; fi

echo -n "Test 39: --agents codex,cursor installs Cursor commands but not .claude or .gemini... "
proj=$(make_project "codex-cursor")
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/.gemini"   "$proj/.standards/.gemini" 2>/dev/null || true
ln -s "$REPO_ROOT/.cursor"   "$proj/.standards/.cursor" 2>/dev/null || true
fake_home="$TMPDIR_BASE/codex-cursor-home"; mkdir -p "$fake_home"
(cd "$proj" && HOME="$fake_home" GIT_CONFIG_GLOBAL="$fake_home/.gitconfig" \
    "$SETUP" --agents codex,cursor --languages typescript >/dev/null 2>&1) || true
if [ -f "$proj/AGENTS.md" ] && [ -f "$proj/.cursorrules" ] && [ -d "$proj/.cursor/commands" ] \
   && [ ! -e "$proj/.claude" ] && [ ! -e "$proj/.gemini" ]; then
    pass
else
    fail "expected AGENTS.md + .cursorrules + .cursor/commands only"
fi

echo -n "Test 40: --agents detect still installs git hooks (legacy behaviour preserved)... "
proj=$(make_project "detect-hooks")
touch "$proj/AGENTS.md"
mkdir -p "$proj/.standards"
ln -s "$REPO_ROOT/standards" "$proj/.standards/standards"
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
fake_home="$TMPDIR_BASE/detect-hooks-home"; mkdir -p "$fake_home"
(cd "$proj" && HOME="$fake_home" GIT_CONFIG_GLOBAL="$fake_home/.gitconfig" \
    "$SETUP" --agents detect --languages typescript >/dev/null 2>&1) || true
if [ -f "$proj/.git/hooks/post-merge" ]; then pass; else fail "post-merge hook not installed in detect mode"; fi

echo -n "Test 41: swift-only app assembly contains no TypeScript/Dart-specific lines (#193)... "
proj=$(make_project "swift-only-assembly")
out="$proj/AGENTS.md"
bash "$REPO_ROOT/scripts/assemble-config.sh" --project-root "$proj" codex \
    "$REPO_ROOT/standards/shared/blocks" \
    "$REPO_ROOT/standards/agents/claude-code/base-claude-code.md" \
    "$out" lang-swift.md role-app.md >/dev/null 2>&1 || true
if [ ! -f "$out" ]; then
    fail "assemble-config.sh did not write $out"
elif grep -q 'tsc -b' "$out"; then
    fail "swift-only assembly still contains 'tsc -b' (testing-policy.md leak)"
elif grep -q '`const` constructors' "$out"; then
    fail "swift-only assembly still contains Dart '\`const\` constructors' (role-app.md leak)"
elif ! grep -q 'Swift 6' "$out"; then
    fail "swift-only assembly does not contain the Swift 6 language block"
else
    pass
fi

echo -n "Test 42: typescript-only assembly keeps the 'tsc -b' build guidance in its language block... "
proj=$(make_project "ts-only-assembly")
out="$proj/AGENTS.md"
bash "$REPO_ROOT/scripts/assemble-config.sh" --project-root "$proj" codex \
    "$REPO_ROOT/standards/shared/blocks" \
    "$REPO_ROOT/standards/agents/claude-code/base-claude-code.md" \
    "$out" lang-typescript.md role-service.md >/dev/null 2>&1 || true
if [ -f "$out" ] && grep -q 'tsc -b' "$out"; then pass; else fail "'tsc -b' missing from typescript assembly"; fi

# --- Monorepo members (#179): setup, sync and diff iterate members -------------

# Fixture: root declares members server/ (Python manifest, no member config yet)
# and web/ (TypeScript, with its own .standards.yml). The root itself has no
# manifests, so every language must come from the members.
make_monorepo() {
    local name="$1"
    local m
    m=$(make_project "$name")
    fake_standards "$m"
    mkdir -p "$m/server/src" "$m/web/src"
    printf 'version: 1\nlanguages: []\nagents:\n  - codex\nrole: service\nmembers:\n  - server\n  - web\n' > "$m/.standards.yml"
    printf '[project]\nname = "server"\n' > "$m/server/pyproject.toml"
    printf 'version: 1\nlanguages:\n  - typescript\n' > "$m/web/.standards.yml"
    printf '{"name":"web"}\n' > "$m/web/package.json"
    printf '{"compilerOptions":{"strict":true}}\n' > "$m/web/tsconfig.json"
    echo "$m"
}

echo -n "Test 43: setup.sh keeps members:, assembles the members' blocks into the root agent config, and keeps the root's own languages list... "
proj=$(make_monorepo "setup-members")
(cd "$proj" && "$SETUP" --agents codex >/dev/null 2>&1) || true
errs=""
grep -q '^members:' "$proj/.standards.yml"                       || errs="$errs members-key-dropped"
grep -q '^  - server$' "$proj/.standards.yml"                     || errs="$errs server-not-listed"
grep -q '^  - web$' "$proj/.standards.yml"                        || errs="$errs web-not-listed"
# The union is for agent configs only: a non-empty root languages: list makes
# lint-standards run language checks against the root, which has no manifests.
grep -q '^languages: \[\]$' "$proj/.standards.yml"                || errs="$errs root-languages-not-empty"
grep -q '^  - python$' "$proj/.standards.yml"                     && errs="$errs python-leaked-into-root-languages"
grep -q '^  - typescript$' "$proj/.standards.yml"                 && errs="$errs typescript-leaked-into-root-languages"
grep -q 'Member languages' "$proj/.standards.yml"                 || errs="$errs member-languages-note-missing"
[ -f "$proj/AGENTS.md" ] && grep -q 'tsc -b' "$proj/AGENTS.md"    || errs="$errs typescript-block-missing"
[ -f "$proj/AGENTS.md" ] && grep -qi 'ruff' "$proj/AGENTS.md"     || errs="$errs python-block-missing"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 43b: after setup.sh, lint-standards.sh does not run a member's language checks against the aggregator root... "
lint_json=$(bash "$REPO_ROOT/scripts/lint-standards.sh" --format json "$proj" 2>/dev/null || true)
root_ts=$(printf '%s' "$lint_json" | tr -d '\n' | grep -o '"check": "typescript/strict-tsconfig",[[:space:]]*"member": "\."' || true)
web_ts=$(printf '%s' "$lint_json" | tr -d '\n' | grep -o '"check": "typescript/strict-tsconfig",[[:space:]]*"member": "web"' || true)
if [ -z "$root_ts" ] && [ -n "$web_ts" ]; then pass; else
    fail "root_ts='$root_ts' web_ts='$web_ts'"; fi

echo -n "Test 44: setup.sh bootstraps a .standards.yml for a declared member that has none, and leaves an existing one alone... "
errs=""
[ -f "$proj/server/.standards.yml" ]                              || errs="$errs server-config-missing"
grep -q '^  - python$' "$proj/server/.standards.yml" 2>/dev/null  || errs="$errs server-python-missing"
grep -q '^members:' "$proj/server/.standards.yml" 2>/dev/null     && errs="$errs server-config-has-members"
[ "$(cat "$proj/web/.standards.yml")" = "$(printf 'version: 1\nlanguages:\n  - typescript')" ] || errs="$errs web-config-rewritten"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 45: setup.sh --dry-run names the member config it would write and writes nothing... "
proj=$(make_monorepo "setup-members-dry")
dry_out=$(cd "$proj" && "$SETUP" --agents codex --dry-run 2>&1) || true
if echo "$dry_out" | grep -q 'server/.standards.yml' && [ ! -e "$proj/server/.standards.yml" ] && [ ! -e "$proj/AGENTS.md" ]; then pass; else
    fail "dry-run wrote files or did not mention the member config"; fi

echo -n "Test 46: sync-standards.sh unions member languages into the root agent config and lists the members... "
proj=$(make_monorepo "sync-members")
printf 'version: 1\nlanguages:\n  - python\n' > "$proj/server/.standards.yml"
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
errs=""
echo "$sync_out" | grep -q 'server'                               || errs="$errs server-not-listed"
echo "$sync_out" | grep -q 'web'                                  || errs="$errs web-not-listed"
[ -f "$proj/AGENTS.md" ] && grep -q 'tsc -b' "$proj/AGENTS.md"    || errs="$errs typescript-block-missing"
[ -f "$proj/AGENTS.md" ] && grep -qi 'ruff' "$proj/AGENTS.md"     || errs="$errs python-block-missing"
if [ -z "$errs" ]; then pass; else fail "$errs: $sync_out"; fi

echo -n "Test 47: diff-standards.sh --exit-code agrees with sync on a monorepo (no drift right after a sync)... "
diff_rc=0
(cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1) || diff_rc=$?
if [ "$diff_rc" -eq 0 ]; then pass; else fail "diff-standards reported drift (exit $diff_rc) immediately after sync"; fi

echo -n "Test 48: sync-standards.sh warns about a declared member that does not exist and still completes... "
printf 'version: 1\nlanguages: []\nagents:\n  - codex\nrole: service\nmembers:\n  - server\n  - ghost\n' > "$proj/.standards.yml"
sync_rc=0
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || sync_rc=$?
if [ "$sync_rc" -eq 0 ] && echo "$sync_out" | grep -qi 'ghost' && echo "$sync_out" | grep -q 'Sync complete'; then pass; else
    fail "rc=$sync_rc: $sync_out"; fi

echo -n "Test 49: a member whose config declares 'languages: []' contributes nothing to the root agent config (no detection behind its back)... "
proj=$(make_monorepo "setup-members-empty-langs")
printf 'version: 1\nlanguages: []\n' > "$proj/web/.standards.yml"   # web/ still has tsconfig.json and package.json
(cd "$proj" && "$SETUP" --agents codex >/dev/null 2>&1) || true
errs=""
[ -f "$proj/AGENTS.md" ]                                          || errs="$errs agents-missing"
grep -q 'tsc -b' "$proj/AGENTS.md" 2>/dev/null                    && errs="$errs typescript-assembled-despite-empty-list"
grep -qi 'ruff' "$proj/AGENTS.md" 2>/dev/null                     || errs="$errs python-block-missing"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 50: setup.sh --languages names the root's own languages and still unions the members' into the agent config... "
proj=$(make_monorepo "setup-members-override")
(cd "$proj" && "$SETUP" --agents codex --languages python >/dev/null 2>&1) || true
errs=""
grep -q '^  - python$' "$proj/.standards.yml"                     || errs="$errs python-not-in-root-languages"
grep -q '^  - typescript$' "$proj/.standards.yml"                 && errs="$errs typescript-leaked-into-root-languages"
[ -f "$proj/AGENTS.md" ] && grep -q 'tsc -b' "$proj/AGENTS.md"    || errs="$errs typescript-block-missing"
[ -f "$proj/AGENTS.md" ] && grep -qi 'ruff' "$proj/AGENTS.md"     || errs="$errs python-block-missing"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 51: zero-config bootstrap: a tsconfig.json under apps/web feeds the agent config but not the root languages list... "
proj=$(make_project "setup-zero-config-monorepo")
fake_standards "$proj"
mkdir -p "$proj/apps/web"
printf '{"name":"web"}\n' > "$proj/apps/web/package.json"
printf '{"compilerOptions":{"strict":true}}\n' > "$proj/apps/web/tsconfig.json"
setup_out=$(cd "$proj" && "$SETUP" --agents codex 2>&1) || true
errs=""
grep -q '^languages: \[\]$' "$proj/.standards.yml"                || errs="$errs root-languages-not-empty"
grep -q '^  - typescript$' "$proj/.standards.yml"                 && errs="$errs typescript-leaked-into-root-languages"
[ -f "$proj/AGENTS.md" ] && grep -q 'tsc -b' "$proj/AGENTS.md"    || errs="$errs typescript-block-missing"
echo "$setup_out" | grep -q 'sub-roots.*typescript'               || errs="$errs sub-root-hint-missing"
lint_json=$(bash "$REPO_ROOT/scripts/lint-standards.sh" --format json "$proj" 2>/dev/null || true)
printf '%s' "$lint_json" | tr -d '\n' | grep -q '"check": "typescript/strict-tsconfig",[[:space:]]*"member": "\."' && errs="$errs root-ts-check-ran"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$setup_out" | grep -i 'sub-roots' | head -2)"; fi

echo -n "Test 52: setup.sh never writes a member config through a symlink (dangling link to a path outside the checkout)... "
proj=$(make_monorepo "setup-member-config-symlink")
link_target_dir=$(mktemp -d "${TMPDIR:-/tmp}/setup-safe-outside.XXXXXX")
link_target="$link_target_dir/standards.yml"
ln -s "$link_target" "$proj/server/.standards.yml"
setup_out=$(cd "$proj" && "$SETUP" --agents codex 2>&1) || true
errs=""
[ -e "$link_target" ]                                             && errs="$errs wrote-through-symlink"
[ -L "$proj/server/.standards.yml" ]                              || errs="$errs symlink-replaced"
echo "$setup_out" | grep -q "server' rejected: its .standards.yml is a symlink" || errs="$errs no-rejection-message"
rm -rf "$link_target_dir"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$setup_out" | grep -i 'symlink\|members' | head -3)"; fi

echo -n "Test 53: setup.sh re-quotes a member path that YAML needs quoted, so the regenerated config re-reads to the same member... "
proj=$(make_monorepo "setup-member-quoting")
mkdir -p "$proj/#svc/src"
printf 'version: 1\nlanguages:\n  - python\n' > "$proj/#svc/.standards.yml"
printf 'version: 1\nlanguages: []\nagents:\n  - codex\nrole: service\nmembers:\n  - "#svc"\n  - web\n' > "$proj/.standards.yml"
(cd "$proj" && "$SETUP" --agents codex >/dev/null 2>&1) || true
errs=""
grep -q '^  - "#svc"$' "$proj/.standards.yml"                      || errs="$errs svc-not-requoted"
grep -q '^  - web$' "$proj/.standards.yml"                        || errs="$errs web-not-plain"
lint_json=$(bash "$REPO_ROOT/scripts/lint-standards.sh" --format json "$proj" 2>/dev/null || true)
printf '%s' "$lint_json" | tr -d '\n' | grep -q '"members": *\[ *"\." *, *"#svc" *, *"web" *\]' || errs="$errs svc-not-resolved-after-rewrite"
if [ -z "$errs" ]; then pass; else fail "$errs: $(grep -A3 '^members:' "$proj/.standards.yml" | tr '\n' '|')"; fi

echo -n "Test 54: sync and diff build the same root + sub-root + member union as setup (no drift, sub-root block kept)... "
proj=$(make_project "sync-subroot-union")
fake_standards "$proj"
mkdir -p "$proj/apps/web"
printf '[project]\nname = "root"\n' > "$proj/pyproject.toml"
printf '{"name":"web"}\n' > "$proj/apps/web/package.json"
printf '{"compilerOptions":{"strict":true}}\n' > "$proj/apps/web/tsconfig.json"
(cd "$proj" && "$SETUP" --agents codex >/dev/null 2>&1) || true
errs=""
grep -q '^  - python$' "$proj/.standards.yml"                     || errs="$errs python-not-in-root-languages"
grep -q '^  - typescript$' "$proj/.standards.yml"                 && errs="$errs typescript-leaked-into-root-languages"
[ -f "$proj/AGENTS.md" ] && grep -q 'tsc -b' "$proj/AGENTS.md"    || errs="$errs setup-typescript-block-missing"
(cd "$proj" && "$SYNC" >/dev/null 2>&1) || true
grep -q 'tsc -b' "$proj/AGENTS.md"                                || errs="$errs sync-dropped-typescript-block"
grep -qi 'ruff' "$proj/AGENTS.md"                                 || errs="$errs sync-dropped-python-block"
diff_rc=0
(cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1) || diff_rc=$?
[ "$diff_rc" -eq 0 ]                                              || errs="$errs diff-reports-drift($diff_rc)"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 55: bootstrapping a config-less parent member does not detect through a nested member's manifests... "
proj=$(make_project "setup-nested-bootstrap")
fake_standards "$proj"
mkdir -p "$proj/packages/web"
printf 'version: 1\nlanguages: []\nagents:\n  - codex\nrole: service\nmembers:\n  - packages\n  - packages/web\n' > "$proj/.standards.yml"
printf 'version: 1\nlanguages:\n  - typescript\n' > "$proj/packages/web/.standards.yml"
printf '{"name":"web"}\n' > "$proj/packages/web/package.json"
printf '{"compilerOptions":{"strict":true}}\n' > "$proj/packages/web/tsconfig.json"
(cd "$proj" && "$SETUP" --agents codex >/dev/null 2>&1) || true
errs=""
[ -f "$proj/packages/.standards.yml" ]                            || errs="$errs parent-config-not-bootstrapped"
grep -q '^languages: \[\]$' "$proj/packages/.standards.yml" 2>/dev/null || errs="$errs parent-languages-not-empty"
grep -q 'typescript' "$proj/packages/.standards.yml" 2>/dev/null   && errs="$errs child-language-leaked-into-parent"
[ -f "$proj/AGENTS.md" ] && grep -q 'tsc -b' "$proj/AGENTS.md"    || errs="$errs typescript-block-missing"
if [ -z "$errs" ]; then pass; else fail "$errs: $(cat "$proj/packages/.standards.yml" 2>/dev/null | tr '\n' '|')"; fi

echo -n "Test 56: a language both the root (tooling manifest) and a sub-root carry is still assembled from the sub-root when the root omits it... "
proj=$(make_project "sync-subroot-overlap")
fake_standards "$proj"
mkdir -p "$proj/apps/web"
printf 'version: 1\nlanguages:\n  - python\nagents:\n  - codex\nrole: service\n' > "$proj/.standards.yml"
printf '[project]\nname = "root"\n' > "$proj/pyproject.toml"
printf '{"name":"root-tooling"}\n' > "$proj/package.json"          # root carries javascript but declares only python
printf '{"name":"web"}\n' > "$proj/apps/web/package.json"          # the sub-root carries javascript too
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
errs=""
[ -f "$proj/AGENTS.md" ]                                          || errs="$errs agents-missing"
grep -q 'eslint-config-prettier' "$proj/AGENTS.md" 2>/dev/null    || errs="$errs javascript-block-missing"
grep -qi 'ruff' "$proj/AGENTS.md" 2>/dev/null                     || errs="$errs python-block-missing"
grep -q '^  - javascript$' "$proj/.standards.yml"                 && errs="$errs javascript-forced-into-root-languages"
diff_rc=0
(cd "$proj" && bash "$REPO_ROOT/scripts/diff-standards.sh" --exit-code >/dev/null 2>&1) || diff_rc=$?
[ "$diff_rc" -eq 0 ]                                              || errs="$errs diff-reports-drift($diff_rc)"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$sync_out" | grep -i 'languages' | head -2)"; fi

# --- #183: curated agent configs ---------------------------------------------

TODO_OVERVIEW='<!-- TODO(standards): one-paragraph project overview goes here. Run /merge-standards to fill. -->'
TODO_COMMANDS='<!-- TODO(standards): list key build/test/run commands. Run /merge-standards to fill. -->'

echo -n "Test 57: project_overview/key_commands in .standards.yml are assembled into CLAUDE.md and survive the setup rewrite... "
proj=$(make_project "persisted-overview")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - claude-code\nrole: service\nproject_overview: |\n  Widget service that renders dashboards.\n\n  It talks to the billing API.\nkey_commands: |\n  make test    # unit tests\n  make lint\n' > "$proj/.standards.yml"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
errs=""
grep -q 'Widget service that renders dashboards.' "$proj/CLAUDE.md" 2>/dev/null || errs="$errs overview-missing"
grep -q 'It talks to the billing API.' "$proj/CLAUDE.md" 2>/dev/null         || errs="$errs overview-second-paragraph-missing"
grep -q '^make test    # unit tests$' "$proj/CLAUDE.md" 2>/dev/null         || errs="$errs commands-missing"
grep -q '^make lint$' "$proj/CLAUDE.md" 2>/dev/null                         || errs="$errs commands-second-line-missing"
grep -q 'TODO(standards)' "$proj/CLAUDE.md" 2>/dev/null                     && errs="$errs todo-marker-left"
grep -q '{{' "$proj/CLAUDE.md" 2>/dev/null                                  && errs="$errs placeholder-left"
grep -q '^project_overview: |$' "$proj/.standards.yml"                      || errs="$errs yml-overview-not-preserved"
grep -q '^  make lint$' "$proj/.standards.yml"                              || errs="$errs yml-commands-not-preserved"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 58: a config assembled from persisted text re-syncs with a matching checksum (no pending, doctor PASS)... "
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
doc_out=$(cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1) || true
errs=""
echo "$sync_out" | grep -q 'claude-code config synced'                       || errs="$errs not-synced"
[ -d "$proj/.standards-pending" ]                                           && errs="$errs pending-staged"
grep -q 'Widget service that renders dashboards.' "$proj/CLAUDE.md"         || errs="$errs overview-lost-on-sync"
echo "$doc_out" | grep 'Checksums' | grep -q 'PASS'                          || errs="$errs doctor-checksums-not-pass"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$doc_out" | grep 'Checksums')"; fi

echo -n "Test 59: sync prints the .standards.yml to add when a config has filled-in sections the yml lacks... "
proj=$(make_project "capture-hint")
fake_standards "$proj"
write_standards_yml "$proj" claude-code
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
# Fill the sections in by hand, as the merge skill used to instruct.
sed -e "s|$TODO_OVERVIEW|Hand-filled overview of the widget service.|" \
    -e "s|$TODO_COMMANDS|make widgets   # build the widgets|" \
    "$proj/CLAUDE.md" > "$proj/CLAUDE.md.tmp" && mv "$proj/CLAUDE.md.tmp" "$proj/CLAUDE.md"
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
errs=""
echo "$sync_out" | grep -q 'config customized'                                      || errs="$errs not-reported-customized"
echo "$sync_out" | grep -q '^   project_overview: |$'                               || errs="$errs overview-key-not-printed"
echo "$sync_out" | grep -q '^     Hand-filled overview of the widget service.$'     || errs="$errs overview-text-not-printed"
echo "$sync_out" | grep -q '^   key_commands: |$'                                   || errs="$errs commands-key-not-printed"
echo "$sync_out" | grep -q '^     make widgets   # build the widgets$'              || errs="$errs commands-text-not-printed"
echo "$sync_out" | grep -q 'TODO(standards)'                                        && errs="$errs todo-marker-captured"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$sync_out" | grep -A6 'does not persist' | tr '\n' '|')"; fi

echo -n "Test 60: pasting the printed yaml makes the next sync record the baseline instead of staging a pending copy... "
rm -rf "$proj/.standards-pending"
echo "$sync_out" | awk '/^   (project_overview|key_commands): \|$/ { p = 1 } p && /^$/ { p = 0 } p' | sed 's/^   //' >> "$proj/.standards.yml"
before=$(cat "$proj/CLAUDE.md")
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
after=$(cat "$proj/CLAUDE.md")
doc_out=$(cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1) || true
errs=""
grep -q '^project_overview: |$' "$proj/.standards.yml"                       || errs="$errs yaml-not-appended"
echo "$sync_out" | grep -q 'claude-code config synced'                       || errs="$errs not-synced"
[ -d "$proj/.standards-pending" ]                                           && errs="$errs pending-staged"
[ "$before" = "$after" ]                                                    || errs="$errs file-rewritten"
grep -q 'Hand-filled overview of the widget service.' "$proj/CLAUDE.md"     || errs="$errs overview-lost"
echo "$doc_out" | grep 'Checksums' | grep -q 'PASS'                          || errs="$errs doctor-checksums-not-pass"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$sync_out" | grep -i 'claude' | head -3 | tr '\n' '|')"; fi

echo -n "Test 61: managed: { CLAUDE.md: false } keeps a hand-edited config out of sync (no rewrite, no pending, reported curated)... "
proj=$(make_project "curated-sync")
fake_standards "$proj"
write_standards_yml "$proj" claude-code
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
{ head -1 "$proj/CLAUDE.md"; echo "# curated local rule"; tail -n +2 "$proj/CLAUDE.md"; } > "$proj/CLAUDE.md.tmp" \
    && mv "$proj/CLAUDE.md.tmp" "$proj/CLAUDE.md"
printf 'managed:\n  CLAUDE.md: false\n' >> "$proj/.standards.yml"
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
errs=""
grep -q '^# curated local rule$' "$proj/CLAUDE.md"                          || errs="$errs edit-lost"
[ -d "$proj/.standards-pending" ]                                           && errs="$errs pending-staged"
echo "$sync_out" | grep -q 'claude-code config is curated'                   || errs="$errs not-reported-curated"
echo "$sync_out" | grep -q 'config customized'                               && errs="$errs reported-customized"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$sync_out" | grep -i 'claude' | head -3 | tr '\n' '|')"; fi

echo -n "Test 62: setup.sh re-run keeps a curated file and carries managed:/hooks: into the regenerated .standards.yml... "
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
errs=""
grep -q '^# curated local rule$' "$proj/CLAUDE.md"                          || errs="$errs edit-lost-on-setup"
grep -q '^managed:$' "$proj/.standards.yml"                                 || errs="$errs managed-key-lost"
grep -q '^  CLAUDE.md: false$' "$proj/.standards.yml"                       || errs="$errs managed-entry-lost"
[ -d "$proj/.standards-pending" ]                                           && errs="$errs pending-staged"
if [ -z "$errs" ]; then pass; else fail "$errs: $(grep -c '' "$proj/.standards.yml") lines in yml"; fi

echo -n "Test 63: hooks: custom stops setup.sh from installing the native post-merge hook and is kept in .standards.yml... "
proj=$(make_project "hooks-custom")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\nhooks: custom\n' > "$proj/.standards.yml"
setup_out=$(cd "$proj" && "$SETUP" 2>&1) || true
errs=""
[ -f "$proj/.git/hooks/post-merge" ]                                        && errs="$errs native-hook-installed"
echo "$setup_out" | grep -q 'hooks: custom declared'                         || errs="$errs not-announced"
grep -q '^hooks: custom$' "$proj/.standards.yml"                            || errs="$errs hooks-key-lost"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$setup_out" | grep -i 'hook' | head -3 | tr '\n' '|')"; fi

echo -n "Test 64: without hooks: (or hooks: standards) setup.sh still installs the native post-merge hook... "
proj=$(make_project "hooks-default")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\nhooks: standards\n' > "$proj/.standards.yml"
(cd "$proj" && "$SETUP" >/dev/null 2>&1) || true
if [ -f "$proj/.git/hooks/post-merge" ] && grep -q 'standards' "$proj/.git/hooks/post-merge"; then pass; else fail "native post-merge hook not installed"; fi

echo -n "Test 65: an unrecognised hooks: value is reported and setup.sh still installs the native post-merge hook... "
proj=$(make_project "hooks-bogus")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\nhooks: lefthoook\n' > "$proj/.standards.yml"
setup_out=$(cd "$proj" && "$SETUP" 2>&1) || true
errs=""
[ -f "$proj/.git/hooks/post-merge" ]                                        || errs="$errs native-hook-missing"
echo "$setup_out" | grep -q "hooks: 'lefthoook' in .standards.yml is not recognised" || errs="$errs not-warned"
echo "$setup_out" | grep -q 'lefthoook declared in .standards.yml'           && errs="$errs treated-as-manager"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$setup_out" | grep -i 'hook' | head -3 | tr '\n' '|')"; fi

echo -n "Test 66: a hand-written config declared managed: false before the first setup gets a checksum baseline (doctor PASS, file untouched)... "
proj=$(make_project "curated-before-setup")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - claude-code\nrole: service\nmanaged:\n  CLAUDE.md: false\n' > "$proj/.standards.yml"
printf '# Hand-written CLAUDE.md\n\nEntirely project-owned.\n' > "$proj/CLAUDE.md"
setup_out=$(cd "$proj" && "$SETUP" --agents claude-code --languages typescript 2>&1) || true
doc_out=$(cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1) || true
errs=""
[ "$(cat "$proj/CLAUDE.md")" = "$(printf '# Hand-written CLAUDE.md\n\nEntirely project-owned.')" ] || errs="$errs file-changed"
echo "$setup_out" | grep -q 'claude-code config is curated'                  || errs="$errs not-reported-curated"
[ -f "$proj/.standards-checksums" ]                                         || errs="$errs checksums-missing"
grep -q '^CLAUDE.md ' "$proj/.standards-checksums" 2>/dev/null              || errs="$errs baseline-missing"
[ -d "$proj/.standards-pending" ]                                           && errs="$errs pending-staged"
echo "$doc_out" | grep 'Checksums' | grep -q 'PASS'                          || errs="$errs doctor-checksums-not-pass"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$doc_out" | grep 'Checksums')"; fi

echo -n "Test 67: setup/sync leave no *.pre-standards-setup copy of a config in the temp directory... "
proj=$(make_project "tmp-backup-leak")
fake_standards "$proj"
write_standards_yml "$proj" claude-code
leak_tmp="$TMPDIR_BASE/leak-tmp"; mkdir -p "$leak_tmp"
# A manual config with no header (assembly case 2) ...
printf '# Manual CLAUDE.md\n' > "$proj/CLAUDE.md"
(cd "$proj" && TMPDIR="$leak_tmp" "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
# ... then a tracked config replaced wholesale (assembly case 1).
rm -rf "$proj/.standards-pending" "$proj/CLAUDE.md"
(cd "$proj" && TMPDIR="$leak_tmp" "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
printf '# Replaced wholesale, no header or sentinel\n' > "$proj/CLAUDE.md"
sync_out=$(cd "$proj" && TMPDIR="$leak_tmp" "$SYNC" 2>&1) || true
errs=""
echo "$sync_out" | grep -q 'config customized'                               || errs="$errs case1-not-exercised"
leaked=$(find "$leak_tmp" -name '*.pre-standards-setup' | wc -l | tr -d ' ')
[ "$leaked" = "0" ]                                                         || errs="$errs leaked=$leaked"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 68: setup.sh adds the default worktree root to .gitignore once (second run does not duplicate it)... "
proj=$(make_project "wt-gitignore-default")
fake_standards "$proj"
printf 'node_modules/\n' > "$proj/.gitignore"
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
n=$(grep -cxF '.claude/worktrees/' "$proj/.gitignore" 2>/dev/null || true)
if [ "$n" = "1" ] && grep -qxF 'node_modules/' "$proj/.gitignore"; then pass; else fail "entries=$n: $(cat "$proj/.gitignore" | tr '\n' '|')"; fi

echo -n "Test 69: worktree_dir: in .standards.yml is gitignored under that name and preserved in the regenerated .standards.yml... "
proj=$(make_project "wt-gitignore-custom")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\nworktree_dir: tools/wt\n' > "$proj/.standards.yml"
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
errs=""
[ -f "$proj/.gitignore" ]                                   || errs="$errs gitignore-missing"
grep -qxF 'tools/wt/' "$proj/.gitignore" 2>/dev/null        || errs="$errs root-not-ignored"
grep -qxF '.claude/worktrees/' "$proj/.gitignore" 2>/dev/null && errs="$errs default-also-added"
grep -q '^worktree_dir: tools/wt' "$proj/.standards.yml"    || errs="$errs worktree_dir-not-preserved"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 70: an invalid worktree_dir: is reported and the default root is gitignored instead... "
proj=$(make_project "wt-invalid")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\nworktree_dir: ../outside\n' > "$proj/.standards.yml"
setup_out=$(cd "$proj" && "$SETUP" --agents codex --languages typescript 2>&1) || true
errs=""
echo "$setup_out" | grep -q "worktree_dir: '../outside'.*not a relative path" || errs="$errs not-warned"
grep -qxF '.claude/worktrees/' "$proj/.gitignore" 2>/dev/null                 || errs="$errs default-not-ignored"
grep -qF '../outside/' "$proj/.gitignore" 2>/dev/null                         && errs="$errs invalid-ignored"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 71: setup.sh installs the pre-commit worktree guard when no pre-commit hook exists, and the hook refuses a worktree path... "
proj=$(make_project "wt-guard-install")
fake_standards "$proj"
write_standards_yml "$proj" codex
setup_out=$(cd "$proj" && "$SETUP" 2>&1) || true
errs=""
[ -x "$proj/.git/hooks/pre-commit" ]                                          || errs="$errs hook-missing"
grep -q 'standards-worktree-guard' "$proj/.git/hooks/pre-commit" 2>/dev/null  || errs="$errs not-the-guard"
echo "$setup_out" | grep -q 'Pre-commit worktree guard installed'             || errs="$errs not-reported"
mkdir -p "$proj/.claude/worktrees/x" && echo x > "$proj/.claude/worktrees/x/f"
(cd "$proj" && git add -f .claude/worktrees/x/f && git -c user.email="t@t" -c user.name="T" commit -q -m "chore: oops" >/dev/null 2>&1) && errs="$errs commit-not-refused"
# A second run recognises its own hook.
setup_out=$(cd "$proj" && "$SETUP" 2>&1) || true
echo "$setup_out" | grep -q 'worktree guard already installed'                || errs="$errs rerun-not-recognised"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 72: an existing pre-commit hook is never replaced (hint printed), and --agents <list> skips the guard... "
proj=$(make_project "wt-guard-noclobber")
fake_standards "$proj"
write_standards_yml "$proj" codex
printf '#!/bin/sh\necho mine\n' > "$proj/.git/hooks/pre-commit"; chmod +x "$proj/.git/hooks/pre-commit"
setup_out=$(cd "$proj" && "$SETUP" 2>&1) || true
errs=""
grep -q 'echo mine' "$proj/.git/hooks/pre-commit"                              || errs="$errs clobbered"
echo "$setup_out" | grep -q 'pre-commit already exists'                         || errs="$errs no-hint"
echo "$setup_out" | grep -q 'pre-commit-worktree-guard.example'                 || errs="$errs hint-lacks-template"
proj2=$(make_project "wt-guard-explicit")
fake_standards "$proj2"
(cd "$proj2" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
[ -f "$proj2/.git/hooks/pre-commit" ]                                          && errs="$errs explicit-agents-installed-hook"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 73: with hooks: husky declared, setup.sh does not write a native pre-commit hook and prints the husky wiring... "
proj=$(make_project "wt-guard-husky")
fake_standards "$proj"
printf 'version: 1\nlanguages:\n  - typescript\nagents:\n  - codex\nrole: service\nhooks: husky\n' > "$proj/.standards.yml"
setup_out=$(cd "$proj" && "$SETUP" 2>&1) || true
errs=""
[ -f "$proj/.git/hooks/pre-commit" ]                                           && errs="$errs native-hook-written"
echo "$setup_out" | grep -q "pre-commit-worktree-guard.example' >> .husky/pre-commit" || errs="$errs no-husky-hint"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$setup_out" | grep -i 'guard' | head -3 | tr '\n' '|')"; fi

echo -n "Test 74: --dry-run announces the gitignore entry and the guard without writing either... "
proj=$(make_project "wt-dry-run")
fake_standards "$proj"
write_standards_yml "$proj" codex
printf 'node_modules/\n' > "$proj/.gitignore"
setup_out=$(cd "$proj" && "$SETUP" --dry-run 2>&1) || true
errs=""
echo "$setup_out" | grep -q 'Would write: .*pre-commit (worktree guard)'       || errs="$errs guard-not-announced"
echo "$setup_out" | grep -q 'Would append to: .*\.gitignore'                   || errs="$errs gitignore-not-announced"
[ -f "$proj/.git/hooks/pre-commit" ]                                           && errs="$errs guard-written"
grep -q 'worktrees' "$proj/.gitignore"                                         && errs="$errs gitignore-written"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

# --- #184: setup.sh --migrate for pre-1.2 consumers ---------------------------
#
# Fixture: a consumer installed before the 1.2 safe-setup, with v1.0-era agent
# configs copied from the old hand-rolled templates. They cite standards paths
# no release has carried since the #21 renumbering (00_/03_/12_…), the
# .cursorrules cites arch-03 (deleted in #40), Codex still has a .codexrc, the
# .aiderrc carries the 100/90/80 coverage tiers and a pinned model, and there
# is no .standards.yml, no .standards-checksums and no .standards-pending/.
DOCTOR="$REPO_ROOT/scripts/doctor.sh"
RENAME_MAP="$REPO_ROOT/docs/reference/renamed-files.md"

make_pre12_project() {
    local name="$1"
    local proj
    proj=$(make_project "$name")
    fake_standards "$proj"
    mkdir -p "$proj/.github"
    printf '[project]\nname = "fixture"\n' > "$proj/pyproject.toml"
    cat > "$proj/.aiderrc" <<'EOF'
# Aider (Claude Code) Configuration
# This file configures Aider to follow project standards

# Model configuration
model = claude-3-5-sonnet-20241022

# Architecture rules
architecture_rules = """
Follow Clean Architecture principles.

Reference: standards/architecture/00_project_standards_and_architecture.md
"""

# Language-specific standards
language_standards = """
Apply language-specific standards from:
- Python: standards/languages/03_python_standards.md
- TypeScript: standards/languages/08_typescript_standards.md
"""

# Testing requirements
testing_standards = """
- Domain: 100% test coverage
- Application: 90%+ test coverage
- Infrastructure: 80%+ test coverage
"""

# Documentation requirements
documentation_standards = """
Reference: standards/process/12_documentation_standards.md
"""
EOF
    cat > "$proj/.codexrc" <<'EOF'
# OpenAI Codex Configuration
# This file configures Codex to follow project standards

## Architecture Standards
# Reference: standards/architecture/00_project_standards_and_architecture.md
# - Follow Clean Architecture (Domain → Application → Infrastructure → Apps)

## Language Standards
# Apply language-specific standards from standards/languages/:
# - Python: 03_python_standards.md
# - TypeScript: 08_typescript_standards.md

## Testing Standards
# - Domain: 100% coverage
# - Application: 90%+ coverage
# - Infrastructure: 80%+ coverage

## Process Standards
# - Documentation: standards/process/12_documentation_standards.md
# - Git workflow: standards/process/13_git_version_control_standards.md

## Project Notes
# - Deploy with `make release` only from the main branch.
EOF
    cat > "$proj/.github/copilot-instructions.md" <<'EOF'
# GitHub Copilot Instructions

## Core Standards

### Architecture & Standards
- `standards/architecture/00_project_standards_and_architecture.md` - Core architecture, SOLID principles, naming conventions
- `standards/architecture/01_automation_standards.md` - Makefile targets and automation requirements

### Language-Specific Standards
- `standards/languages/03_python_standards.md` - Python (uv, ruff, mypy, pytest)
- `standards/languages/08_typescript_standards.md` - TypeScript (pnpm, prettier, eslint, vitest, strict mode)

### Process Standards
- `standards/process/12_documentation_standards.md` - ADR, code docs, changelog, user docs
- `standards/process/14_code_review_expectations.md` - Code review process and expectations
EOF
    cat > "$proj/.cursorrules" <<'EOF'
# Cursor Rules

1. **Always check relevant standards** before making changes:
   - `standards/architecture/arch-01_project_standards_and_architecture.md` - Core architecture, SOLID principles, naming conventions
   - `standards/architecture/arch-02_automation_standards.md` - Makefile targets and automation requirements
   - `standards/architecture/arch-03_cursor_automation_standards.md` - Cursor-specific interaction modes (@new-feature, @refactor, @debug, @review)
   - `standards/architecture/arch-03_cursor_automation_standards.md` — continue requiring @review before release
   - `standards/languages/lang-01_python_standards.md` - Python (uv, ruff, mypy, pytest)

2. **Follow interaction modes** from `standards/architecture/arch-03_cursor_automation_standards.md`:
   - `@new-feature` - scaffold a feature
   - `@refactor` - restructure without behaviour change
EOF
    echo "$proj"
}

echo -n "Test 75: docs/reference/renamed-files.md maps every #21 rename and the #40 deletion... "
errs=""
[ -f "$RENAME_MAP" ] || errs="$errs map-missing"
for pair in \
    "00_project_standards_and_architecture.md:arch-01_project_standards_and_architecture.md" \
    "01_automation_standards.md:arch-02_automation_standards.md" \
    "16_data_versioning_and_migration_standards.md:arch-04_data_versioning_and_migration_standards.md" \
    "17_resilient_architecture_patterns.md:arch-05_resilient_architecture_patterns.md" \
    "03_python_standards.md:lang-01_python_standards.md" \
    "04_java_standards.md:lang-02_java_standards.md" \
    "05_kotlin_standards.md:lang-03_kotlin_standards.md" \
    "06_swift_standards.md:lang-04_swift_standards.md" \
    "07_dart_standards.md:lang-05_dart_standards.md" \
    "08_typescript_standards.md:lang-06_typescript_standards.md" \
    "09_javascript_standards.md:lang-07_javascript_standards.md" \
    "10_rust_standards.md:lang-08_rust_standards.md" \
    "11_zig_standards.md:lang-09_zig_standards.md" \
    "12_documentation_standards.md:proc-01_documentation_standards.md" \
    "13_git_version_control_standards.md:proc-02_git_version_control_standards.md" \
    "14_code_review_expectations.md:proc-03_code_review_expectations.md" \
    "15_agent_workflow_standards.md:proc-04_agent_workflow_standards.md"; do
    old="${pair%%:*}"; new="${pair#*:}"
    grep -q "^| \`standards/[a-z]*/$old\` | \`standards/[a-z]*/$new\`" "$RENAME_MAP" 2>/dev/null || errs="$errs $old"
done
grep -q "^| \`standards/architecture/arch-03_cursor_automation_standards.md\` | (removed)" "$RENAME_MAP" 2>/dev/null || errs="$errs arch-03-not-removed"
grep -q "^| \`standards/architecture/02_cursor_automation_standards.md\` | (removed)" "$RENAME_MAP" 2>/dev/null || errs="$errs 02_cursor-not-removed"
# Every new path in the map must exist in this repo (a map entry to a missing file would rewrite one dead reference into another).
map_out=$(bash -c "source '$REPO_ROOT/scripts/lib/migrate.sh' && load_rename_map '$RENAME_MAP'" 2>/dev/null) || errs="$errs loader-failed"
while IFS="$(printf '\t')" read -r _old _new; do
    [ -n "$_new" ] || continue
    [ "$_new" = "-" ] && continue
    [ -f "$REPO_ROOT/$_new" ] || errs="$errs target-missing:$_new"
done <<EOF
$map_out
EOF
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 76: setup.sh --migrate rewrites dead standards references in place (.aiderrc, copilot-instructions.md, .cursorrules)... "
proj=$(make_pre12_project "migrate-rewrite")
mig_out=$(cd "$proj" && "$SETUP" --migrate 2>&1) || true
errs=""
for f in .aiderrc .github/copilot-instructions.md; do
    grep -qE '(^|[^A-Za-z0-9_-])(00_project_standards_and_architecture|03_python_standards|08_typescript_standards|12_documentation_standards)\.md' "$proj/$f" && errs="$errs $f-still-dead"
done
grep -q 'standards/architecture/arch-01_project_standards_and_architecture.md' "$proj/.aiderrc"        || errs="$errs aiderrc-arch01"
grep -q 'standards/languages/lang-01_python_standards.md' "$proj/.aiderrc"                              || errs="$errs aiderrc-lang01"
grep -q 'standards/process/proc-01_documentation_standards.md' "$proj/.aiderrc"                         || errs="$errs aiderrc-proc01"
grep -q '`standards/architecture/arch-02_automation_standards.md`' "$proj/.github/copilot-instructions.md" || errs="$errs copilot-arch02"
grep -q '`standards/process/proc-03_code_review_expectations.md`' "$proj/.github/copilot-instructions.md"  || errs="$errs copilot-proc03"
# Unchanged text survives the rewrite.
grep -q 'Core architecture, SOLID principles, naming conventions' "$proj/.github/copilot-instructions.md" || errs="$errs copilot-text-lost"
echo "$mig_out" | grep -q 'arch-01_project_standards_and_architecture.md'                               || errs="$errs not-reported"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$mig_out" | grep -i 'migrat\|rewr' | head -4 | tr '\n' '|')"; fi

echo -n "Test 77: --migrate drops a bullet that only cites a removed standard; a bullet with project text after the citation and a prose reference are kept and reported as unresolved (.cursorrules arch-03)... "
errs=""
# The template bullet about arch-03 is gone; the project's own bullet, the surrounding bullets and the prose line stay.
grep -q 'arch-03_cursor_automation_standards.md` - Cursor-specific interaction modes' "$proj/.cursorrules" && errs="$errs bullet-kept"
grep -q 'arch-03_cursor_automation_standards.md` — continue requiring @review before release' "$proj/.cursorrules" || errs="$errs project-bullet-dropped"
[ "$(grep -c '^  - `.cursorrules:[0-9]*: arch-03_cursor_automation_standards.md`' "$proj/.standards-pending/MERGE_PLAN.md" 2>/dev/null)" -ge 2 ] || errs="$errs plan-lacks-both-unresolved"
grep -q 'arch-02_automation_standards.md` - Makefile targets' "$proj/.cursorrules"                          || errs="$errs neighbour-lost"
grep -q 'Follow interaction modes\*\* from `standards/architecture/arch-03_cursor_automation_standards.md`' "$proj/.cursorrules" || errs="$errs prose-changed"
[ -f "$proj/.standards-pending/MERGE_PLAN.md" ]                                                           || errs="$errs no-merge-plan"
grep -q 'arch-03_cursor_automation_standards.md' "$proj/.standards-pending/MERGE_PLAN.md" 2>/dev/null     || errs="$errs plan-lacks-unresolved"
grep -qi 'migrat' "$proj/.standards-pending/MERGE_PLAN.md" 2>/dev/null                                    || errs="$errs plan-lacks-migration-section"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 78: --migrate converts .codexrc to AGENTS.md (Markdown, dead refs rewritten, project notes kept, original backed up)... "
errs=""
[ -f "$proj/AGENTS.md" ]                                                        || errs="$errs agents-missing"
[ -f "$proj/.codexrc" ]                                                         && errs="$errs codexrc-still-present"
[ -f "$proj/.codexrc.pre-standards-setup" ]                                     || errs="$errs no-backup"
grep -q '^## Architecture Standards' "$proj/AGENTS.md" 2>/dev/null              || errs="$errs heading-lost"
grep -q '^- Deploy with `make release` only from the main branch.' "$proj/AGENTS.md" 2>/dev/null || errs="$errs notes-lost-or-still-commented"
grep -q 'lang-01_python_standards.md' "$proj/AGENTS.md" 2>/dev/null             || errs="$errs refs-not-rewritten"
grep -q '03_python_standards.md' "$proj/AGENTS.md" 2>/dev/null                  && errs="$errs dead-ref-kept"
grep -q 'Application: 95%+ coverage' "$proj/AGENTS.md" 2>/dev/null              || errs="$errs tiers-not-raised"
grep -q 'Converted from .codexrc' "$proj/AGENTS.md" 2>/dev/null                 || errs="$errs provenance-missing"
[ -f "$proj/.standards-pending/AGENTS.md" ]                                     || errs="$errs assembled-not-staged"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 79: --migrate raises .aiderrc coverage tiers to the 95% floor and drops the pinned model; aiderrc.template has no model line... "
errs=""
grep -q 'Application: 95%+ test coverage' "$proj/.aiderrc"     || errs="$errs application-tier"
grep -q 'Infrastructure: 95%+ test coverage' "$proj/.aiderrc"  || errs="$errs infrastructure-tier"
grep -q 'Domain: 100% test coverage' "$proj/.aiderrc"          || errs="$errs domain-tier-changed"
grep -q '^model = ' "$proj/.aiderrc"                           && errs="$errs model-kept"
grep -q '^model' "$REPO_ROOT/standards/agents/aider/aiderrc.template" && errs="$errs template-has-model"
[ -f "$proj/.standards-pending/.aiderrc" ]                     || errs="$errs template-not-staged"
# Two passes rewrote .aiderrc (references, then tiers/model); the backup is the file before the first one.
grep -q '03_python_standards.md' "$proj/.aiderrc.pre-standards-setup" 2>/dev/null                  || errs="$errs backup-is-intermediate"
grep -q '^model = claude-3-5-sonnet-20241022' "$proj/.aiderrc.pre-standards-setup" 2>/dev/null     || errs="$errs backup-lacks-model"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 80: --migrate bootstraps .standards.yml from detection plus existing configs and writes .standards-checksums... "
errs=""
[ -f "$proj/.standards.yml" ]                                     || errs="$errs yml-missing"
for a in cursor copilot codex aider; do
    grep -q "^  - $a\$" "$proj/.standards.yml" 2>/dev/null        || errs="$errs agent-$a"
done
grep -q '^  - python$' "$proj/.standards.yml" 2>/dev/null         || errs="$errs lang-python"
[ -f "$proj/.standards-checksums" ]                                || errs="$errs checksums-missing"
for k in .cursorrules copilot-instructions.md AGENTS.md .aiderrc; do
    grep -q "^$k " "$proj/.standards-checksums" 2>/dev/null        || errs="$errs checksum-$k"
done
[ -f "$proj/.standards-pending/.cursorrules" ]                     || errs="$errs cursorrules-not-staged"
if [ -z "$errs" ]; then pass; else fail "$errs: $(cat "$proj/.standards-checksums" 2>/dev/null | tr '\n' '|')"; fi

echo -n "Test 81: after --migrate, sync-standards stages the configs as customized (no 'manually created' skip, no clobber) and doctor no longer asks to migrate... "
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
doc_out=$(cd "$proj" && bash "$DOCTOR" 2>&1) || true
errs=""
echo "$sync_out" | grep -q 'manually created'                                   && errs="$errs manually-created"
echo "$sync_out" | grep -q 'config customized'                                  || errs="$errs not-staged-as-customized"
grep -q 'Follow interaction modes' "$proj/.cursorrules"                         || errs="$errs cursorrules-clobbered"
echo "$doc_out" | grep -q -- '--migrate'                                        && errs="$errs doctor-still-asks-migrate"
echo "$doc_out" | grep 'Configuration' | grep -q 'PASS'                         || errs="$errs doctor-config-not-pass"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$sync_out" | grep -i 'config' | head -4 | tr '\n' '|')"; fi

echo -n "Test 82: doctor recognises the pre-1.2 shape and prints the single migration command instead of the per-check warnings (exit 1)... "
proj=$(make_pre12_project "migrate-doctor")
doc_rc=0
doc_out=$(cd "$proj" && bash "$DOCTOR" 2>&1) || doc_rc=$?
errs=""
[ "$doc_rc" -eq 1 ]                                                        || errs="$errs rc=$doc_rc"
[ "$(echo "$doc_out" | grep -c -- 'setup.sh --migrate')" -ge 1 ]            || errs="$errs no-migrate-command"
echo "$doc_out" | grep -q 'make setup-agents'                               && errs="$errs per-agent-warnings"
echo "$doc_out" | grep -q 'Checksums'                                       && errs="$errs checksums-check-ran"
echo "$doc_out" | grep -q 'Git Hooks'                                       && errs="$errs hooks-check-ran"
echo "$doc_out" | grep -q '\.codexrc'                                       || errs="$errs codexrc-not-named"
echo "$doc_out" | grep -q '\.aiderrc'                                       || errs="$errs dead-ref-files-not-named"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$doc_out" | grep -i 'migrat' | head -3 | tr '\n' '|')"; fi

echo -n "Test 83: setup.sh without --migrate on a pre-1.2 project points at --migrate and leaves the dead references alone... "
set_out=$(cd "$proj" && "$SETUP" --agents aider 2>&1) || true
errs=""
echo "$set_out" | grep -q -- 'setup.sh --migrate'                          || errs="$errs no-hint"
grep -q '03_python_standards.md' "$proj/.aiderrc"                          || errs="$errs rewrote-without-migrate"
[ -f "$proj/.codexrc" ]                                                    || errs="$errs converted-without-migrate"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 84: --migrate --dry-run reports every rewrite and conversion but modifies nothing... "
proj=$(make_pre12_project "migrate-dry")
before=$(cd "$proj" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum -a 256 | shasum -a 256)
dry_out=$(cd "$proj" && "$SETUP" --migrate --dry-run 2>&1) || true
after=$(cd "$proj" && find . -path ./.git -prune -o -type f -print | sort | xargs shasum -a 256 | shasum -a 256)
errs=""
[ "$before" = "$after" ]                                                   || errs="$errs files-changed"
[ -f "$proj/.standards.yml" ]                                              && errs="$errs yml-written"
[ -d "$proj/.standards-pending" ]                                          && errs="$errs pending-written"
echo "$dry_out" | grep -q 'Would rewrite'                                  || errs="$errs no-rewrite-report"
echo "$dry_out" | grep -q 'Would convert .codexrc'                         || errs="$errs no-convert-report"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$dry_out" | grep -i 'would' | head -4 | tr '\n' '|')"; fi

echo -n "Test 85: --migrate with an existing AGENTS.md leaves it alone and stages the converted .codexrc beside the merge plan... "
proj=$(make_pre12_project "migrate-agents-exists")
printf '# AGENTS.md\n\nHand-written Codex instructions that must survive.\n' > "$proj/AGENTS.md"
mig_out=$(cd "$proj" && "$SETUP" --migrate 2>&1) || true
errs=""
grep -q 'must survive' "$proj/AGENTS.md"                                   || errs="$errs agents-changed"
[ -f "$proj/.codexrc" ]                                                    || errs="$errs codexrc-removed"
[ -f "$proj/.standards-pending/AGENTS.md.from-codexrc" ]                   || errs="$errs converted-not-staged"
grep -q 'lang-01_python_standards.md' "$proj/.standards-pending/AGENTS.md.from-codexrc" 2>/dev/null || errs="$errs converted-not-rewritten"
grep -q 'AGENTS.md.from-codexrc' "$proj/.standards-pending/MERGE_PLAN.md" 2>/dev/null                || errs="$errs plan-lacks-entry"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$mig_out" | grep -i 'codexrc' | head -3 | tr '\n' '|')"; fi

echo -n "Test 86: --migrate reads a legacy .standards-config for role and languages and retires it... "
proj=$(make_pre12_project "migrate-legacy-config")
printf 'STANDARDS_ROLE=library\nSTANDARDS_LANGUAGES=python,typescript\nSTANDARDS_AGENTS=aider\n' > "$proj/.standards-config"
(cd "$proj" && "$SETUP" --migrate >/dev/null 2>&1) || true
errs=""
grep -q '^role: library$' "$proj/.standards.yml" 2>/dev/null               || errs="$errs role"
grep -q '^  - typescript$' "$proj/.standards.yml" 2>/dev/null              || errs="$errs lang-typescript"
grep -q '^  - python$' "$proj/.standards.yml" 2>/dev/null                  || errs="$errs lang-python"
[ -f "$proj/.standards-config" ]                                           && errs="$errs legacy-kept"
[ -f "$proj/.standards-config.pre-standards-setup" ]                       || errs="$errs legacy-backup-missing"
if [ -z "$errs" ]; then pass; else fail "$errs: $(grep -E '^(role|  - )' "$proj/.standards.yml" 2>/dev/null | tr '\n' '|')"; fi

echo -n "Test 87: --migrate on an already-migrated project is a no-op for migration and runs a normal setup... "
proj=$(make_pre12_project "migrate-twice")
(cd "$proj" && "$SETUP" --migrate >/dev/null 2>&1) || true
snap=$(cat "$proj/.aiderrc" "$proj/AGENTS.md" "$proj/.cursorrules" | shasum -a 256)
second=$(cd "$proj" && "$SETUP" --migrate 2>&1) || true
errs=""
[ "$snap" = "$(cat "$proj/.aiderrc" "$proj/AGENTS.md" "$proj/.cursorrules" | shasum -a 256)" ] || errs="$errs files-changed"
echo "$second" | grep -qi 'nothing to migrate\|no pre-1.2'                 || errs="$errs not-reported-noop"
echo "$second" | grep -q 'Setup complete'                                  || errs="$errs setup-not-run"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$second" | grep -i 'migrat' | head -3 | tr '\n' '|')"; fi

echo -n "Test 88: a plain setup.sh first (checksums written, artefacts untouched) does not hide the pre-1.2 shape: doctor still asks to migrate and --migrate still rewrites and converts... "
proj=$(make_pre12_project "migrate-after-plain-setup")
(cd "$proj" && "$SETUP" --agents claude-code --languages python >/dev/null 2>&1) || true
errs=""
[ -f "$proj/.standards-checksums" ]                                        || errs="$errs plain-setup-wrote-no-checksums"
doc_out=$(cd "$proj" && bash "$DOCTOR" 2>&1) || true
echo "$doc_out" | grep -q -- 'setup.sh --migrate'                          || errs="$errs doctor-silent"
echo "$doc_out" | grep -q 'left by a plain setup'                          || errs="$errs doctor-wrong-prefix"
mig_out=$(cd "$proj" && "$SETUP" --migrate 2>&1) || true
echo "$mig_out" | grep -qi 'nothing to migrate'                            && errs="$errs nothing-to-migrate"
grep -q '03_python_standards.md' "$proj/.aiderrc"                          && errs="$errs aiderrc-still-dead"
[ -f "$proj/.codexrc" ]                                                    && errs="$errs codexrc-kept"
[ -f "$proj/AGENTS.md" ]                                                   || errs="$errs agents-missing"
doc_out=$(cd "$proj" && bash "$DOCTOR" 2>&1) || true
echo "$doc_out" | grep -q -- '--migrate'                                   && errs="$errs doctor-still-asks-after-migrate"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$mig_out" | grep -i 'migrat' | head -3 | tr '\n' '|')"; fi

echo -n "Test 89: sync-standards refreshing a managed .aiderrc (checksum matches) carries the project's model = line into the new template copy... "
proj=$(make_project "aiderrc-model-kept")
fake_standards "$proj"
write_standards_yml "$proj" aider
(cd "$proj" && "$SETUP" >/dev/null 2>&1) || true
# A consumer on the previous template: same settings, a pinned model, and a checksum that matches.
tmpl="$REPO_ROOT/standards/agents/aider/aiderrc.template"
{ sed -n '1,3p' "$tmpl"; echo; echo "model = claude-sonnet-4-6"; sed -n '/^read = /,$p' "$tmpl"; } > "$proj/.aiderrc"
h=$(shasum -a 256 "$proj/.aiderrc" | awk '{print $1}')
{ grep -v '^\.aiderrc ' "$proj/.standards-checksums" 2>/dev/null; echo ".aiderrc $h"; } > "$proj/.standards-checksums.new" && mv "$proj/.standards-checksums.new" "$proj/.standards-checksums"
sync_out=$(cd "$proj" && "$SYNC" 2>&1) || true
errs=""
echo "$sync_out" | grep -q 'Aider .aiderrc synced'                         || errs="$errs not-synced"
echo "$sync_out" | grep -q '.aiderrc customized'                           && errs="$errs treated-as-customized"
grep -q 'The template pins no model' "$proj/.aiderrc"                      || errs="$errs template-not-refreshed"
grep -q '^model = claude-sonnet-4-6$' "$proj/.aiderrc"                     || errs="$errs model-lost"
[ "$(grep -c '^model' "$proj/.aiderrc")" = "1" ]                           || errs="$errs model-duplicated"
h2=$(shasum -a 256 "$proj/.aiderrc" | awk '{print $1}')
grep -q "^\.aiderrc $h2\$" "$proj/.standards-checksums"                    || errs="$errs checksum-stale"
(cd "$proj" && "$SYNC" >/dev/null 2>&1) || true
[ "$h2" = "$(shasum -a 256 "$proj/.aiderrc" | awk '{print $1}')" ]         || errs="$errs not-idempotent"
if [ -z "$errs" ]; then pass; else fail "$errs: $(echo "$sync_out" | grep -i 'aider' | head -3 | tr '\n' '|')"; fi

echo -n "Test 90: --migrate rewrites a symlinked config through the link (link and mode kept, no temp file left) and backs up the original once... "
proj=$(make_pre12_project "migrate-symlink")
mkdir -p "$proj/config" && mv "$proj/.aiderrc" "$proj/config/aiderrc" && chmod 640 "$proj/config/aiderrc" && ln -s config/aiderrc "$proj/.aiderrc"
(cd "$proj" && "$SETUP" --migrate >/dev/null 2>&1) || true
errs=""
[ -L "$proj/.aiderrc" ]                                                    || errs="$errs link-replaced"
grep -q 'lang-01_python_standards.md' "$proj/config/aiderrc"               || errs="$errs target-not-rewritten"
grep -q '^model = ' "$proj/config/aiderrc"                                 && errs="$errs model-kept"
if stat -c %a / >/dev/null 2>&1; then mode=$(stat -c %a "$proj/config/aiderrc"); else mode=$(stat -f %Lp "$proj/config/aiderrc"); fi   # GNU, then BSD
[ "$mode" = "640" ]                                                        || errs="$errs mode=$mode"
[ "$(find "$proj/config" -mindepth 1 ! -name aiderrc | wc -l | tr -d ' ')" = "0" ] || errs="$errs temp-left:$(find "$proj/config" -mindepth 1 ! -name aiderrc -exec basename {} \; | tr '\n' ',')"
grep -q '03_python_standards.md' "$proj/.aiderrc.pre-standards-setup" 2>/dev/null || errs="$errs backup-not-original"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

# --- #194: agent-neutral workflow text and per-agent skills -------------------

ALL_AGENTS="claude-code cursor copilot gemini codex aider"
SKILL_NAMES=$(for f in "$REPO_ROOT"/standards/skills/*.md; do basename "$f" .md; done | tr '\n' ' ')

# assemble_for <proj> <agent> <out> — assemble one agent config into <out>.
assemble_for() {
    bash "$REPO_ROOT/scripts/assemble-config.sh" --project-root "$1" "$2" \
        "$REPO_ROOT/standards/shared/blocks" \
        "$REPO_ROOT/standards/agents/$2/base-$2.md" \
        "$3" lang-typescript.md role-service.md >/dev/null 2>&1 || true
}

echo -n "Test 91: {{WORKTREE_DIR}} resolves from worktree_dir: in every agent's assembly, and defaults to .claude/worktrees... "
proj=$(make_project "wt-var")
printf 'version: 1\nlanguages:\n  - typescript\nagents: []\nrole: service\nworktree_dir: tools/wt\n' > "$proj/.standards.yml"
errs=""
for a in $ALL_AGENTS; do
    out="$proj/out-$a.md"
    assemble_for "$proj" "$a" "$out"
    [ -f "$out" ]                             || { errs="$errs $a:not-written"; continue; }
    grep -q '{{WORKTREE_DIR}}' "$out"         && errs="$errs $a:literal-var"
    grep -q 'tools/wt' "$out"                 || errs="$errs $a:worktree_dir-not-applied"
    grep -q '\.claude/worktrees' "$out"       && errs="$errs $a:default-leaked"
done
proj2=$(make_project "wt-var-default")
assemble_for "$proj2" "codex" "$proj2/AGENTS.md"
grep -q '\.claude/worktrees' "$proj2/AGENTS.md" || errs="$errs default-missing"
grep -q '{{WORKTREE_DIR}}' "$proj2/AGENTS.md"   && errs="$errs default:literal-var"
[ -n "$SKILL_NAMES" ]                           || errs="$errs no-skills-dir"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 92: assemble-skills.sh claude-code writes every standards/skills/*.md to .claude/skills/<name>/SKILL.md with its frontmatter intact... "
proj=$(make_project "skills-claude")
rc=0; out=$(bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" claude-code 2>&1) || rc=$?
errs=""
[ "$rc" -eq 0 ] || errs="$errs rc=$rc"
for n in $SKILL_NAMES; do
    f="$proj/.claude/skills/$n/SKILL.md"
    [ -f "$f" ]                               || { errs="$errs $n:missing"; continue; }
    head -1 "$f" | grep -q '^---$'            || errs="$errs $n:no-frontmatter"
    grep -q "^name: $n$" "$f"                 || errs="$errs $n:no-name"
    grep -q '^description: ' "$f"             || errs="$errs $n:no-description"
done
echo "$out" | grep -q 'claude-code' || errs="$errs not-reported"
if [ -z "$errs" ]; then pass; else fail "$errs; output: $out"; fi

echo -n "Test 93: assemble-skills.sh cursor writes .cursor/commands/<name>.md with a description frontmatter and no name: key... "
proj=$(make_project "skills-cursor")
bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" cursor >/dev/null 2>&1 || true
errs=""
for n in $SKILL_NAMES; do
    f="$proj/.cursor/commands/$n.md"
    [ -f "$f" ]                               || { errs="$errs $n:missing"; continue; }
    head -1 "$f" | grep -q '^---$'            || errs="$errs $n:no-frontmatter"
    grep -q '^description: ' "$f"             || errs="$errs $n:no-description"
    grep -q '^name: ' "$f"                    && errs="$errs $n:name-key-kept"
done
[ -e "$proj/.claude" ] && errs="$errs claude-dir-written"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 94: assemble-skills.sh copilot writes .github/prompts/<name>.prompt.md with a description frontmatter... "
proj=$(make_project "skills-copilot")
bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" copilot >/dev/null 2>&1 || true
errs=""
for n in $SKILL_NAMES; do
    f="$proj/.github/prompts/$n.prompt.md"
    [ -f "$f" ]                               || { errs="$errs $n:missing"; continue; }
    head -1 "$f" | grep -q '^---$'            || errs="$errs $n:no-frontmatter"
    grep -q '^description: ' "$f"             || errs="$errs $n:no-description"
    grep -q "^# " "$f"                        || errs="$errs $n:no-body"
done
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 95: codex, gemini and aider assemblies carry a '## Skills' index naming every skill; claude-code, cursor and copilot do not... "
proj=$(make_project "skills-index")
errs=""
for a in codex gemini aider; do
    out="$proj/out-$a.md"
    assemble_for "$proj" "$a" "$out"
    grep -q '^## Skills$' "$out" || { errs="$errs $a:no-section"; continue; }
    for n in $SKILL_NAMES; do
        grep -q "^### $n$" "$out" || errs="$errs $a:$n-missing"
    done
    grep -q 'standards/skills/merge-standards.md' "$out" || errs="$errs $a:no-runbook-path"
    # the index must come before the project-specific section
    idx=$(grep -n '^## Skills$' "$out" | cut -d: -f1); sen=$(grep -n 'BEGIN PROJECT-SPECIFIC' "$out" | cut -d: -f1)
    [ "$idx" -lt "$sen" ] || errs="$errs $a:after-sentinel"
done
for a in claude-code cursor copilot; do
    out="$proj/out-$a.md"
    assemble_for "$proj" "$a" "$out"
    grep -q '^## Skills$' "$out" && errs="$errs $a:unexpected-section"
done
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 96: setup.sh --agents copilot installs the prompt files only; --agents codex installs no skill files at all... "
proj=$(make_project "setup-skills-copilot")
fake_standards "$proj"
(cd "$proj" && "$SETUP" --agents copilot --languages typescript >/dev/null 2>&1) || true
errs=""
[ -f "$proj/.github/prompts/merge-standards.prompt.md" ] || errs="$errs copilot:prompt-missing"
[ -e "$proj/.claude" ]                                   && errs="$errs copilot:.claude-written"
[ -e "$proj/.cursor" ]                                   && errs="$errs copilot:.cursor-written"
proj=$(make_project "setup-skills-codex")
fake_standards "$proj"
(cd "$proj" && "$SETUP" --agents codex --languages typescript >/dev/null 2>&1) || true
[ -e "$proj/.claude" ]                                   && errs="$errs codex:.claude-written"
[ -e "$proj/.github/prompts" ]                           && errs="$errs codex:prompts-written"
grep -q '^## Skills$' "$proj/AGENTS.md"                  || errs="$errs codex:no-index"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 97: sync-standards with agents: [claude-code, cursor, copilot] installs all three skill sets; --dry-run announces them without writing... "
proj=$(make_project "sync-skills")
fake_standards "$proj"
write_standards_yml "$proj" claude-code cursor copilot
dry=$(cd "$proj" && "$SYNC" --dry-run 2>&1) || true
errs=""
echo "$dry" | grep -q 'Would write: .*\.claude/skills/merge-standards/SKILL.md'            || errs="$errs dry:claude-not-announced"
echo "$dry" | grep -q 'Would write: .*\.github/prompts/merge-standards.prompt.md'    || errs="$errs dry:copilot-not-announced"
[ -e "$proj/.claude/skills" ]                                                        && errs="$errs dry:written"
out=$(cd "$proj" && "$SYNC" 2>&1) || true
[ -f "$proj/.claude/skills/security-gate/SKILL.md" ]            || errs="$errs claude-skill-missing"
[ -f "$proj/.cursor/commands/security-gate.md" ]          || errs="$errs cursor-command-missing"
[ -f "$proj/.cursor/commands/pr.md" ]                     || errs="$errs cursor-pr-command-missing"
[ -f "$proj/.github/prompts/security-gate.prompt.md" ]    || errs="$errs copilot-prompt-missing"
# a second sync is quiet about unchanged skills
out2=$(cd "$proj" && "$SYNC" 2>&1) || true
echo "$out2" | grep -q 'skills.*unchanged\|Skills up to date' || errs="$errs second-sync-not-quiet"
if [ -z "$errs" ]; then pass; else fail "$errs; output: $out"; fi

echo -n "Test 98: assemble-skills.sh rejects an unknown agent (exit 2) and --dry-run writes nothing... "
proj=$(make_project "skills-usage")
bad_rc=0; bad_out=$(bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" nope 2>&1) || bad_rc=$?
dry_rc=0; dry_out=$(bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" --dry-run claude-code cursor 2>&1) || dry_rc=$?
errs=""
[ "$bad_rc" -eq 2 ]                                   || errs="$errs bad-rc=$bad_rc"
echo "$bad_out" | grep -q 'Unknown agent'             || errs="$errs no-unknown-msg"
[ "$dry_rc" -eq 0 ]                                   || errs="$errs dry-rc=$dry_rc"
echo "$dry_out" | grep -q 'Would write: .*\.cursor/commands/merge-standards.md' || errs="$errs dry-not-announced"
if [ -e "$proj/.claude" ] || [ -e "$proj/.cursor" ]; then errs="$errs dry-wrote-files"; fi
if [ -z "$errs" ]; then pass; else fail "$errs; $bad_out $dry_out"; fi

echo -n "Test 99: assembled text calls make ci the project's full local gate that mirrors CI, and makes CHANGELOG.md conditional on release automation... "
proj=$(make_project "assembled-text")
assemble_for "$proj" "claude-code" "$proj/CLAUDE.md"
errs=""
grep -q "full local gate" "$proj/CLAUDE.md"                 || errs="$errs no-local-gate"
grep -qi "mirror CI" "$proj/CLAUDE.md"                      || errs="$errs no-mirror-ci"
grep -q "full pipeline must pass" "$proj/CLAUDE.md"         && errs="$errs old-pipeline-text"
grep -q "release automation" "$proj/CLAUDE.md"              || errs="$errs changelog-unconditional"
grep -q '^Maintain `CHANGELOG.md`' "$proj/CLAUDE.md"        && errs="$errs changelog-leads-unconditionally"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 100: assemble-skills.sh never replaces a skill file it did not install or that was edited since — it stages the new version to .standards-pending/<path> and records what it installs in .standards-checksums... "
proj=$(make_project "skills-guard")
mkdir -p "$proj/.claude/skills/security-gate"
printf -- '---\nname: security-gate\ndescription: mine\n---\n\nMy own security gate.\n' > "$proj/.claude/skills/security-gate/SKILL.md"
rc=0; out=$(bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" claude-code 2>&1) || rc=$?
errs=""
[ "$rc" -eq 0 ]                                                                    || errs="$errs rc=$rc"
grep -q 'My own security gate' "$proj/.claude/skills/security-gate/SKILL.md"       || errs="$errs foreign-replaced"
[ -f "$proj/.standards-pending/.claude/skills/security-gate/SKILL.md" ]            || errs="$errs foreign-not-staged"
echo "$out" | grep -q 'not installed by the standards'                             || errs="$errs foreign-not-reported"
echo "$out" | grep -q '1 staged'                                                   || errs="$errs summary-no-staged"
grep -q '^\.claude/skills/merge-standards/SKILL\.md ' "$proj/.standards-checksums" || errs="$errs checksum-not-recorded"
grep -q '^\.claude/skills/security-gate/SKILL\.md ' "$proj/.standards-checksums"   && errs="$errs foreign-checksum-recorded"
# an installed skill the user edits afterwards is kept on the next run
printf '\nLocal note.\n' >> "$proj/.claude/skills/merge-standards/SKILL.md"
out2=$(bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" claude-code 2>&1) || true
grep -q 'Local note' "$proj/.claude/skills/merge-standards/SKILL.md"              || errs="$errs customized-replaced"
[ -f "$proj/.standards-pending/.claude/skills/merge-standards/SKILL.md" ]         || errs="$errs customized-not-staged"
echo "$out2" | grep -q 'edited since'                                              || errs="$errs customized-not-reported"
# --dry-run announces the staging without writing anything
proj=$(make_project "skills-guard-dry")
mkdir -p "$proj/.cursor/commands"; echo "mine" > "$proj/.cursor/commands/security-gate.md"
dry=$(bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" --dry-run cursor 2>&1) || true
echo "$dry" | grep -q 'Would stage: .*\.standards-pending/\.cursor/commands/security-gate\.md' || errs="$errs dry:not-announced"
[ -e "$proj/.standards-pending" ]                                                  && errs="$errs dry:staged"
[ "$(cat "$proj/.cursor/commands/security-gate.md")" = "mine" ]                    || errs="$errs dry:replaced"
if [ -z "$errs" ]; then pass; else fail "$errs; output: $out $out2 $dry"; fi

echo -n "Test 101: skills are installed as written — no template variable is resolved, so the installed runbook equals the source the single-file agents read... "
proj=$(make_project "skills-literal")
printf 'version: 1\nlanguages: []\nagents: []\nrole: service\nworktree_dir: tools/wt\n' > "$proj/.standards.yml"
bash "$REPO_ROOT/scripts/assemble-skills.sh" --project-root "$proj" claude-code cursor >/dev/null 2>&1 || true
errs=""
cmp -s "$REPO_ROOT/standards/skills/merge-standards.md" "$proj/.claude/skills/merge-standards/SKILL.md" || errs="$errs claude-not-verbatim"
grep -q '{{PROJECT_OVERVIEW}}' "$proj/.claude/skills/merge-standards/SKILL.md"    || errs="$errs overview-placeholder-resolved"
grep -q '{{WORKTREE_DIR}}' "$proj/.cursor/commands/config-assembly.md"            || errs="$errs worktree-placeholder-resolved"
grep -q 'tools/wt' "$proj/.cursor/commands/config-assembly.md"                    && errs="$errs worktree_dir-substituted"
if [ -z "$errs" ]; then pass; else fail "$errs"; fi

echo -n "Test 102: a second setup.sh run still owns the skills it installed — an upstream skill change updates an unmodified file instead of staging it... "
proj=$(make_project "setup-skills-rerun")
mkdir -p "$proj/.standards/standards"
for d in "$REPO_ROOT"/standards/*; do
    case "$(basename "$d")" in
        skills) cp -R "$d" "$proj/.standards/standards/skills" ;;
        *)      ln -s "$d" "$proj/.standards/standards/" ;;
    esac
done
ln -s "$REPO_ROOT/scripts"   "$proj/.standards/scripts"
ln -s "$REPO_ROOT/templates" "$proj/.standards/templates"
ln -s "$REPO_ROOT/.cursor"   "$proj/.standards/.cursor"
ln -s "$REPO_ROOT/.gemini"   "$proj/.standards/.gemini"
(cd "$proj" && "$SETUP" --agents claude-code --languages typescript >/dev/null 2>&1) || true
errs=""
[ -f "$proj/.claude/skills/security-gate/SKILL.md" ]                               || errs="$errs skill-missing"
grep -q '^\.claude/skills/security-gate/SKILL\.md ' "$proj/.standards-checksums"   || errs="$errs checksum-missing"
printf '\nUpstream addition.\n' >> "$proj/.standards/standards/skills/security-gate.md"
out=$(cd "$proj" && "$SETUP" --agents claude-code --languages typescript 2>&1) || true
grep -q 'Upstream addition' "$proj/.claude/skills/security-gate/SKILL.md"          || errs="$errs upstream-not-applied"
[ -e "$proj/.standards-pending/.claude/skills" ]                                   && errs="$errs wrongly-staged"
grep -q '^\.claude/skills/security-gate/SKILL\.md ' "$proj/.standards-checksums"   || errs="$errs checksum-dropped"
# doctor hashes the skill entries the same way: no drift right after install
doc=$(cd "$proj" && bash "$REPO_ROOT/scripts/doctor.sh" 2>&1) || true
echo "$doc" | grep -q 'All config checksums match'                                 || errs="$errs doctor:drift-reported"
if [ -z "$errs" ]; then pass; else fail "$errs; output: $out; doctor: $(echo "$doc" | grep -i checksum)"; fi

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}$FAIL failures${NC}"
    exit 1
fi
echo -e "${GREEN}All $PASS tests passed!${NC}"
