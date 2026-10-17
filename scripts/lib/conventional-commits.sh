#!/bin/bash
# scripts/lib/conventional-commits.sh — shared Conventional Commits helpers
#
# Sourced by:
#   scripts/lint-checks/common/conventional-commits.sh  (history check)
#   scripts/check-commit-message.sh                     (hook / PR-title check)
#
# One place for the accepted type list, the subject regex and the
# `commits:` block of .standards.yml so the linter, the commit-msg hooks and
# the PR-title check can never drift apart. bash 3.2 compatible; no
# associative arrays, no mapfile.

# Canonical cross-cutting types (shared/core-standards.md § Commit Messages)
# plus the extra Conventional Commits types the linter also accepts.
CC_TYPES='feat|fix|refactor|test|docs|chore|perf|ci|build|style|revert'

# <type>(<scope>)!: <subject> — scope and "!" optional, subject required.
CC_SUBJECT_REGEX="^(${CC_TYPES})(\([^)]+\))?!?:[[:space:]].+"

# cc_is_conventional <subject> → 0 when the subject line is a Conventional Commit
cc_is_conventional() {
    printf '%s' "$1" | grep -qE "$CC_SUBJECT_REGEX"
}

# cc_scope <subject> → prints the scope ("" when unscoped)
cc_scope() {
    printf '%s' "$1" | sed -nE "s/^(${CC_TYPES})\(([^)]+)\)!?:.*/\2/p"
}

# cc_is_exempt <subject> → 0 for messages git generates or that are rewritten
# before they reach mainline (autosquash prefixes, merge commits, git revert).
cc_is_exempt() {
    case "$1" in
        "fixup! "*|"squash! "*|"amend! "*|"Merge "*|"Revert \""*) return 0 ;;
    esac
    return 1
}

# cc_comment_prefix <project_root> → the prefix git treats as a comment line:
# core.commentString (git ≥ 2.45; may be several characters), else
# core.commentChar, else "#". Prints nothing for "auto": git then chooses a
# character absent from the user's message, which cannot be reconstructed
# from the final file, so callers must not strip anything in that case.
cc_comment_prefix() {
    local p
    p=$(git -C "$1" config --get core.commentString 2>/dev/null)
    [ -n "$p" ] || p=$(git -C "$1" config --get core.commentChar 2>/dev/null)
    case "$p" in
        '') printf '#' ;;
        auto) ;;
        *) printf '%s' "$p" ;;
    esac
}

# cc_config_get <project_root> <key> → scalar value of commits.<key> in
# .standards.yml (inline comments and single/double quotes stripped); prints
# nothing when unset.
cc_config_get() {
    local yml="$1/.standards.yml"
    local key="$2"
    [ -f "$yml" ] || return 0
    awk -v key="$key" '
        /^commits:/ { found = 1; next }
        found && /^[^[:space:]#]/ { exit }
        found && $0 ~ ("^[[:space:]]+" key ":") {
            sub("^[[:space:]]+" key ":[[:space:]]*", "")
            sub(/[[:space:]]+#.*$/, "")
            sub(/[[:space:]]+$/, "")
            gsub(/["\047]/, "")
            print
            exit
        }
    ' "$yml"
}

# cc_config_scopes <project_root> → space-separated commits.scopes allow-list.
# Accepts the inline form `scopes: [api, domain]` and the block form.
cc_config_scopes() {
    local yml="$1/.standards.yml"
    [ -f "$yml" ] || return 0
    awk '
        /^commits:/ { found = 1; next }
        found && /^[^[:space:]#]/ { exit }
        found && /^[[:space:]]+scopes:/ {
            line = $0
            sub(/^[[:space:]]+scopes:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            if (line ~ /^\[/) {
                gsub(/[][]/, "", line)
                gsub(/,/, " ", line)
                gsub(/["\047]/, "", line)
                print line
                exit
            }
            inlist = 1
            next
        }
        inlist && /^[[:space:]]+-[[:space:]]*/ {
            item = $0
            sub(/^[[:space:]]+-[[:space:]]*/, "", item)
            sub(/[[:space:]]+#.*$/, "", item)
            gsub(/["\047]/, "", item)
            printf "%s ", item
            next
        }
        # Blank and comment lines inside the block list do not end it.
        inlist && /^[[:space:]]*(#|$)/ { next }
        inlist { exit }
    ' "$yml" | tr -s ' ' | sed 's/^ //; s/ $//'
}

# cc_scope_allowed <scope> <allowlist> → 0 when the scope is empty, the
# allow-list is empty, or the scope exactly equals one entry of the
# (space-separated) allow-list. Compared token by token so a scope that
# contains whitespace ("api domain") can never match two adjacent entries.
cc_scope_allowed() {
    local scope="$1"
    local entry
    [ -z "$scope" ] && return 0
    [ -z "$2" ] && return 0
    for entry in $2; do
        [ "$entry" = "$scope" ] && return 0
    done
    return 1
}
