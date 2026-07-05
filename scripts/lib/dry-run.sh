#!/bin/bash
# Dry-run aware file operations shared by setup.sh and sync-standards.sh.
#
# These helpers read the global DRY_RUN variable at call time: when DRY_RUN is
# "true" they print what would happen and make no changes; otherwise they
# perform the operation. Callers must define DRY_RUN (true|false) before use.
#
# Usage:
#   source "$SCRIPT_DIR/lib/dry-run.sh"
#   DRY_RUN=false
#   dry_run_cp src dst
#   printf '...' | dry_run_write dst

dry_run_cp() {
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [dry-run] Would copy: $1 → $2"
    else
        cp "$1" "$2"
    fi
}

dry_run_mkdir() {
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [dry-run] Would create directory: $1"
    else
        mkdir -p "$1"
    fi
}

dry_run_write() {
    local target="$1"
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [dry-run] Would write: $target"
        cat > /dev/null
    else
        cat > "$target"
    fi
}

dry_run_append() {
    local target="$1"
    if [ "${DRY_RUN:-false}" = true ]; then
        echo "  [dry-run] Would append to: $target"
        cat > /dev/null
    else
        cat >> "$target"
    fi
}
