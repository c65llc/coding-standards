#!/bin/bash
# scripts/lib/members.sh — Sourceable library: monorepo member (sub-root)
# resolution shared by lint-standards.sh, doctor.sh, setup.sh,
# sync-standards.sh and diff-standards.sh.
#
# Source this file; do not execute it directly.
#
# A *member* is a sub-directory of the project root that is a project in its
# own right — it has (or should have) its own .standards.yml declaring its
# languages, lint.exclude, coverage floors and so on. Every real consumer of
# these standards is a monorepo (#179): a Rust core plus a SwiftUI shell plus
# TypeScript workers, or server/ + web/ with the test directory, mypy and
# eslint configs all one level down. Without members the scripts assume a
# single root and report false positives.
#
# Where members come from (first match wins):
#   1. `members:` in the root .standards.yml — an explicit list of
#      root-relative paths. `members: []` means "no members" and disables
#      auto-discovery.
#   2. Auto-discovery — every */.standards.yml and */*/.standards.yml one or
#      two levels below the root. Hidden directories (.git, .standards,
#      .worktrees, .claude/worktrees, .Codex/worktrees …) are never entered,
#      nor are node_modules, vendor, third_party, dist, build, target,
#      coverage or .standards_tmp.
#
# Members are not recursive: a member's own `members:` key is ignored. Paths
# must stay inside the root — absolute paths and ".." are rejected lexically,
# and a declared path whose directory exists is also resolved physically: a
# symlink anywhere in the path, or a real location outside the root, is
# rejected too (the root .standards.yml is PR-controlled, so a committed
# symlink must not let the scripts read or write outside the checkout). Each
# rejection is noted on stderr; `rejected_members` lists them for callers
# that report findings. The root itself is always a member and is spelled ".".
#
# Usage:
#   source "$SCRIPT_DIR/lib/members.sh"
#   members=$(resolve_members "$PROJECT_ROOT")        # one path per line, no "."
#   for m in $members; do root=$(member_root "$PROJECT_ROOT" "$m"); ...; done
#   langs=$(aggregate_member_languages "$PROJECT_ROOT" "$root_langs" "$members" "$detect_script")

# yaml_list lives in checksums.sh; load it when the caller has not.
if ! declare -f yaml_list >/dev/null 2>&1; then
    # shellcheck source=checksums.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/checksums.sh"
fi

# Directory names auto-discovery never enters (hidden names are skipped by the
# glob itself, since dotglob is off).
MEMBER_SKIP_DIRS="node_modules vendor third_party dist build target coverage .standards .standards_tmp .worktrees .workspaces"

