#!/bin/bash
# Assemble a single self-contained agent config from a base template + content blocks.
#
# Usage:
#   assemble-config.sh [--project-root <path>] [--skills-dir <path>] <agent> <blocks-dir> <base-template> <output-file> [block1 block2 ...]
#
# Options:
#   --project-root <path> — Explicit consumer project root for template-var resolution.
#                           Falls back to git rev-parse on output-file's dir, then pwd.
#   --skills-dir <path>   — Source of the agent-neutral skills (default: the
#                           standards/skills/ directory beside <blocks-dir>'s
#                           standards tree). Agents that read a single config
#                           file (codex, gemini, aider) get a "## Skills" index
#                           of them; the file-based agents (claude-code,
#                           cursor, copilot) get skill files from
#                           assemble-skills.sh instead.
#
# Arguments:
#   agent         — Agent name (claude-code, cursor, copilot, gemini, aider, codex)
#   blocks-dir    — Path to standards/shared/blocks/
#   base-template — Path to the base template file
#   output-file   — Path to write the assembled config
#   block1...     — Additional block filenames (lang-python.md, role-service.md, etc.)

set -e

# ---------------------------------------------------------------------------
# Option parsing (before positional args)
# ---------------------------------------------------------------------------

PROJECT_ROOT_OVERRIDE=""
SKILLS_DIR_OVERRIDE=""
# Declared profiles (#227): --profiles "<names>" wins; otherwise the
# STANDARDS_PROFILES environment variable the sync/setup/diff scripts export,
# so the guarded assembler's positional contract stays untouched.
PROFILES="${STANDARDS_PROFILES:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)
            PROJECT_ROOT_OVERRIDE="$2"
            shift 2
            ;;
        --skills-dir)
            SKILLS_DIR_OVERRIDE="$2"
            shift 2
            ;;
        --profiles)
            PROFILES="$2"
            shift 2
            ;;
        --) shift; break ;;
        *)  break ;;
    esac
done

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

AGENT="${1:-}"
BLOCKS_DIR="${2:-}"
BASE_TEMPLATE="${3:-}"
OUTPUT_FILE="${4:-}"
shift 4 2>/dev/null || true
EXTRA_BLOCKS=("$@")

