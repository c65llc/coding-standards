#!/bin/bash
# scripts/diff-standards.sh — Show what sync-standards would change without modifying anything
#
# For each declared agent, assembles to a temp file and diffs it against the
# installed assembled config (CLAUDE.md, .cursorrules, AGENTS.md, ...). Prints
# color-coded output and cleans up temp files. Auxiliary files that sync copies
# verbatim (.aiderrc, .gemini/settings.json, .claude/settings.json, Cursor
# commands) are outside this diff.
#
# Usage:
#   ./.standards/scripts/diff-standards.sh [--exit-code] [project-root]
#   ./scripts/diff-standards.sh            (from a clone of the standards repo)
#   make diff-standards
#
# Options:
#   --exit-code   Exit 1 when any assembled agent config would change or be
#                 created (otherwise always exits 0). Lets the script gate CI.
#   -h, --help    Show this help.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

EXIT_CODE=false
PROJECT_ROOT_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --exit-code)
            EXIT_CODE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 2
            ;;
        *)
            PROJECT_ROOT_ARG="$1"
            shift
            ;;
    esac
done

if [ -n "$PROJECT_ROOT_ARG" ]; then
    PROJECT_ROOT="$(cd "$PROJECT_ROOT_ARG" 2>/dev/null && pwd)" || {
        echo "Error: project root not found: $PROJECT_ROOT_ARG" >&2
        exit 2
    }
else
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Refuse to run from inside the .standards/ submodule (see lib/guard.sh).
# shellcheck source=lib/guard.sh disable=SC1091
source "$SCRIPT_DIR/lib/guard.sh"
refuse_if_inside_standards_dir "$PROJECT_ROOT" "diff-standards.sh" || exit 2

# ---------------------------------------------------------------------------
# Colors — real escape bytes ($'...'), so they render through %s as well as
# inside format strings. Single-quoted '\033[...]' would print literally when
# passed as a printf argument.
# ---------------------------------------------------------------------------

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'
BOLD=$'\033[1m'

# ---------------------------------------------------------------------------
# Source helpers
# ---------------------------------------------------------------------------

if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
fi

# ---------------------------------------------------------------------------
# Map languages to block filenames (shared: scripts/lib/languages.sh)
# ---------------------------------------------------------------------------

# shellcheck source=lib/languages.sh disable=SC1091
source "$SCRIPT_DIR/lib/languages.sh"

# Monorepo members (shared: scripts/lib/members.sh)
# shellcheck source=lib/members.sh disable=SC1091
source "$SCRIPT_DIR/lib/members.sh"

# ---------------------------------------------------------------------------
# Locate standards directories
# ---------------------------------------------------------------------------

STANDARDS_DIR=""
if [ -d "$PROJECT_ROOT/.standards" ]; then
    STANDARDS_DIR="$PROJECT_ROOT/.standards"
elif [ -d "$SCRIPT_DIR/../standards" ]; then
    STANDARDS_DIR="$SCRIPT_DIR/.."
fi

# How the consumer should invoke the sibling scripts. Inside a consumer project
# the scripts live under .standards/; in a clone of the standards repo they are
# under ./scripts/. Never name a Make target — the consumer may not have one.
if [ "$STANDARDS_DIR" = "$PROJECT_ROOT/.standards" ]; then
    SCRIPTS_PREFIX="./.standards/scripts"
else
    SCRIPTS_PREFIX="./scripts"
fi
SYNC_CMD="$SCRIPTS_PREFIX/sync-standards.sh"
SETUP_CMD="$SCRIPTS_PREFIX/setup.sh"

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
    printf "   Run %s to initialize standards for this project.\n\n" "$SETUP_CMD"
    exit 0
fi

ROLE="${STD_ROLE:-service}"
DETECTED_LANGS="${STD_LANGUAGES:-}"
PROFILES="${STD_PROFILES:-}"
for _p in $PROFILES; do
    if ! profile_supported "$_p"; then
        echo "ERROR: Unknown profile: $_p (expected one of: ${SUPPORTED_PROFILES// /, })" >&2
        exit 2
    fi
done
unset _p
export STANDARDS_PROFILES="$PROFILES"
AGENTS_LIST="${STD_AGENTS:-}"

# Default agents if not in config
if [ -z "$AGENTS_LIST" ]; then
    AGENTS_LIST="claude-code cursor copilot gemini codex aider"
fi

