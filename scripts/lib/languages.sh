#!/bin/bash
# Language → standards-block mapping shared by setup.sh, sync-standards.sh, and
# diff-standards.sh.
#
# This is the single source of truth for how detected language keys map to the
# lang-*.md block filenames assembled into agent configs. When a new language
# standard is added, update ONLY this table.
#
# Usage:
#   source "$SCRIPT_DIR/lib/languages.sh"
#   blocks=$(map_languages_to_blocks "python typescript go")

# Map detected languages to block filenames.
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
    # Deduplicate and output space-separated on one line.
    if [ ${#BLOCKS[@]} -gt 0 ]; then
        printf '%s\n' "${BLOCKS[@]}" | sort -u | tr '\n' ' '
    fi
}
