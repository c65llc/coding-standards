#!/bin/bash
# scripts/lib/tool-configs.sh — Sourceable library that installs the language
# tool configs (standards/agents/<lang>/*: ruff.toml, .prettierrc, ...) into a
# project without ever clobbering a customized one.
#
# Used by setup.sh and sync-standards.sh. Needs lib/checksums.sh and
# lib/languages.sh sourced before the call; do not execute it directly.
#
# .standards-checksums holds one `tool:<name> <hash>` line per config: the hash
# of the last *standards* version installed or offered, never of the project's
# own text. So a file matching its line is a verbatim standards copy and safe
# to replace, and a tuned or merged file never matches and is never written.

# _tool_hash <file> — SHA256 of the whole file (compute_hash is for assembled
# agent configs: it stops at the PROJECT-SPECIFIC sentinel).
_tool_hash() {
    shasum -a 256 "$1" | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# install_tool_configs <project_root> <agents_dir> <languages> <dry_run>
#
# For every tool config of every language:
#   missing                      → copy it
#   unchanged since we wrote it  → update it
#   customized, standards moved  → keep it, stage ours in .standards-pending/
#   customized, nothing new      → keep it
#
# Reads and updates the caller's NEW_CHECKSUMS string (the caller writes
# .standards-checksums). Sets TOOL_STAGED to the names that have a staged copy
# waiting, for append_tool_config_plan (lib/merge-plan.sh).
# ---------------------------------------------------------------------------
install_tool_configs() {
    local root="$1" agents_dir="$2" langs="$3" dry_run="$4"
    local lang config_file name target key stored offered verb done_msg alternate
    TOOL_STAGED=""

    for lang in $langs; do
        [ -d "$agents_dir/$lang" ] || continue
        for config_file in "$agents_dir/$lang"/* "$agents_dir/$lang"/.[!.]*; do
            [ -f "$config_file" ] || continue
            name="$(basename "$config_file")"
            if [ "$name" = ".golangci.yml" ]; then
                alternate="$(golangci_alternate_config "$root")"
                if [ -n "$alternate" ]; then
                    echo "   ℹ️  Keeping $alternate — $name not installed ($lang)"
                    continue
                fi
            fi
            target="$root/$name"
            key="tool:$name"
            stored=$(read_stored_hash "$key" "$root/$CHECKSUMS_FILE")
            offered=$(_tool_hash "$config_file")
            verb=""

            if [ ! -f "$target" ]; then
                verb="copy"; done_msg="Added"
            elif ! cmp -s "$config_file" "$target"; then
                if [ -n "$stored" ] && [ "$(_tool_hash "$target")" = "$stored" ]; then
                    verb="update"; done_msg="Updated"
                elif [ "$stored" = "$offered" ]; then
                    echo "   ℹ️  Kept your $name ($lang)"
                elif [ "$dry_run" = true ]; then
                    echo "  [dry-run] Kept your $name; Would stage: $config_file → $root/$PENDING_DIR/$name"
                    continue
                else
                    mkdir -p "$root/$PENDING_DIR"
                    if ! cp "$config_file" "$root/$PENDING_DIR/$name"; then
                        echo "   ⚠️  Failed to stage $name (non-fatal, continuing...)"
                        continue
                    fi
                    echo "   ⚠️  Kept your $name; the standards version is staged to $PENDING_DIR/$name"
                fi
            fi

            if [ -n "$verb" ]; then
                if [ "$dry_run" = true ]; then
                    echo "  [dry-run] Would $verb: $config_file → $target"
                    continue
                fi
                if ! cp "$config_file" "$target"; then
                    echo "   ⚠️  Failed to write $name (non-fatal, continuing...)"
                    continue
                fi
                echo "   ✅ $done_msg $name ($lang)"
            fi

            [ "$dry_run" = true ] && continue
            NEW_CHECKSUMS=$(update_checksum_entry "$key" "$offered" "$NEW_CHECKSUMS")
            if [ -f "$root/$PENDING_DIR/$name" ]; then
                TOOL_STAGED="${TOOL_STAGED:+$TOOL_STAGED }$name"
            fi
        done
    done
}