# ---------------------------------------------------------------------------
# member_normalize <path>
#
# Prints the normalized root-relative form of a declared member path
# (quotes and a trailing YAML comment removed, "./" and trailing slashes
# stripped). Returns 1, printing nothing, when the entry is empty, absolute,
# or escapes the root through "..".
# ---------------------------------------------------------------------------
member_normalize() {
    local p="$1"
    p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$p" in
        \"*) p="${p#\"}"; p="${p%%\"*}" ;;
        \'*) p="${p#\'}"; p="${p%%\'*}" ;;
        \#*) p="" ;;
        *)   p=$(printf '%s' "$p" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
    esac
    while [ "${p#./}" != "$p" ]; do p="${p#./}"; done
    while [ -n "$p" ] && [ "${p%/}" != "$p" ]; do p="${p%/}"; done
    case "$p" in
        ""|.|/*|..|../*|*/..|*/../*) return 1 ;;
    esac
    printf '%s\n' "$p"
}

# ---------------------------------------------------------------------------
# members_declared <root>
# True when the root .standards.yml carries a `members:` key (even an empty
# list), i.e. the project opted out of auto-discovery.
# ---------------------------------------------------------------------------
members_declared() {
    [ -f "$1/.standards.yml" ] && grep -qE '^members:' "$1/.standards.yml" 2>/dev/null
}

# ---------------------------------------------------------------------------
# member_escape_reason <root> <normalized-member>
#
# Physical containment check for a declared member whose lexical form passed
# member_normalize. Prints a reason and returns 0 when the path must be
# rejected: some component of it (including the leaf) is a symlink, or its
# real location (pwd -P) is not <root> or below it. Returns 1 silently when
# the member is fine — or when its directory does not exist, which is left
# for member_problem to report as "not found".
# ---------------------------------------------------------------------------
member_escape_reason() {
    local root="$1" rel="$2" prefix="" seg rest root_real m_real
    [ -d "$root/$rel" ] || return 1
    rest="$rel"
    while [ -n "$rest" ]; do
        seg="${rest%%/*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        prefix="${prefix:+$prefix/}$seg"
        if [ -L "$root/$prefix" ]; then
            printf "declared member '%s' rejected: '%s' is a symlink (members must be real directories inside the project)\n" "$rel" "$prefix"
            return 0
        fi
    done
    root_real=$(cd "$root" 2>/dev/null && pwd -P) || return 1
    m_real=$(cd "$root/$rel" 2>/dev/null && pwd -P) || return 1
    case "$m_real" in
        "$root_real"|"$root_real"/*) return 1 ;;
    esac
    printf "declared member '%s' rejected: resolves to '%s', outside the project root\n" "$rel" "$m_real"
    return 0
}

# member__each_declared <root> <callback>
# Runs <callback> <accepted-path> or <callback> "" <reason> for every raw
# `members:` entry of the root .standards.yml, in declaration order.
member__each_declared() {
    local root="$1" cb="$2" raw entry norm reason
    [ -f "$root/.standards.yml" ] || return 0
    raw=$(yaml_list "members" "$root/.standards.yml" | tr ' ' '\n')
    # yaml_list splits inline lists on commas but joins everything with
    # spaces; a path with a space is not supported (nor is it in lint.exclude).
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        if ! norm=$(member_normalize "$entry"); then
            "$cb" "" "ignoring invalid entry '$entry' (must be a relative path inside the project)"
        elif reason=$(member_escape_reason "$root" "$norm"); then
            "$cb" "" "$reason"
        else
            "$cb" "$norm"
        fi
    done <<EOF
$raw
EOF
    return 0
}

member__emit_accepted() {
    if [ -n "$1" ]; then printf '%s\n' "$1"; else echo "members: $2" >&2; fi
}

member__emit_rejected() {
    [ -z "$1" ] && printf '%s\n' "$2"
    return 0
}

# ---------------------------------------------------------------------------
# declared_members <root>
# Prints the accepted `members:` entries of the root .standards.yml, one per
# line, in declaration order. Invalid entries (lexical or physical, see
# member_escape_reason) are dropped with a note on stderr. Prints nothing when
# the key is absent or the list is empty.
# ---------------------------------------------------------------------------
declared_members() {
    member__each_declared "$1" member__emit_accepted
}

# ---------------------------------------------------------------------------
# rejected_members <root>
# Prints one reason line per `members:` entry that declared_members dropped,
# so callers can surface the rejection as a finding instead of a silent skip.
# Prints nothing when `members:` is absent (discovery never rejects: it simply
# does not enter symlinks).
# ---------------------------------------------------------------------------
rejected_members() {
    member__each_declared "$1" member__emit_rejected
}

# member__skipped <root-relative path>: true when any segment is on the skip list.
member__skipped() {
    local rel="$1" seg rest skip
    rest="$rel"
    while [ -n "$rest" ]; do
        seg="${rest%%/*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        for skip in $MEMBER_SKIP_DIRS; do
            [ "$seg" = "$skip" ] && return 0
        done
    done
    return 1
}

# ---------------------------------------------------------------------------
# discover_members <root>
# Prints every sub-directory one or two levels below <root> that holds a
# .standards.yml, sorted, skipping hidden directories, symlinks and the names
# in MEMBER_SKIP_DIRS.
# ---------------------------------------------------------------------------
discover_members() {
    local root="$1" d rel
    [ -d "$root" ] || return 0
    for d in "$root"/*/ "$root"/*/*/; do
        d="${d%/}"
        [ -d "$d" ] || continue
        [ -L "$d" ] && continue
        [ -f "$d/.standards.yml" ] || continue
        rel="${d#"$root/"}"
        case "$rel" in
            */*) [ -L "$root/${rel%%/*}" ] && continue ;;
        esac
        member__skipped "$rel" && continue
        printf '%s\n' "$rel"
    done | sort -u
    return 0
}

# ---------------------------------------------------------------------------
# resolve_members <root>
# The declared list when `members:` is present, else the discovered one. One
# root-relative path per line; never includes ".".
# ---------------------------------------------------------------------------
resolve_members() {
    local root="$1"
    if members_declared "$root"; then
        declared_members "$root"
    else
        discover_members "$root"
    fi
}

# member_root <root> <member>: absolute directory of a member ("." → root).
member_root() {
    if [ "$2" = "." ]; then printf '%s\n' "$1"; else printf '%s/%s\n' "$1" "$2"; fi
}

# member_label <member>: "(root)" for ".", the path otherwise.
member_label() {
    if [ "$1" = "." ]; then printf '(root)\n'; else printf '%s\n' "$1"; fi
}

# ---------------------------------------------------------------------------
# member_problem <root> <member>
# Prints a one-line description when a declared member is unusable (directory
# missing, or no .standards.yml), nothing when it is fine. Exit status mirrors
# that: 0 = fine, 1 = problem printed.
# ---------------------------------------------------------------------------
member_problem() {
    local dir
    dir=$(member_root "$1" "$2")
    if [ ! -d "$dir" ]; then
        printf "declared member '%s' not found (no such directory)\n" "$2"
        return 1
    fi
    if [ ! -f "$dir/.standards.yml" ]; then
        printf "member '%s' has no .standards.yml (language checks skipped)\n" "$2"
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# member_languages <root> <member> [detect-script]
#
# Space-separated languages of one member: the `languages:` list of its own
# .standards.yml when it has one — an explicit `languages: []` (or no key) is
# respected as "none", exactly as lint-standards.sh treats it, so a language
# the member deliberately did not declare is never assembled or installed on
# its behalf — else, for a member with no config at all, what <detect-script>
# finds in it (when given). Prints nothing for a missing directory.
# ---------------------------------------------------------------------------
member_languages() {
    local root="$1" member="$2" detect="${3:-}" dir langs=""
    dir=$(member_root "$root" "$member")
    [ -d "$dir" ] || return 0
    if [ -f "$dir/.standards.yml" ]; then
        langs=$(yaml_list "languages" "$dir/.standards.yml" | sed 's/[[:space:]]*$//')
    elif [ -n "$detect" ] && [ -x "$detect" ]; then
        langs=$("$detect" "$dir" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    fi
    printf '%s\n' "$langs"
}

# ---------------------------------------------------------------------------
# dedupe_words <words...>
# Prints the given words once each, first occurrence wins, space-separated.
# ---------------------------------------------------------------------------
dedupe_words() {
    local out="" w
    # shellcheck disable=SC2048,SC2086
    for w in $*; do
        case " $out " in
            *" $w "*) ;;
            *) out="${out:+$out }$w" ;;
        esac
    done
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# aggregate_member_languages <root> <root-languages> <members> [detect-script]
#
# Union of the root's languages and every member's (declared, or detected
# with <detect-script> for a member without a config), deduplicated in order.
# Root-level agent configs are assembled from this union so an agent that only
# reads the root file (Cursor, Copilot, Aider) still sees every member's rules.
# ---------------------------------------------------------------------------
aggregate_member_languages() {
    local root="$1" base="$2" members="$3" detect="${4:-}" m all
    all="$base"
    for m in $members; do
        all="$all $(member_languages "$root" "$m" "$detect")"
    done
    dedupe_words "$all"
}