# Same language union as setup.sh and sync-standards.sh — root (declared,
# else its own manifests), non-member sub-roots, members — otherwise this diff
# would report drift forever.
MEMBERS=$(resolve_members "$PROJECT_ROOT" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
if [ -x "$SCRIPT_DIR/detect-languages.sh" ]; then
    if [ -z "$DETECTED_LANGS" ]; then
        DETECTED_LANGS=$("$SCRIPT_DIR/detect-languages.sh" --root-only "$PROJECT_ROOT")
    fi
    DETECTED_LANGS=$(dedupe_words "$DETECTED_LANGS" "$(subroot_languages "$PROJECT_ROOT" "$MEMBERS" "$SCRIPT_DIR/detect-languages.sh")")
fi
if [ -n "$MEMBERS" ]; then
    DETECTED_LANGS=$(aggregate_member_languages "$PROJECT_ROOT" "$DETECTED_LANGS" "$MEMBERS" "$SCRIPT_DIR/detect-languages.sh")
    printf "  %s\n\n" "Members: ${MEMBERS// /, } (languages: ${DETECTED_LANGS:-none})"
fi

PROFILES=$(aggregate_member_profiles "$PROJECT_ROOT" "$PROFILES" "$MEMBERS") || exit 2
export STANDARDS_PROFILES="$PROFILES"

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
# Profile blocks (#227), after the role block, in declared order.
for pb in $(map_profiles_to_blocks "$PROFILES"); do
    if [ -n "$BLOCKS_DIR" ] && [ -f "$BLOCKS_DIR/$pb" ]; then
        BLOCK_ARGS+=("$pb")
    else
        echo "⚠️  profile block $pb not found; skipping" >&2
    fi
done

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
CURATED=0

TEMP_FILES=()
# shellcheck disable=SC2317
cleanup() {
    for f in ${TEMP_FILES[@]+"${TEMP_FILES[@]}"}; do
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

    printf "%s→ %s%s  (%s)\n" "$CYAN" "$agent" "$NC" "$(basename "$OUTPUT_PATH")"

    # Assemble to temp file. Seed it from the installed config so the assembler
    # carries the consumer's PROJECT-SPECIFIC section across, exactly as sync
    # does — otherwise that section always reads as drift and --exit-code can
    # never pass. The assembler may also drop a *.pre-standards-setup backup
    # next to the temp file for a hand-written config; clean that up too.
    TEMP_FILE=$(mktemp)
    TEMP_FILES+=("$TEMP_FILE" "$TEMP_FILE.pre-standards-setup")
    if [ -f "$OUTPUT_PATH" ]; then
        cp "$OUTPUT_PATH" "$TEMP_FILE"
    fi

    # --project-root: the temp file lives outside the project, so the assembler
    # cannot infer the root from its location and would fall back to the cwd,
    # mis-resolving {{PROJECT_NAME}} when [project-root] points elsewhere.
    if ! "$ASSEMBLE_SCRIPT" --project-root "$PROJECT_ROOT" \
            "$agent" "$BLOCKS_DIR" "$BASE_TEMPLATE" "$TEMP_FILE" ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"} 2>/dev/null; then
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

    # Curated file (#183): `managed: { <file>: false }` in .standards.yml. Sync
    # never regenerates it, so its differences are shown for manual review
    # but are not pending changes (and do not fail --exit-code).
    IS_CURATED=false
    if declare -f file_managed >/dev/null 2>&1 && ! file_managed "$PROJECT_ROOT" "$OUTPUT_PATH"; then
        IS_CURATED=true
    fi

    # Compute diff
    DIFF_OUTPUT=$(diff --unified=3 "$OUTPUT_PATH" "$TEMP_FILE" 2>/dev/null || true)

    if [ -z "$DIFF_OUTPUT" ]; then
        if [ "$IS_CURATED" = true ]; then
            printf "  %s\n" "${GREEN}✅ Up to date (curated: managed: false)${NC}"
        else
            printf "  %s\n" "${GREEN}✅ Up to date${NC}"
        fi
        UNCHANGED=$((UNCHANGED + 1))
    else
        ADDED=$(printf '%s\n' "$DIFF_OUTPUT" | grep -c '^+[^+]' || true)
        REMOVED=$(printf '%s\n' "$DIFF_OUTPUT" | grep -c '^-[^-]' || true)
        if [ "$IS_CURATED" = true ]; then
            printf "  %s~ Curated (managed: false): +%d/-%d lines differ from the upstream template — review manually; sync will not apply them%s\n" "$CYAN" "$ADDED" "$REMOVED" "$NC"
        else
            printf "  %s~ Changes: +%d/-%d lines%s\n" "$YELLOW" "$ADDED" "$REMOVED" "$NC"
        fi
        # Print colored diff
        printf '%s\n' "$DIFF_OUTPUT" | while IFS= read -r line; do
            case "$line" in
                +*) printf "%s%s%s\n" "$GREEN" "$line" "$NC" ;;
                -*) printf "%s%s%s\n" "$RED" "$line" "$NC" ;;
                @*) printf "%s%s%s\n" "$CYAN" "$line" "$NC" ;;
                *)  printf "%s\n" "$line" ;;
            esac
        done
        if [ "$IS_CURATED" = true ]; then
            CURATED=$((CURATED + 1))
        else
            CHANGED=$((CHANGED + 1))
        fi
    fi
    printf "\n"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf "=======================================\n"
printf "  %sSummary:%s " "$BOLD" "$NC"
printf "%s%d up to date%s  " "$GREEN" "$UNCHANGED" "$NC"
printf "%s%d would change%s  " "$YELLOW" "$CHANGED" "$NC"
printf "%s%d new%s  " "$GREEN" "$NEW_FILES" "$NC"
if [ "$CURATED" -gt 0 ]; then
    printf "%s%d curated (manual review)%s  " "$CYAN" "$CURATED" "$NC"
fi
if [ "$SKIPPED" -gt 0 ]; then
    printf "%s%d skipped%s" "$YELLOW" "$SKIPPED" "$NC"
fi
printf "\n\n"

PENDING=false
if [ "$CHANGED" -gt 0 ] || [ "$NEW_FILES" -gt 0 ]; then
    PENDING=true
    printf "Run %s%s%s to apply changes.\n" "$BOLD" "$SYNC_CMD" "$NC"
    printf "Preview the write operations first with %s%s --dry-run%s.\n\n" "$BOLD" "$SYNC_CMD" "$NC"
fi

if [ "$EXIT_CODE" = true ] && [ "$PENDING" = true ]; then
    exit 1
fi

exit 0
