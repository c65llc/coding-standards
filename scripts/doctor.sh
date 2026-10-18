#!/bin/bash
# scripts/doctor.sh — Standards health check
#
# Audits the current project's standards setup and produces a scored health
# report. Works both in the standards repo itself (self-dogfooding) and in
# consumer projects that have the .standards/ submodule installed.
#
# Usage:
#   ./scripts/doctor.sh
#   make doctor

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Source helpers if available
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck source=scripts/lib/checksums.sh
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
fi
# Supported language keys (languages.sh) and monorepo members (members.sh).
if [ -f "$SCRIPT_DIR/lib/languages.sh" ]; then
    # shellcheck source=scripts/lib/languages.sh
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/languages.sh"
fi
if [ -f "$SCRIPT_DIR/lib/members.sh" ]; then
    # shellcheck source=scripts/lib/members.sh
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/members.sh"
fi

# ---------------------------------------------------------------------------
# Colors and formatting
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

# ---------------------------------------------------------------------------
# Score tracking
# ---------------------------------------------------------------------------

PASS=0
WARN=0
FAIL=0
TOTAL=0
# Use newline-delimited string for fixes (bash 3 compatible)
FIXES=""

check_pass() {
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
    printf "  ${GREEN}✅ PASS${NC}  %-22s %s\n" "$1" "$2"
}

check_warn() {
    WARN=$((WARN + 1))
    TOTAL=$((TOTAL + 1))
    printf "  ${YELLOW}⚠️  WARN${NC}  %-22s %s\n" "$1" "$2"
    if [ -n "$3" ]; then
        if [ -z "$FIXES" ]; then
            FIXES="$3"
        else
            FIXES="$FIXES
$3"
        fi
    fi
}

check_fail() {
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
    printf "  ${RED}❌ FAIL${NC}  %-22s %s\n" "$1" "$2"
    if [ -n "$3" ]; then
        if [ -z "$FIXES" ]; then
            FIXES="$3"
        else
            FIXES="$FIXES
$3"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Lookup helpers (bash 3 compatible — no associative arrays)
# ---------------------------------------------------------------------------

# Returns the expected config file path for a given agent key
agent_file() {
    case "$1" in
        claude-code) echo "CLAUDE.md" ;;
        cursor)      echo ".cursorrules" ;;
        copilot)     echo ".github/copilot-instructions.md" ;;
        gemini)      echo ".gemini/GEMINI.md" ;;
        codex)       echo "AGENTS.md" ;;
        aider)       echo ".aider-instructions.md" ;;
        *)           echo "" ;;
    esac
}

# Returns a friendly display name for a given agent key
agent_name() {
    case "$1" in
        claude-code) echo "Claude Code" ;;
        cursor)      echo "Cursor" ;;
        copilot)     echo "Copilot" ;;
        gemini)      echo "Gemini" ;;
        codex)       echo "Codex" ;;
        aider)       echo "Aider" ;;
        *)           echo "$1" ;;
    esac
}

# ---------------------------------------------------------------------------
# Detect whether we are running inside the standards repo itself
# ---------------------------------------------------------------------------

IS_STANDARDS_REPO=false
if [ -f "$PROJECT_ROOT/scripts/setup.sh" ] && [ -f "$PROJECT_ROOT/standards/shared/core-standards.md" ]; then
    IS_STANDARDS_REPO=true
fi

# ---------------------------------------------------------------------------
# Check 1: Configuration file exists
# ---------------------------------------------------------------------------

