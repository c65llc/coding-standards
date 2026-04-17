#!/bin/bash
# Shared assembly loop used by setup.sh and sync-standards.sh.
# Wraps scripts/assemble-config.sh with checksum guarding (should_assemble /
# write_pending from lib/checksums.sh) so a customized target is staged as a
# pending update instead of being clobbered.

# Load checksum helpers if not already sourced.
if ! type should_assemble >/dev/null 2>&1; then
    _ASM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck disable=SC1091
    source "$_ASM_LIB_DIR/checksums.sh"
fi

# Usage:
#   assemble_agent_config_guarded <agent> <assemble_script> <blocks_dir> \
#       <base_template> <output_path> <checksums_path> <dry_run> [block ...]
#
# Exit codes:
#   0 — wrote output (fresh or replacement)
#   1 — wrote pending update (.standards-pending/)
#   2 — skipped (manual file without assembly header; backup staged)
#   3 — assembler failed
#
# On exit 0, caller should update its checksums using compute_hash +
# update_checksum_entry. On exit 1, caller should track the basename in its
# "pending" accumulator for MERGE_PLAN emission.
assemble_agent_config_guarded() {
    local agent="$1"
    local assemble_script="$2"
    local blocks_dir="$3"
    local base_template="$4"
    local output_path="$5"
    local checksums_path="$6"
    local dry_run="$7"
    shift 7
    local blocks=("$@")

    if [ "$dry_run" = "true" ]; then
        if [ -f "$output_path" ]; then
            echo "  [dry-run] Would assemble (guarded): $output_path"
        else
            echo "  [dry-run] Would create: $output_path"
        fi
        return 0
    fi

    local sa_rc=0
    should_assemble "$output_path" "$checksums_path" || sa_rc=$?

    case "$sa_rc" in
        0)
            if "$assemble_script" "$agent" "$blocks_dir" "$base_template" \
                "$output_path" ${blocks[@]+"${blocks[@]}"}; then
                return 0
            else
                return 3
            fi
            ;;
        1)
            local tmp
            tmp=$(mktemp)
            if "$assemble_script" "$agent" "$blocks_dir" "$base_template" \
                "$tmp" ${blocks[@]+"${blocks[@]}"} 2>/dev/null; then
                write_pending "$output_path" "$agent"
                cp "$tmp" "$PENDING_DIR/$(basename "$output_path")"
                rm -f "$tmp"
                return 1
            else
                rm -f "$tmp"
                return 3
            fi
            ;;
        2)
            return 2
            ;;
    esac
}
