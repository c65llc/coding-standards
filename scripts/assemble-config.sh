#!/bin/bash
# Assemble a single self-contained agent config from a base template + content blocks.
#
# Usage:
#   assemble-config.sh <agent> <blocks-dir> <base-template> <output-file> [block1 block2 ...]
#
# Arguments:
#   agent         — Agent name (claude-code, cursor, copilot, gemini, aider, codex)
#   blocks-dir    — Path to standards/shared/blocks/
#   base-template — Path to the base template file
#   output-file   — Path to write the assembled config
#   block1...     — Additional block filenames (lang-python.md, role-service.md, etc.)

set -e

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
    # Strip lang-/role- prefix and .md suffix
    local base="${filename##lang-}"
    base="${base##role-}"
    base="${base%.md}"
    # Capitalize first letter (compatible with bash 3.x / macOS)
    printf '%s%s' "$(echo "${base:0:1}" | tr '[:lower:]' '[:upper:]')" "${base:1}"
}

# ---------------------------------------------------------------------------
# Assemble the config into a temp file (for atomic write)
# ---------------------------------------------------------------------------

OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

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

    # Extra blocks (lang-* and role-*)
    lang_header_printed=false
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
        else
            # Unknown prefix — include without a section header, warn
            echo "WARNING [$AGENT]: block '$block_basename' has unknown prefix (expected lang- or role-), including without section header" >&2
            append_block "$block_path" "" ""
        fi
    done

    # Project-specific section
    printf '\n'
    if [ -n "$PROJECT_SPECIFIC_CONTENT" ]; then
        printf '%s\n' "$PROJECT_SPECIFIC_CONTENT"
    else
        printf '%s — DO NOT EDIT THIS LINE -->\n' "$SENTINEL"
        printf '\n'
        printf '<!-- Add project-specific instructions below this line. This section is preserved across re-assembly. -->\n'
    fi

} > "$TMPFILE"

# Atomic move to final destination
mv "$TMPFILE" "$OUTPUT_FILE"
trap - EXIT

echo "[$AGENT] Assembled config written to: $OUTPUT_FILE"