if [ -z "$AGENT" ] || [ -z "$BLOCKS_DIR" ] || [ -z "$BASE_TEMPLATE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: $(basename "$0") <agent> <blocks-dir> <base-template> <output-file> [block1 block2 ...]" >&2
    echo "  agent         — Agent name (claude-code, cursor, copilot, gemini, aider, codex)" >&2
    echo "  blocks-dir    — Path to standards/shared/blocks/" >&2
    echo "  base-template — Path to base template file" >&2
    echo "  output-file   — Path to write assembled config" >&2
    exit 1
fi

if [ ! -f "$BASE_TEMPLATE" ]; then
    echo "ERROR [$AGENT]: base template not found: $BASE_TEMPLATE" >&2
    exit 1
fi

if [ ! -d "$BLOCKS_DIR" ]; then
    echo "ERROR [$AGENT]: blocks directory not found: $BLOCKS_DIR" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

ASSEMBLED_HEADER="<!-- Assembled by coding-standards setup.sh — do not edit above the PROJECT-SPECIFIC marker -->"
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"

# Agent-neutral skills (standards/skills/, #194). Agents that read one config
# file get an index of them; see lib/skills.sh for the per-agent shapes.
_LANGS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/languages.sh"
if [ -f "$_LANGS_LIB" ]; then
    # shellcheck source=lib/languages.sh disable=SC1091
    source "$_LANGS_LIB"
fi
if ! declare -f profile_display_name >/dev/null 2>&1; then
    # Fallback when the library is not shipped: the derived name as is.
    profile_display_name() { printf '%s\n' "$1"; }
fi
_SKILLS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/skills.sh"
if [ -f "$_SKILLS_LIB" ]; then
    # shellcheck disable=SC1090,SC1091
    source "$_SKILLS_LIB"
fi
SKILLS_DIR="$SKILLS_DIR_OVERRIDE"
if [ -z "$SKILLS_DIR" ]; then
    # <standards>/shared/blocks → <standards>/skills
    SKILLS_DIR="$(cd "$BLOCKS_DIR/../.." 2>/dev/null && pwd)/skills"
fi

# Common blocks always included in order
COMMON_BLOCKS=(
    "architecture-core.md"
    "testing-policy.md"
    "security-summary.md"
    "naming-conventions.md"
    "git-workflow.md"
    "documentation-policy.md"
)

# ---------------------------------------------------------------------------
# Extract existing project-specific section (if any)
# ---------------------------------------------------------------------------

PROJECT_SPECIFIC_CONTENT=""

if [ -f "$OUTPUT_FILE" ]; then
    if grep -qF "$SENTINEL" "$OUTPUT_FILE" 2>/dev/null; then
        # File has sentinel — extract everything from sentinel line to EOF
        PROJECT_SPECIFIC_CONTENT="$(grep -n "$SENTINEL" "$OUTPUT_FILE" | head -1 | cut -d: -f1 | xargs -I{} tail -n "+{}" "$OUTPUT_FILE")"
    elif ! grep -qF "Assembled by coding-standards" "$OUTPUT_FILE" 2>/dev/null; then
        # File exists, no sentinel, and no assembled header — it was manually created
        BACKUP_FILE="${OUTPUT_FILE}.pre-standards-setup"
        echo "WARNING [$AGENT]: $OUTPUT_FILE appears to be manually created (no assembly header or sentinel)." >&2
        echo "WARNING [$AGENT]: Backing up to $BACKUP_FILE" >&2
        cp "$OUTPUT_FILE" "$BACKUP_FILE"
    fi
fi

# ---------------------------------------------------------------------------
# Helper: append a block file with a section header
# ---------------------------------------------------------------------------

append_block() {
    local block_file="$1"
    local section_header="$2"
    local sub_header="$3"

    if [ ! -f "$block_file" ]; then
        echo "WARNING [$AGENT]: block not found, skipping: $block_file" >&2
        return
    fi

    if [ -n "$section_header" ]; then
        printf '\n%s\n' "$section_header"
    fi
    if [ -n "$sub_header" ]; then
        printf '\n%s\n' "$sub_header"
    fi
    printf '\n'
    cat "$block_file"
}

# ---------------------------------------------------------------------------
# Helper: derive display name from block filename
# ---------------------------------------------------------------------------

derive_name() {
    local filename="$1"
    # Strip lang-/role-/profile- prefix and .md suffix
    local base="${filename##lang-}"
    base="${base##role-}"
    base="${base##profile-}"
    base="${base%.md}"
    # Capitalize first letter (compatible with bash 3.x / macOS)
    printf '%s%s' "$(echo "${base:0:1}" | tr '[:lower:]' '[:upper:]')" "${base:1}"
}

# ---------------------------------------------------------------------------
# Assemble the config into a temp file (for atomic write)
# ---------------------------------------------------------------------------

OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

# The consumer project root: an explicit override (callers writing to temp
# files), else git on the output file's directory, else pwd. Used for the
# template variables and for the path the skills index points at.
if [ -n "$PROJECT_ROOT_OVERRIDE" ]; then
    _TV_ROOT="$PROJECT_ROOT_OVERRIDE"
else
    _TV_ROOT="$(git -C "$OUTPUT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Where the skills index tells the agent to read the full runbooks: the
# project-relative path when the skills directory is inside the project (the
# .standards/ submodule), else the conventional submodule path.
skills_runbook_ref() {
    local abs_root abs_skills
    abs_root="$(cd "$_TV_ROOT" 2>/dev/null && pwd -P)"
    abs_skills="$(cd "$SKILLS_DIR" 2>/dev/null && pwd -P)"
    case "$abs_skills" in
        "$abs_root"/*) printf '%s\n' "${abs_skills#"$abs_root"/}" ;;
        *)             printf '.standards/standards/skills\n' ;;
    esac
}

TMPFILE="$(mktemp "${OUTPUT_DIR}/.assemble-config.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

{
    # Header comment
    printf '%s\n' "$ASSEMBLED_HEADER"
    printf '\n'

    # Base template
    cat "$BASE_TEMPLATE"

    # Common blocks — assembler injects section headers, blocks contain only content
    for block in "${COMMON_BLOCKS[@]}"; do
        block_path="${BLOCKS_DIR}/${block}"
        if [ ! -f "$block_path" ]; then
            echo "WARNING [$AGENT]: common block not found, skipping: $block_path" >&2
            continue
        fi
        # Derive section header from filename
        case "$block" in
            architecture-core.md)   section="## Architecture" ;;
            testing-policy.md)      section="## Testing" ;;
            security-summary.md)    section="## Security" ;;
            naming-conventions.md)  section="## Naming Conventions" ;;
            git-workflow.md)        section="## Git Workflow" ;;
            documentation-policy.md) section="## Documentation" ;;
            *)                      section="" ;;
        esac
        append_block "$block_path" "$section" ""
    done

    # Extra blocks (lang-*, role-* and profile-*)
    lang_header_printed=false
    profiles_header_printed=false
    for block in "${EXTRA_BLOCKS[@]}"; do
        block_path="${BLOCKS_DIR}/${block}"
        block_basename="$(basename "$block")"

        if [[ "$block_basename" == lang-* ]]; then
            lang_name="$(derive_name "$block_basename")"
            if [ "$lang_header_printed" = false ]; then
                append_block "$block_path" "## Language Standards" "### ${lang_name}"
                lang_header_printed=true
            else
                append_block "$block_path" "" "### ${lang_name}"
            fi
        elif [[ "$block_basename" == role-* ]]; then
            append_block "$block_path" "## Project Type" ""
        elif [[ "$block_basename" == profile-* ]]; then
            # Profiles (#227): one "## Profiles" section, one sub-heading per
            # declared profile, in the order the blocks were passed.
            profile_name="$(profile_display_name "$(derive_name "$block_basename" | tr '[:upper:]' '[:lower:]')")"
            if [ "$profiles_header_printed" = false ]; then
                append_block "$block_path" "## Profiles" "### ${profile_name}"
                profiles_header_printed=true
            else
                append_block "$block_path" "" "### ${profile_name}"
            fi
        else
            # Unknown prefix — include without a section header, warn
            echo "WARNING [$AGENT]: block '$block_basename' has unknown prefix (expected lang-, role- or profile-), including without section header" >&2
            append_block "$block_path" "" ""
        fi
    done

    # Skills index (#194) for agents that read one config file. Claude Code,
    # Cursor and Copilot discover the skill files assemble-skills.sh installs.
    if declare -f render_skills_index >/dev/null 2>&1 && [ -d "$SKILLS_DIR" ]; then
        case " $SKILLS_INDEX_AGENTS " in
            *" $AGENT "*)
                printf '\n## Skills\n\n'
                render_skills_index "$SKILLS_DIR" "$(skills_runbook_ref)" "$PROFILES"
                ;;
        esac
    fi

    # Project-specific section
    printf '\n'
    if [ -n "$PROJECT_SPECIFIC_CONTENT" ]; then
        printf '%s\n' "$PROJECT_SPECIFIC_CONTENT"
    else
        printf '%s — DO NOT EDIT THIS LINE -->\n' "$SENTINEL"
        printf '\n'
        printf '<!-- Add project-specific instructions below this line. This section is preserved across re-assembly. -->\n'
        printf '\n'
        printf '## Known Traps\n'
        printf '\n'
        printf '| Trap | Why it bites | Issue | Date |\n'
        printf '|------|--------------|-------|------|\n'
        printf '| Example: run `make ci` from the repo root, not from a package directory | Sub-make targets resolve paths from the working directory and silently skip suites | #000 | YYYY-MM-DD |\n'
    fi

} > "$TMPFILE"

# Atomic move to final destination
mv "$TMPFILE" "$OUTPUT_FILE"
trap - EXIT

# Resolve template variables ({{PROJECT_NAME}} etc.) in place.
_TV_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/template-vars.sh"
if [ -f "$_TV_LIB" ]; then
    # shellcheck disable=SC1090,SC1091
    source "$_TV_LIB"
    resolve_template_vars "$OUTPUT_FILE" "$_TV_ROOT"
fi

echo "[$AGENT] Assembled config written to: $OUTPUT_FILE"