check_config() {
    local yml="$PROJECT_ROOT/.standards.yml"
    local legacy="$PROJECT_ROOT/.standards-config"

    if [ -f "$yml" ]; then
        local version=""
        if declare -f yaml_get >/dev/null 2>&1; then
            version=$(yaml_get "version" "$yml")
        else
            version=$(grep "^version:" "$yml" 2>/dev/null | sed 's/^version:[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)
        fi
        local ver_str=""
        [ -n "$version" ] && ver_str=" (version $version)"
        check_pass "Configuration" ".standards.yml found${ver_str}"
    elif [ -f "$legacy" ]; then
        check_warn "Configuration" ".standards-config found (legacy format)" \
            "Migrate: rename .standards-config to .standards.yml and convert to YAML format"
    else
        check_fail "Configuration" ".standards.yml not found" \
            "Create: add .standards.yml to this project (see .standards/templates/standards.yml.example)"
    fi
}

# ---------------------------------------------------------------------------
# Check 2: Agent config files present
# ---------------------------------------------------------------------------

check_agents() {
    # Determine which agents to check
    local agents_to_check=""

    # Try to load from config
    if declare -f read_standards_config >/dev/null 2>&1; then
        read_standards_config "$PROJECT_ROOT" 2>/dev/null || true
        agents_to_check="$STD_AGENTS"
    fi

    # If no agents declared in config, check all known agents
    if [ -z "${agents_to_check}" ]; then
        agents_to_check="claude-code cursor copilot gemini codex aider"
    fi

    for agent in $agents_to_check; do
        local file
        file=$(agent_file "$agent")
        local display
        display=$(agent_name "$agent")

        if [ -z "$file" ]; then
            check_warn "$display" "Unknown agent type: '$agent'" \
                "Check: '$agent' is not a recognized agent key in .standards.yml"
            continue
        fi

        local full_path="$PROJECT_ROOT/$file"
        if [ -f "$full_path" ]; then
            check_pass "$display" "$file present"
        else
            check_warn "$display" "$file missing" \
                "Run: make setup-agents  (to install missing $display config)"
        fi
    done
}

# ---------------------------------------------------------------------------
# Check 3: Checksums valid
# ---------------------------------------------------------------------------

check_checksums() {
    local checksums_file="$PROJECT_ROOT/.standards-checksums"

    if [ ! -f "$checksums_file" ]; then
        check_warn "Checksums" ".standards-checksums not found" \
            "Run: make setup  (to initialize checksums for agent configs)"
        return
    fi

    if ! declare -f compute_hash >/dev/null 2>&1; then
        check_warn "Checksums" "checksum library not available (skipping hash validation)" ""
        return
    fi

    local mismatches=0
    local checked=0
    local curated=""
    local drifted=""

    while IFS=' ' read -r key stored_hash; do
        [ -z "$key" ] && continue
        case "$key" in \#*) continue ;; esac

        local file
        file=$(agent_file "$key")
        [ -z "$file" ] && file="$key"

        local full_path="$PROJECT_ROOT/$file"
        [ ! -f "$full_path" ] && continue

        local current_hash
        if [ "$key" = ".aiderrc" ]; then
            current_hash=$(shasum -a 256 "$full_path" | awk '{print $1}')
        else
            current_hash=$(compute_hash "$full_path")
        fi
        checked=$((checked + 1))

        if [ "$current_hash" != "$stored_hash" ]; then
            # A file .standards.yml declares `managed: false` is hand-curated
            # (#183): sync never regenerates it, so its edits are not drift.
            if declare -f file_managed >/dev/null 2>&1 && ! file_managed "$PROJECT_ROOT" "$file"; then
                curated="${curated:+$curated, }$file"
            else
                mismatches=$((mismatches + 1))
                drifted="${drifted:+$drifted, }$file"
            fi
        fi
    done < "$checksums_file"

    local curated_note=""
    [ -n "$curated" ] && curated_note=" (curated, not drifted: $curated)"

    if [ "$checked" -eq 0 ]; then
        check_warn "Checksums" ".standards-checksums is empty or has no matching files" \
            "Run: make setup  (to regenerate checksums)"
    elif [ "$mismatches" -eq 0 ]; then
        check_pass "Checksums" "All config checksums match${curated_note}"
    else
        check_warn "Checksums" "$mismatches config file(s) modified since last assembly: $drifted${curated_note}" \
            "Run: make sync-standards  (after reviewing changes in .standards-pending/); persist a filled-in overview with project_overview:/key_commands: in .standards.yml, or declare the file curated with managed: { <file>: false }"
    fi
}

# ---------------------------------------------------------------------------
# Check 4: Languages match detected vs declared
# ---------------------------------------------------------------------------

# Members (root-relative sub-roots with their own .standards.yml), resolved
# once from the root config or by auto-discovery (scripts/lib/members.sh).
MEMBERS=""
MEMBERS_SOURCE=""
if declare -f resolve_members >/dev/null 2>&1; then
    MEMBERS=$(resolve_members "$PROJECT_ROOT" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if members_declared "$PROJECT_ROOT"; then
        MEMBERS_SOURCE="declared"
    else
        MEMBERS_SOURCE="auto-discovered"
    fi
fi

# in_list <word> <space-separated list>
in_list() {
    case " $2 " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

# check_languages_for <dir> <label> <skip-dirs> [--root-only]
#
# Compares the languages detected under <dir> with the ones its .standards.yml
# declares. Three findings:
#   - a declared key with no standards document or lint checks (unsupported):
#     agent assembly and lint-standards silently ignore it, so say so
#   - a supported language detected but not declared
#   - nothing declared although languages were detected
# Detection skips <skip-dirs> (the members, when checking the root) so a
# member's languages are judged by its own config, not demanded of the root.
# With --root-only (used for the root) only the directory's own manifests
# count: a tsconfig.json under apps/web must not be demanded of the root
# config, where it would make lint-standards look for a root tsconfig.json.
check_languages_for() {
    local dir="$1" label="$2" skip_dirs="$3" root_only="${4:-}"
    local detect_args=() s
    [ "$root_only" = "--root-only" ] && detect_args+=(--root-only)
    for s in $skip_dirs; do
        detect_args+=(--skip "$s")
    done

    local detected
    detected=$(bash "$DETECT_SCRIPT" ${detect_args[@]+"${detect_args[@]}"} "$dir" 2>/dev/null | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    local declared=""
    if declare -f read_standards_config >/dev/null 2>&1 && [ -f "$dir/.standards.yml" ]; then
        read_standards_config "$dir" 2>/dev/null || true
        declared=$(printf '%s\n' "$STD_LANGUAGES" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    fi

    # Declared but unsupported: no lang-NN standard, no lint-checks directory.
    local unsupported="" lang
    if declare -f language_supported >/dev/null 2>&1; then
        for lang in $declared; do
            language_supported "$lang" || unsupported="${unsupported:+$unsupported }$lang"
        done
    fi
    if [ -n "$unsupported" ]; then
        check_warn "$label" "Declared '$unsupported' is unsupported: no standards document or lint checks exist for it (ignored by agent assembly and lint-standards)" \
            "Remove '$unsupported' from the languages list in ${dir#"$PROJECT_ROOT/"}/.standards.yml, or contribute a lang-NN standard for it"
    fi

    # Only supported detections are ever suggested: an unsupported key such as
    # cpp (a CMake-only project) has no standards or checks, so asking for it
    # to be declared would only trip the unsupported warning above.
    local supported_detected=""
    for lang in $detected; do
        if declare -f language_supported >/dev/null 2>&1 && ! language_supported "$lang"; then
            continue
        fi
        supported_detected="${supported_detected:+$supported_detected }$lang"
    done

    if [ -z "$declared" ] && [ -z "$supported_detected" ]; then
        check_pass "$label" "No languages detected or declared"
        return
    fi

    if [ -z "$declared" ]; then
        check_warn "$label" "Languages detected but none declared in .standards.yml" \
            "Add: declare 'languages: [${supported_detected// /, }]' in .standards.yml"
        return
    fi

    # Detected (and supported) but not declared.
    local undeclared=""
    for lang in $supported_detected; do
        in_list "$lang" "$declared" || undeclared="${undeclared:+$undeclared }$lang"
    done

    if [ -n "$undeclared" ]; then
        check_warn "$label" "Detected '$undeclared' not in .standards.yml" \
            "Add: '$undeclared' to .standards.yml languages list"
    elif [ -z "$unsupported" ]; then
        check_pass "$label" "Declared languages match detected languages"
    fi
}

check_languages() {
    DETECT_SCRIPT=""

    if [ -f "$SCRIPT_DIR/detect-languages.sh" ]; then
        DETECT_SCRIPT="$SCRIPT_DIR/detect-languages.sh"
    elif [ -f "$PROJECT_ROOT/.standards/scripts/detect-languages.sh" ]; then
        DETECT_SCRIPT="$PROJECT_ROOT/.standards/scripts/detect-languages.sh"
    fi

    if [ -z "$DETECT_SCRIPT" ]; then
        check_warn "Languages" "detect-languages.sh not found (skipping)" ""
        return
    fi

    check_languages_for "$PROJECT_ROOT" "Languages" "$MEMBERS" --root-only

    local m
    for m in $MEMBERS; do
        [ -d "$PROJECT_ROOT/$m" ] || continue
        # Skip the members nested below this one (re-based onto it), so a
        # parent member is not asked to declare a child member's languages.
        # shellcheck disable=SC2086
        check_languages_for "$PROJECT_ROOT/$m" "Languages ($m)" "$(member_descendants "$m" $MEMBERS | tr '\n' ' ')"
    done
}

# ---------------------------------------------------------------------------
# Check 4b: Members (monorepo sub-roots) are present and configured
# ---------------------------------------------------------------------------

check_members() {
    local m problems=0 rejected

    # A declared entry that escapes the root (lexically, or physically through
    # a symlink) is dropped by resolve_members; say so rather than skip it.
    if declare -f rejected_members >/dev/null 2>&1; then
        while IFS= read -r rejected; do
            [ -z "$rejected" ] && continue
            check_fail "Members" "$rejected" \
                "Fix: members: entries must be real directories inside the project; remove the entry or replace the symlink with the directory"
            problems=$((problems + 1))
        done <<EOF
$(rejected_members "$PROJECT_ROOT" 2>/dev/null)
EOF
    fi

    if [ -z "$MEMBERS" ]; then
        if [ "$MEMBERS_SOURCE" = "declared" ] && [ "$problems" -eq 0 ]; then
            check_pass "Members" "members: [] (single-root project, auto-discovery off)"
        fi
        return
    fi

    for m in $MEMBERS; do
        if [ ! -d "$PROJECT_ROOT/$m" ]; then
            check_fail "Members" "declared member '$m' not found (no such directory)" \
                "Fix: remove '$m' from members: in .standards.yml, or create the directory"
            problems=$((problems + 1))
        elif [ ! -f "$PROJECT_ROOT/$m/.standards.yml" ]; then
            check_warn "Members" "member '$m' has no .standards.yml (its languages are never linted)" \
                "Run: .standards/scripts/setup.sh  (bootstraps $m/.standards.yml), or copy .standards/templates/standards.yml.example to $m/.standards.yml"
            problems=$((problems + 1))
        fi
    done

    if [ "$problems" -eq 0 ]; then
        check_pass "Members" "$(echo "$MEMBERS" | wc -w | tr -d ' ') member(s) $MEMBERS_SOURCE: ${MEMBERS// /, }"
    fi
}

# ---------------------------------------------------------------------------
# Check 5: Submodule present (skip in standards repo itself)
# ---------------------------------------------------------------------------

check_submodule() {
    if [ "$IS_STANDARDS_REPO" = "true" ]; then
        check_pass "Submodule" "Running in standards repo (submodule check skipped)"
        return
    fi

    local submodule_dir="$PROJECT_ROOT/.standards"

    if [ ! -d "$submodule_dir" ]; then
        check_fail "Submodule" ".standards/ directory not found" \
            "Run: curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash"
        return
    fi

    if [ ! -d "$submodule_dir/.git" ] && [ ! -f "$submodule_dir/.git" ]; then
        check_fail "Submodule" ".standards/ exists but is not a git repo" \
            "Run: git submodule update --init .standards"
        return
    fi

    local submodule_head=""
    submodule_head=$(cd "$submodule_dir" && git rev-parse HEAD 2>/dev/null) || submodule_head=""

    if [ -n "$submodule_head" ]; then
        check_pass "Submodule" ".standards/ is a valid git repo"
    else
        check_warn "Submodule" ".standards/ submodule may not be initialized" \
            "Run: git submodule update --init .standards"
    fi
}

# ---------------------------------------------------------------------------
# Check 6: Git hooks installed
#
# Recognises three hook managers. lefthook and husky take over core.hooksPath,
# so the native .git/hooks/post-merge that setup.sh writes never runs there;
# the standards-sync reminder and the Conventional Commits commit-msg hook are
# checked inside the manager's own config instead.
# ---------------------------------------------------------------------------

# hook_manager_installed <name> → 0 when git is actually wired to *this*
# manager: the effective hooks directory (core.hooksPath when set, else the
# repo's hooks dir) is either named after the manager (husky v9+ points
# core.hooksPath at .husky/_) or contains hook scripts written by it (lefthook
# install writes scripts that mention lefthook). A config file alone
# (lefthook.yml, .husky/) installs nothing, and a core.hooksPath owned by a
# different manager does not count.
# effective_hooks_dir → prints the directory git actually reads hooks from:
# core.hooksPath when set, else the repo's hooks dir (which differs from
# .git/hooks in linked worktrees). Always absolute.
effective_hooks_dir() {
    local hooks_dir
    hooks_dir=$(git -C "$PROJECT_ROOT" config --get core.hooksPath 2>/dev/null)
    if [ -z "$hooks_dir" ]; then
        hooks_dir=$(git -C "$PROJECT_ROOT" rev-parse --git-path hooks 2>/dev/null || echo ".git/hooks")
    fi
    case "$hooks_dir" in
        /*) ;;
        *) hooks_dir="$PROJECT_ROOT/$hooks_dir" ;;
    esac
    printf '%s\n' "$hooks_dir"
}

hook_manager_installed() {
    local name="$1" hooks_dir
    hooks_dir=$(effective_hooks_dir)
    # Whatever the config names, git only runs hooks that exist there.
    { [ -d "$hooks_dir" ] && [ -n "$(ls -A "$hooks_dir" 2>/dev/null)" ]; } || return 1
    if git -C "$PROJECT_ROOT" config --get core.hooksPath 2>/dev/null | grep -qi "$name"; then
        return 0
    fi
    grep -qil "$name" "$hooks_dir"/* 2>/dev/null
}

# lefthook_block <config> <hook> → prints the body of the top-level `<hook>:`
# block in a lefthook config (up to the next top-level key).
lefthook_block() {
    awk -v key="$2" '
        $0 ~ ("^" key ":") { inb = 1; next }
        inb && /^[^[:space:]#]/ { exit }
        inb { print }
    ' "$1" 2>/dev/null
}

check_git_hooks() {
    local lefthook_cfg="" f

    # hooks: in .standards.yml (#183) names the manager that owns the hooks:
    # standards (native hooks written by setup.sh, the default), lefthook,
    # husky, or custom (the project's own `make hooks` or similar). A declared
    # manager wins over file detection; custom satisfies the check outright,
    # since there is no config file for doctor to read.
    local declared=""
    if declare -f read_standards_config >/dev/null 2>&1; then
        read_standards_config "$PROJECT_ROOT" 2>/dev/null || true
        declared="${STD_HOOKS:-}"
    fi
    case "$declared" in
        ""|standards|lefthook|husky) ;;
        custom)
            check_pass "Git Hooks" "hooks: custom — the project's own hook manager owns post-merge/commit-msg (native hook check skipped)"
            return
            ;;
        *)
            check_warn "Git Hooks" "hooks: '$declared' is not recognised (expected standards, lefthook, husky or custom); checking hooks as if undeclared" \
                "Fix: set hooks: to standards | lefthook | husky | custom in .standards.yml"
            declared=""
            ;;
    esac

    for f in lefthook.yml lefthook.yaml .lefthook.yml .lefthook.yaml; do
        if [ -f "$PROJECT_ROOT/$f" ]; then
            lefthook_cfg="$f"
            break
        fi
    done

    if [ "$declared" = "lefthook" ] && [ -z "$lefthook_cfg" ]; then
        check_warn "Git Hooks" "hooks: lefthook declared but no lefthook.yml found (nothing manages the hooks yet)" \
            "Run: cp .standards/templates/lefthook.yml.example lefthook.yml && lefthook install  (or fix hooks: in .standards.yml)"
        return
    fi
    if [ "$declared" = "husky" ] && [ ! -d "$PROJECT_ROOT/.husky" ]; then
        check_warn "Git Hooks" "hooks: husky declared but no .husky/ directory found (nothing manages the hooks yet)" \
            "Run: npx husky init  (or fix hooks: in .standards.yml)"
        return
    fi

    if [ -n "$lefthook_cfg" ] && [ "$declared" != "husky" ]; then
        if hook_manager_installed lefthook; then
            check_pass "Git Hooks" "lefthook manages git hooks ($lefthook_cfg, hooks installed)"
        else
            check_warn "Git Hooks" "$lefthook_cfg present but lefthook hooks are not installed (nothing in $lefthook_cfg runs yet)" \
                "Run: lefthook install"
        fi
        if grep -qE '^commit-msg:' "$PROJECT_ROOT/$lefthook_cfg" 2>/dev/null; then
            check_pass "Git Hooks" "$lefthook_cfg has a commit-msg hook"
        else
            check_warn "Git Hooks" "$lefthook_cfg has no commit-msg hook (Conventional Commits not enforced locally)" \
                "Add the commit-msg block from .standards/templates/lefthook.yml.example to $lefthook_cfg, then: lefthook install"
        fi
        # Key alone is not enough: the post-merge block must actually run the
        # standards sync (same test the husky and native paths apply).
        if lefthook_block "$PROJECT_ROOT/$lefthook_cfg" post-merge | grep -qiE "standards|sync-standards|\.standards"; then
            check_pass "Git Hooks" "$lefthook_cfg post-merge hook contains standards sync"
        elif grep -qE '^post-merge:' "$PROJECT_ROOT/$lefthook_cfg" 2>/dev/null; then
            check_warn "Git Hooks" "$lefthook_cfg has a post-merge hook but it does not run the standards sync" \
                "Add the standards-sync-reminder command from .standards/templates/lefthook.yml.example to the post-merge block"
        else
            check_warn "Git Hooks" "$lefthook_cfg has no post-merge hook (lefthook bypasses .git/hooks/post-merge)" \
                "Add the post-merge block from .standards/templates/lefthook.yml.example to $lefthook_cfg"
        fi
        return
    fi

    if [ -d "$PROJECT_ROOT/.husky" ] && [ "$declared" != "lefthook" ]; then
        if hook_manager_installed husky; then
            check_pass "Git Hooks" "husky manages git hooks (.husky/, hooks installed)"
        else
            check_warn "Git Hooks" ".husky/ present but husky hooks are not installed (core.hooksPath unset; nothing in .husky/ runs yet)" \
                "Run: npx husky  (or npm install, which runs the prepare script)"
        fi
        if [ -f "$PROJECT_ROOT/.husky/commit-msg" ]; then
            check_pass "Git Hooks" ".husky/commit-msg hook present"
        else
            check_warn "Git Hooks" ".husky/ has no commit-msg hook (Conventional Commits not enforced locally)" \
                "Run: cp .standards/templates/husky-commit-msg.example .husky/commit-msg && chmod +x .husky/commit-msg"
        fi
        if [ -f "$PROJECT_ROOT/.husky/post-merge" ] \
           && grep -qiE "standards|sync-standards|\.standards" "$PROJECT_ROOT/.husky/post-merge" 2>/dev/null; then
            check_pass "Git Hooks" ".husky/post-merge contains standards sync"
        else
            check_warn "Git Hooks" ".husky/ has no post-merge standards sync (husky bypasses .git/hooks/post-merge)" \
                "Add a .husky/post-merge hook with the standards update check from .standards/templates/lefthook.yml.example (post-merge block)"
        fi
        return
    fi

    # Native git hooks (what setup.sh installs). Read from the directory git
    # actually uses: core.hooksPath, or the worktree's own hooks dir.
    local hooks_dir hook_file
    hooks_dir=$(effective_hooks_dir)
    hook_file="$hooks_dir/post-merge"

    if [ ! -f "$hook_file" ]; then
        check_fail "Git Hooks" "post-merge hook not installed" \
            "Run: make setup  (to install git hooks for automatic standards sync)"
    elif grep -qiE "standards|sync-standards|\.standards" "$hook_file" 2>/dev/null; then
        check_pass "Git Hooks" "post-merge hook contains standards sync"
    else
        check_warn "Git Hooks" "post-merge hook exists but lacks standards sync reference" \
            "Run: make setup  (to update git hooks with standards sync)"
    fi

    # git ignores hooks without the executable bit, so -f alone is not "installed".
    if [ -x "$hooks_dir/commit-msg" ]; then
        check_pass "Git Hooks" "commit-msg hook installed"
    elif [ -f "$hooks_dir/commit-msg" ]; then
        check_warn "Git Hooks" "commit-msg hook exists but is not executable (git will not run it)" \
            "Run: chmod +x $hooks_dir/commit-msg"
    else
        check_warn "Git Hooks" "no commit-msg hook validates Conventional Commits locally" \
            "Install a commit-msg hook: see .standards/templates/husky-commit-msg.example or .standards/templates/lefthook.yml.example"
    fi
}

# ---------------------------------------------------------------------------
# Check 7: .aiderrc matches canonical aiderrc.template
# ---------------------------------------------------------------------------

check_aiderrc_template_sync() {
    local aiderrc="$PROJECT_ROOT/.aiderrc"
    if [ ! -f "$aiderrc" ]; then
        check_pass "Aider Template" "No .aiderrc present; check skipped"
        return
    fi

    local template=""
    if [ -f "$PROJECT_ROOT/standards/agents/aider/aiderrc.template" ]; then
        template="$PROJECT_ROOT/standards/agents/aider/aiderrc.template"
    elif [ -f "$PROJECT_ROOT/.standards/standards/agents/aider/aiderrc.template" ]; then
        template="$PROJECT_ROOT/.standards/standards/agents/aider/aiderrc.template"
    fi

    if [ -z "$template" ]; then
        check_warn "Aider Template" "aiderrc.template not found, cannot verify .aiderrc sync" ""
        return
    fi

    if cmp -s "$aiderrc" "$template" 2>/dev/null; then
        check_pass "Aider Template" ".aiderrc matches aiderrc.template"
    else
        check_warn "Aider Template" ".aiderrc has drifted from aiderrc.template" \
            "Run: make sync-standards  (or accept customization and update .standards-checksums)"
    fi
}

# ---------------------------------------------------------------------------
# Check 8: Postgres MCP env var (if Postgres MCP is configured)
# ---------------------------------------------------------------------------

check_postgres_mcp() {
    local settings="$PROJECT_ROOT/.gemini/settings.json"
    if [ ! -f "$settings" ]; then
        check_pass "Postgres MCP" "No .gemini/settings.json; check skipped"
        return
    fi

    # Detect "postgres" specifically as a key under mcpServers. Use python3
    # for accuracy when available (handles arbitrary nesting / whitespace);
    # fall back to a tightened grep otherwise.
    local has_postgres="false"
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "
import json, sys
try:
    cfg = json.load(open('$settings'))
except Exception:
    sys.exit(1)
sys.exit(0 if 'postgres' in cfg.get('mcpServers', {}) else 1)
" 2>/dev/null; then
            has_postgres="true"
        fi
    else
        # Fallback: collapse whitespace, then anchor pattern to mcpServers
        # block. Imperfect (won't survive deeply nested mcpServers values
        # containing the literal "postgres" elsewhere) but better than a
        # bare grep.
        if tr -d '\n\r' < "$settings" 2>/dev/null | \
            grep -qE '"mcpServers"[[:space:]]*:[[:space:]]*\{[^{}]*"postgres"[[:space:]]*:'; then
            has_postgres="true"
        fi
    fi

    if [ "$has_postgres" = "false" ]; then
        check_pass "Postgres MCP" "Postgres MCP not configured; check skipped"
        return
    fi

    if [ -n "${POSTGRES_MCP_DATABASE_URL:-}" ]; then
        check_pass "Postgres MCP" "POSTGRES_MCP_DATABASE_URL is set"
    else
        check_warn "Postgres MCP" "Postgres MCP entry present but POSTGRES_MCP_DATABASE_URL unset" \
            "Set: export POSTGRES_MCP_DATABASE_URL=postgresql://...  (or remove the postgres block from .gemini/settings.json)"
    fi
}

# ---------------------------------------------------------------------------
# Check 9: .gitignore entries
# ---------------------------------------------------------------------------

check_gitignore() {
    local gitignore="$PROJECT_ROOT/.gitignore"

    if [ ! -f "$gitignore" ]; then
        check_warn "Gitignore" ".gitignore not found" \
            "Create: add a .gitignore with '.standards-pending/' and '*.pre-standards-setup'"
        return
    fi

    local missing=""
    if ! grep -qF ".standards-pending/" "$gitignore" 2>/dev/null; then
        missing=".standards-pending/"
    fi
    if ! grep -qF "*.pre-standards-setup" "$gitignore" 2>/dev/null; then
        if [ -z "$missing" ]; then
            missing="*.pre-standards-setup"
        else
            missing="$missing, *.pre-standards-setup"
        fi
    fi

    if [ -z "$missing" ]; then
        check_pass "Gitignore" "All required entries present"
    else
        check_warn "Gitignore" "Missing entries: $missing" \
            "Add: '$missing' to .gitignore"
    fi
}

# ---------------------------------------------------------------------------
# Main: run all checks
# ---------------------------------------------------------------------------

printf "\n%s\n" "${BOLD}Standards Health Check${NC}"
printf "=======================================\n\n"

check_config
check_members
check_agents
check_checksums
check_languages
check_submodule
check_git_hooks
check_aiderrc_template_sync
check_postgres_mcp
check_gitignore

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf "\n=======================================\n"

if [ "$TOTAL" -gt 0 ]; then
    pct=$(( (PASS * 100) / TOTAL ))
else
    pct=0
fi

printf "  ${BOLD}Score: %d/%d (%d%%)${NC}\n" "$PASS" "$TOTAL" "$pct"

if [ -n "$FIXES" ]; then
    printf "\n  %s\n" "${BOLD}Fixes needed:${NC}"
    printf '%s\n' "$FIXES" | while IFS= read -r fix; do
        printf "    -> %s\n" "$fix"
    done
fi

printf "\n"

# Exit with failure if any hard FAILs
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
