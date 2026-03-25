#!/bin/bash
# scripts/lib/checksums.sh — Sourceable library of checksum functions.
#
# Used by setup.sh and sync-standards.sh to detect customized agent configs
# and avoid overwriting user edits during re-assembly.
#
# Source this file; do not execute it directly.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/checksums.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CHECKSUMS_FILE=".standards-checksums"
PENDING_DIR=".standards-pending"
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
ASSEMBLY_HEADER="Assembled by coding-standards"

# ---------------------------------------------------------------------------
# compute_hash <file>
#
# Computes SHA256 of the assembler-controlled portion of a file (content above
# the sentinel marker), with trailing whitespace normalized to avoid false
# positives from editor auto-formatting.
#
# Outputs the hex digest to stdout.
# ---------------------------------------------------------------------------
compute_hash() {
    local file="$1"
    # strip_trailing_blanks: portable awk that removes trailing blank lines,
    # avoiding the BSD sed multi-line loop syntax which is not portable.
    local strip_trailing_blanks='{ lines[NR]=$0; if(NF) last=NR } END { for(i=1;i<=last;i++) print lines[i] }'
    local content
    if grep -qF "$SENTINEL" "$file" 2>/dev/null; then
        content=$(sed "/$SENTINEL/,\$d" "$file" | awk "$strip_trailing_blanks")
    else
        content=$(awk "$strip_trailing_blanks" "$file")
    fi
    printf '%s' "$content" | shasum -a 256 | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# read_stored_hash <key> [checksums_file]
#
# Reads the stored hash for <key> from the checksums file.
# Outputs the hash to stdout, or empty string if not found.
#
# File format (one entry per line):
#   <key> <hash>
# ---------------------------------------------------------------------------
read_stored_hash() {
    local key="$1"
    local file="${2:-$CHECKSUMS_FILE}"
    if [ ! -f "$file" ]; then
        echo ""
        return 0
    fi
    awk -v k="$key" '$1 == k { print $2; exit }' "$file"
}

# ---------------------------------------------------------------------------
# update_checksum_entry <key> <hash> <existing_content>
#
# Adds or updates the <key> <hash> entry in <existing_content> (an in-memory
# checksums string). Returns the updated string via stdout.
#
# This is intentionally in-memory so callers can accumulate multiple entries
# and write the file once at the end.
# ---------------------------------------------------------------------------
update_checksum_entry() {
    local key="$1"
    local hash="$2"
    local content="$3"
    # Remove any existing line for this key, then append the new entry.
    local updated
    updated=$(printf '%s\n' "$content" | grep -v "^${key} " || true)
    if [ -n "$updated" ]; then
        printf '%s\n%s %s\n' "$updated" "$key" "$hash"
    else
        printf '%s %s\n' "$key" "$hash"
    fi
}

# ---------------------------------------------------------------------------
# has_assembly_header <file>
#
# Returns 0 (true) if <file> contains the "Assembled by coding-standards"
# header, 1 (false) otherwise.
# ---------------------------------------------------------------------------
has_assembly_header() {
    local file="$1"
    grep -qF "$ASSEMBLY_HEADER" "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# write_pending <output_file> <agent> <blocks_dir> <base_template> [block ...]
#
# Writes a pending-update stub to .standards-pending/<basename-of-output_file>
# so the operator knows a new assembly is available but was skipped because the
# file was customized.
#
# Creates .standards-pending/ if it does not exist.
# ---------------------------------------------------------------------------
write_pending() {
    local output_file="$1"
    local agent="$2"
    shift 2
    local basename
    basename="$(basename "$output_file")"

    mkdir -p "$PENDING_DIR"

    local pending_path="$PENDING_DIR/$basename"
    {
        printf '# Pending update for: %s\n' "$output_file"
        printf '# Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '#\n'
        printf '# This file was NOT written because the destination has been customized.\n'
        printf '# To apply the update, review the diff and merge manually.\n'
        printf '#\n'
        printf '# For guided merge instructions, see:\n'
        printf '#   docs/superpowers/merge-pending-standards.md\n'
        printf '#\n'
        printf '# Agent: %s\n' "$agent"
        printf '# Remaining args: %s\n' "$*"
    } > "$pending_path"
}

# ---------------------------------------------------------------------------
# should_assemble <output_file> [checksums_file]
#
# Decision function: determines whether assembly should proceed for <output_file>.
#
# Exit codes:
#   0 — assemble normally
#         (file does not exist, or file matches stored hash, or file has the
#          assembly header but no stored hash exists yet)
#   1 — skip: file has been customized (hash differs from stored hash)
#   2 — skip: file was manually created without the assembly header
#             (a .bak copy is written to .standards-pending/ as a safety backup)
#
# Warnings are printed to stderr when skipping or backing up.
# ---------------------------------------------------------------------------
should_assemble() {
    local output_file="$1"
    local checksums_file="${2:-$CHECKSUMS_FILE}"

    # File does not exist yet — safe to assemble.
    if [ ! -f "$output_file" ]; then
        return 0
    fi

    local file_key
    file_key=$(basename "$output_file")
    local stored_hash
    stored_hash=$(read_stored_hash "$file_key" "$checksums_file")

    # File exists but was never recorded by us.
    if [ -z "$stored_hash" ]; then
        if has_assembly_header "$output_file"; then
            # Our header is present but we have no hash — first run after
            # this library was introduced, or hash file was wiped. Allow
            # assembly so we can record a baseline.
            return 0
        else
            # File was created by the user (no assembly header).  Back it up
            # and skip assembly to avoid destroying their work.
            echo "WARNING: $output_file has no assembly header and no stored hash — skipping assembly. Backing up to $PENDING_DIR/$(basename "$output_file").bak" >&2
            mkdir -p "$PENDING_DIR"
            cp "$output_file" "$PENDING_DIR/$(basename "$output_file").bak"
            return 2
        fi
    fi

    # We have a stored hash — compare it to the current file content.
    local current_hash
    current_hash=$(compute_hash "$output_file")

    if [ "$current_hash" = "$stored_hash" ]; then
        # File is unchanged since last assembly — safe to overwrite.
        return 0
    else
        # File has been edited since last assembly — do not overwrite.
        echo "WARNING: $output_file has been customized since last assembly — skipping. Run 'make sync-standards' after reviewing $PENDING_DIR/ to merge updates." >&2
        return 1
    fi
}
