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
            mismatches=$((mismatches + 1))
        fi
    done < "$checksums_file"

    if [ "$checked" -eq 0 ]; then
        check_warn "Checksums" ".standards-checksums is empty or has no matching files" \
            "Run: make setup  (to regenerate checksums)"
    elif [ "$mismatches" -eq 0 ]; then
        check_pass "Checksums" "All config checksums match"
    else
        check_warn "Checksums" "$mismatches config file(s) modified since last assembly" \
            "Run: make sync-standards  (after reviewing changes in .standards-pending/)"
    fi
}

# ---------------------------------------------------------------------------
# Check 4: Languages match detected vs declared
# ---------------------------------------------------------------------------

check_languages() {
    local detect_script=""

    if [ -f "$SCRIPT_DIR/detect-languages.sh" ]; then
        detect_script="$SCRIPT_DIR/detect-languages.sh"
    elif [ -f "$PROJECT_ROOT/.standards/scripts/detect-languages.sh" ]; then
        detect_script="$PROJECT_ROOT/.standards/scripts/detect-languages.sh"
    fi

    if [ -z "$detect_script" ]; then
        check_warn "Languages" "detect-languages.sh not found (skipping)" ""
        return
    fi

    # Detect languages in current project
    local detected
    detected=$(bash "$detect_script" "$PROJECT_ROOT" 2>/dev/null | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')

    # Get declared languages from config
    local declared=""
    if declare -f read_standards_config >/dev/null 2>&1; then
        read_standards_config "$PROJECT_ROOT" 2>/dev/null || true
        declared=$(printf '%s\n' "$STD_LANGUAGES" | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    fi

    if [ -z "$declared" ] && [ -z "$detected" ]; then
        check_pass "Languages" "No languages detected or declared"
        return
    fi

    if [ -z "$declared" ]; then
        check_warn "Languages" "Languages detected but none declared in .standards.yml" \
            "Add: declare 'languages: [${detected// /, }]' in .standards.yml"
        return
    fi

    # Find languages detected but not declared
    local undeclared=""
    for lang in $detected; do
        local found=false
        for decl in $declared; do
            if [ "$lang" = "$decl" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = "false" ]; then
            if [ -z "$undeclared" ]; then
                undeclared="$lang"
            else
                undeclared="$undeclared $lang"
            fi
        fi
    done

    if [ -n "$undeclared" ]; then
        check_warn "Languages" "Detected '$undeclared' not in .standards.yml" \
            "Add: '$undeclared' to .standards.yml languages list"
    else
        check_pass "Languages" "Declared languages match detected languages"
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
# ---------------------------------------------------------------------------

check_git_hooks() {
    local hook_file="$PROJECT_ROOT/.git/hooks/post-merge"

    if [ ! -f "$hook_file" ]; then
        check_fail "Git Hooks" "post-merge hook not installed" \
            "Run: make setup  (to install git hooks for automatic standards sync)"
        return
    fi

    if grep -qiE "standards|sync-standards|\.standards" "$hook_file" 2>/dev/null; then
        check_pass "Git Hooks" "post-merge hook contains standards sync"
    else
        check_warn "Git Hooks" "post-merge hook exists but lacks standards sync reference" \
            "Run: make setup  (to update git hooks with standards sync)"
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
# Check 8: .gitignore entries
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
check_agents
check_checksums
check_languages
check_submodule
check_git_hooks
check_aiderrc_template_sync
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
