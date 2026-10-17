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

echo ""
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}$FAIL failures${NC}"
    exit 1
fi
echo -e "${GREEN}All $PASS tests passed!${NC}"
