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
#   language_supported cobol || echo "no standard for cobol"

# Every language key the toolchain knows: the keys map_languages_to_blocks
# maps to a lang-*.md block. doctor.sh flags a declared key outside this list
# as unsupported.
SUPPORTED_LANGUAGES="python javascript typescript jvm java kotlin ruby rails rust swift dart zig go elixir cpp"

# language_supported <key>: true when <key> has a standards block.
language_supported() {
    case " $SUPPORTED_LANGUAGES " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

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
            cpp)        BLOCKS+=("lang-cpp.md") ;;
        esac
    done
    # Deduplicate and output space-separated on one line.
    if [ ${#BLOCKS[@]} -gt 0 ]; then
        printf '%s\n' "${BLOCKS[@]}" | sort -u | tr '\n' ' '
    fi
}

# ---------------------------------------------------------------------------
# Profiles (#227) — the third selector axis beside languages and role.
# ---------------------------------------------------------------------------

SUPPORTED_PROFILES="shared-core ui-surface"

# profile_supported <name> — true for a profile this repo ships.
profile_supported() {
    case " $SUPPORTED_PROFILES " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

# map_profiles_to_blocks "<names>" — one profile-<name>.md per declared
# profile, in declared order, duplicates dropped, trailing space like
# map_languages_to_blocks. Unknown names are skipped: validation is the
# caller's job and happens before any assembly.
map_profiles_to_blocks() {
    local seen=" " name out=""
    for name in $1; do
        profile_supported "$name" || continue
        case "$seen" in *" $name "*) continue ;; esac
        seen="$seen$name "
        out="${out}profile-${name}.md "
    done
    printf '%s' "$out"
}

# profile_display_name <name> — the sub-heading a profile block renders
# under in an assembled config.
profile_display_name() {
    case "$1" in
        shared-core) printf 'Shared Core\n' ;;
        ui-surface)  printf 'UI Surface\n' ;;
        *)
            # Fallback: hyphens to spaces, each word capitalised (bash 3.2).
            local word out=""
            for word in $(printf '%s' "$1" | tr '-' ' '); do
                out="${out:+$out }$(printf '%s%s' "$(printf '%s' "${word:0:1}" | tr '[:lower:]' '[:upper:]')" "${word:1}")"
            done
            printf '%s\n' "$out"
            ;;
    esac
}
