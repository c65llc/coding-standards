#!/bin/bash
# scripts/diff-standards.sh — Show what sync-standards would change without modifying anything
#
# For each declared agent, assembles to a temp file and diffs it against the
# installed config. Prints color-coded output and cleans up temp files.
#
# Usage:
#   ./scripts/diff-standards.sh
#   make diff-standards

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ---------------------------------------------------------------------------
# Source helpers
# ---------------------------------------------------------------------------

if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
fi

# ---------------------------------------------------------------------------
# Map languages to block filenames (shared logic)
# ---------------------------------------------------------------------------

map_languages_to_blocks() {
    local BLOCKS=()
    for lang in $1; do
        case "$lang" in
            python)     BLOCKS+=("lang-python.md") ;;
            javascript) BLOCKS+=("lang-javascript.md") ;;
            typescript) BLOCKS+=("lang-typescript.md") ;;
            jvm)        BLOCKS+=("lang-java.md" "lang-kotlin.md") ;;
            java)       BLOCKS+=("lang-java.md") ;;
            kotlin)     BLOCKS+=("lang-kotlin.md") ;;
            ruby)       BLOCKS+=("lang-ruby.md") ;;
            rails)      BLOCKS+=("lang-rails.md" "lang-ruby.md") ;;
            rust)       BLOCKS+=("lang-rust.md") ;;
            swift)      BLOCKS+=("lang-swift.md") ;;
            dart)       BLOCKS+=("lang-dart.md") ;;
            zig)        BLOCKS+=("lang-zig.md") ;;
            go)         BLOCKS+=("lang-go.md") ;;
            elixir)     BLOCKS+=("lang-elixir.md") ;;
        esac
    done
    printf '%s\n' "${BLOCKS[@]}" | sort -u | tr '\n' ' '
}

# ---------------------------------------------------------------------------
# Locate standards directories
# ---------------------------------------------------------------------------

STANDARDS_DIR=""
if [ -d "$PROJECT_ROOT/.standards" ]; then
    STANDARDS_DIR="$PROJECT_ROOT/.standards"
elif [ -d "$SCRIPT_DIR/../standards" ]; then
    STANDARDS_DIR="$SCRIPT_DIR/.."
fi

AGENTS_DIR=""
if [ -n "$STANDARDS_DIR" ] && [ -d "$STANDARDS_DIR/standards/agents" ]; then
    AGENTS_DIR="$STANDARDS_DIR/standards/agents"
elif [ -d "$SCRIPT_DIR/../standards/agents" ]; then
    AGENTS_DIR="$SCRIPT_DIR/../standards/agents"
fi

BLOCKS_DIR=""
if [ -n "$STANDARDS_DIR" ] && [ -d "$STANDARDS_DIR/standards/shared/blocks" ]; then
    BLOCKS_DIR="$STANDARDS_DIR/standards/shared/blocks"
elif [ -d "$SCRIPT_DIR/../standards/shared/blocks" ]; then
    BLOCKS_DIR="$SCRIPT_DIR/../standards/shared/blocks"
fi

ASSEMBLE_SCRIPT=""
if [ -x "$SCRIPT_DIR/assemble-config.sh" ]; then
    ASSEMBLE_SCRIPT="$SCRIPT_DIR/assemble-config.sh"
elif [ -n "$STANDARDS_DIR" ] && [ -x "$STANDARDS_DIR/scripts/assemble-config.sh" ]; then
    ASSEMBLE_SCRIPT="$STANDARDS_DIR/scripts/assemble-config.sh"
fi

# ---------------------------------------------------------------------------
# Read project configuration
# ---------------------------------------------------------------------------

printf "\n%s\n" "${BOLD}Standards Diff${NC}"
printf "=======================================\n\n"

if ! declare -f read_standards_config >/dev/null 2>&1 || ! read_standards_config "$PROJECT_ROOT" 2>/dev/null; then
    printf "%s\n" "${YELLOW}⚠️  No .standards.yml found in $PROJECT_ROOT${NC}"
    printf "   Run 'make setup' to initialize standards for this project.\n\n"
    exit 0
fi

ROLE="${STD_ROLE:-service}"
DETECTED_LANGS="${STD_LANGUAGES:-}"
AGENTS_LIST="${STD_AGENTS:-}"

# Default agents if not in config
if [ -z "$AGENTS_LIST" ]; then
    AGENTS_LIST="claude-code cursor copilot gemini codex aider"
fi

# Build block arguments
# shellcheck disable=SC2086
LANG_BLOCKS=$(map_languages_to_blocks "$DETECTED_LANGS")
ROLE_BLOCK="role-${ROLE}.md"

BLOCK_ARGS=()
for b in $LANG_BLOCKS; do
    BLOCK_ARGS+=("$b")
done
if [ -n "$BLOCKS_DIR" ] && [ -f "$BLOCKS_DIR/$ROLE_BLOCK" ]; then
    BLOCK_ARGS+=("$ROLE_BLOCK")
fi

# ---------------------------------------------------------------------------
# Diff each agent
# ---------------------------------------------------------------------------

if [ -z "$ASSEMBLE_SCRIPT" ]; then
    printf "%s\n\n" "${RED}❌ assemble-config.sh not found — cannot diff agent configs${NC}"
    exit 1
fi

if [ -z "$AGENTS_DIR" ]; then
    printf "%s\n\n" "${RED}❌ standards/agents directory not found${NC}"
    exit 1
fi

if [ -z "$BLOCKS_DIR" ]; then
    printf "%s\n\n" "${RED}❌ standards/shared/blocks directory not found${NC}"
    exit 1
fi

CHANGED=0
UNCHANGED=0
NEW_FILES=0
SKIPPED=0

TEMP_FILES=()
# shellcheck disable=SC2317
cleanup() {
    for f in "${TEMP_FILES[@]}"; do
        rm -f "$f"
    done
}
trap cleanup EXIT

for agent in $AGENTS_LIST; do
    BASE_TEMPLATE="$AGENTS_DIR/$agent/base-$agent.md"
    if [ ! -f "$BASE_TEMPLATE" ]; then
        continue
    fi

    OUTPUT_PATH=""
    case "$agent" in
        claude-code) OUTPUT_PATH="$PROJECT_ROOT/CLAUDE.md" ;;
        cursor)      OUTPUT_PATH="$PROJECT_ROOT/.cursorrules" ;;
        copilot)     OUTPUT_PATH="$PROJECT_ROOT/.github/copilot-instructions.md" ;;
        gemini)      OUTPUT_PATH="$PROJECT_ROOT/.gemini/GEMINI.md" ;;
        codex)       OUTPUT_PATH="$PROJECT_ROOT/AGENTS.md" ;;
        aider)       OUTPUT_PATH="$PROJECT_ROOT/.aider-instructions.md" ;;
        *)           continue ;;
    esac

    # shellcheck disable=SC2059
    printf "${CYAN}→ %s${NC}  (%s)\n" "$agent" "$(basename "$OUTPUT_PATH")"

    # Assemble to temp file
    TEMP_FILE=$(mktemp)
    TEMP_FILES+=("$TEMP_FILE")

    if ! "$ASSEMBLE_SCRIPT" "$agent" "$BLOCKS_DIR" "$BASE_TEMPLATE" "$TEMP_FILE" ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"} 2>/dev/null; then
        printf "  %s\n\n" "${YELLOW}⚠️  Assembly failed — skipping${NC}"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if [ ! -f "$OUTPUT_PATH" ]; then
        printf "  %s\n" "${GREEN}+ Would create: $OUTPUT_PATH${NC}"
        NEW_FILES=$((NEW_FILES + 1))
        printf "\n"
        continue
    fi

    # Compute diff
    DIFF_OUTPUT=$(diff --unified=3 "$OUTPUT_PATH" "$TEMP_FILE" 2>/dev/null || true)

    if [ -z "$DIFF_OUTPUT" ]; then
        printf "  %s\n" "${GREEN}✅ Up to date${NC}"
        UNCHANGED=$((UNCHANGED + 1))
    else
        ADDED=$(printf '%s\n' "$DIFF_OUTPUT" | grep -c '^+[^+]' || true)
        REMOVED=$(printf '%s\n' "$DIFF_OUTPUT" | grep -c '^-[^-]' || true)
        # shellcheck disable=SC2059
        printf "  ${YELLOW}~ Changes: +%d/-%d lines${NC}\n" "$ADDED" "$REMOVED"
        # Print colored diff (SC2059: colors in format strings are intentional)
        # shellcheck disable=SC2059
        printf '%s\n' "$DIFF_OUTPUT" | while IFS= read -r line; do
            case "$line" in
                +*) printf "${GREEN}%s${NC}\n" "$line" ;;
                -*) printf "${RED}%s${NC}\n" "$line" ;;
                @*) printf "${CYAN}%s${NC}\n" "$line" ;;
                *)  printf "%s\n" "$line" ;;
            esac
        done
        CHANGED=$((CHANGED + 1))
    fi
    printf "\n"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf "=======================================\n"
# shellcheck disable=SC2059
printf "  ${BOLD}Summary:${NC} "
# shellcheck disable=SC2059
printf "${GREEN}%d up to date${NC}  " "$UNCHANGED"
# shellcheck disable=SC2059
printf "${YELLOW}%d would change${NC}  " "$CHANGED"
# shellcheck disable=SC2059
printf "${GREEN}%d new${NC}  " "$NEW_FILES"
if [ "$SKIPPED" -gt 0 ]; then
    # shellcheck disable=SC2059
    printf "${YELLOW}%d skipped${NC}" "$SKIPPED"
fi
printf "\n\n"

if [ "$CHANGED" -gt 0 ] || [ "$NEW_FILES" -gt 0 ]; then
    printf "%s\n\n" "Run ${BOLD}make sync-standards${NC} to apply changes."
fi

exit 0
