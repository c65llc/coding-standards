#!/bin/bash
# scripts/lib/lint-files.sh — Sourceable library: candidate-file enumeration
# for lint-check modules.
#
# Source this file from a check module; do not execute it directly.
#
# Why this exists (#180): `find` walks everything under the project root —
# agent worktrees (.worktrees, .claude/worktrees, .Codex/worktrees), build
# output (target, .build, DerivedData), package caches (.pnpm-store) and
# gitignored artifacts — so the linter timed out on real repositories and
# flagged non-code. This library enumerates candidates with `git ls-files -z`
# (tracked) plus `git ls-files -z -o --exclude-standard` (untracked, not
# ignored), so .gitignore is honoured and nested worktrees are never walked,
# and falls back to a pruned `find -print0` only when the project is not a git
# repository.
#
# Usage (from scripts/lint-checks/<group>/<check>.sh):
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)/lint-files.sh"
#   FILES=$(lint_list_files "$PROJECT_ROOT" docs)        # extra excludes optional
#   FILES=$(lint_list_files --strict "$PROJECT_ROOT")    # security checks, see below
#   HITS=$(lint_grep_hits "$FILES" "$PROJECT_ROOT" '#' 'eval\(')   # "rel:line:content"
#   MATCHES=$(lint_grep_files "$FILES" -lE 'pattern')     # batched grep
#   echo "$MATCHES" | lint_strip_root "$PROJECT_ROOT"     # project-relative paths
#   BAD=$(lint_unscannable_files "$PROJECT_ROOT" docs)    # names the list cannot carry
#
# Exclusion policy:
#   default   Built-in directory exclusions and `.standards.yml` lint.exclude
#             apply to every candidate. Used by code-quality checks
#             (banned-functions, error-handling), where vendored or generated
#             code is noise.
#   --strict  Tracked files are never excluded — not by the built-in list and
#             not by lint.exclude — so a contributor cannot hide a committed
#             file from the scan by editing .standards.yml or by placing it
#             under vendor/. Built-in exclusions still drop untracked content
#             (worktrees, caches), which cannot reach CI anyway. Used by
#             no-secrets.
#   Only regular files are returned: a tracked symlink is dropped (grep would
#   otherwise follow it to a target outside the project, or block on a FIFO),
#   as is a tracked file that has been deleted from the working tree.
#
# Path safety:
#   Git and find emit NUL-delimited names, so every byte of a filename is
#   preserved up to the point where the list becomes a bash string. Bash
#   variables cannot hold NUL and the list is newline-delimited, so a filename
#   that itself contains a newline cannot be carried: such names are never
#   silently dropped — `lint_unscannable_files` returns them (after the same
#   exclusion policy) and the modules report them as findings. Everything else
#   (spaces, colons, quotes, "#") is passed to grep exactly via
#   `tr '\n' '\0' | xargs -0`.
#
# Environment:
#   LINT_FILE_LIST  Path to a NUL-delimited list of project-relative TRACKED
#                   paths. Set by `lint-standards.sh --since/--changed`; when
#                   present it replaces tracked-file enumeration (untracked
#                   files are still enumerated, and exclusions still apply).
#   LINT_MEMBER_EXCLUDE
#                   Newline-separated project-relative directory prefixes that
#                   are treated as additional lint.exclude entries. Set by
#                   `lint-standards.sh` to the monorepo members while the
#                   root's own project/language checks run, so a root that is
#                   itself a project does not re-scan (and double-report) its
#                   members' files under the root's config. Like lint.exclude
#                   it does not apply to --strict checks, and the runner never
#                   sets it for repository-wide checks.
#
# Configuration (.standards.yml):
#   lint:
#     exclude:
#       - docs/            # path prefix (file or directory), relative to root
#       - fixtures/**      # shell-style glob: * matches within a segment,
#                          # ** zero or more whole segments ("**/" may match "")
#       - "gen#tmp/"       # quote a value that contains "#"
#   Entries are matched against project-relative paths and apply to every
#   file-enumerating check except those that use --strict (no-secrets).

# shellcheck source=checksums.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/checksums.sh"

# ---------------------------------------------------------------------------
# Built-in directory exclusions.
#
# Single-segment names match a directory of that name at any depth; entries
# containing "/" match that path suffix (e.g. ".claude/worktrees" matches
# "./.claude/worktrees" and "packages/x/.claude/worktrees").
# ---------------------------------------------------------------------------
LINT_DEFAULT_EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    ".standards"
    ".standards_tmp"
    "vendor"
    "third_party"
    "dist"
    "build"
    ".build"
    "target"
    ".next"
    "__pycache__"
    ".venv"
    "venv"
    ".tox"
    "coverage"
    ".pnpm-store"
    ".wrangler"
    "DerivedData"
    ".worktrees"
    ".claude/worktrees"
    ".Codex/worktrees"
    ".workspaces"
)

# ---------------------------------------------------------------------------
# lint__in_git_repo <root>
# True when <root> is inside a git work tree.
# ---------------------------------------------------------------------------
lint__in_git_repo() {
    local root="$1"
    [ "$(git -C "$root" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]
}

# ---------------------------------------------------------------------------
# lint__glob_to_ere <glob-or-prefix>
# Converts a project-relative path prefix or shell-style glob into an ERE
# fragment. "**/" matches zero or more whole segments, a bare "**" matches
# anything, "*" matches within one segment, "?" one character. Everything
# else is escaped literally. Forward slashes only.
# ---------------------------------------------------------------------------
lint__glob_to_ere() {
    printf '%s\n' "$1" | awk '{
        s = $0
        gsub(/[][^$.|+(){}\\]/, "\\\\&", s)
        gsub(/\*\*\//, "\001", s)
        gsub(/\*\*/, "\002", s)
        gsub(/\*/, "[^/]*", s)
        gsub(/\?/, "[^/]", s)
        gsub(/\001/, "([^/]*/)*", s)
        gsub(/\002/, ".*", s)
        print s
    }'
}

# ---------------------------------------------------------------------------
# lint__default_exclude_ere
# ERE matching any path that lives under one of the built-in excluded dirs.
# ---------------------------------------------------------------------------
lint__default_exclude_ere() {
    local alts="" name esc
    for name in "${LINT_DEFAULT_EXCLUDE_DIRS[@]}"; do
        esc="${name//./\\.}"
        if [ -z "$alts" ]; then alts="$esc"; else alts="$alts|$esc"; fi
    done
    printf '(^|/)(%s)/' "$alts"
}

# ---------------------------------------------------------------------------
# lint__user_exclude_ere <root> [extra-entry ...]
# ERE built from `.standards.yml` lint.exclude plus caller-supplied entries.
# Prints nothing when there are no entries.
#
# A YAML comment starts with "#" only at the start of the value or after
# whitespace, and never inside quotes, so `"dir#name/"` and `dir#name/` are
# kept whole while `docs/  # wireframes` loses its trailing comment.
# ---------------------------------------------------------------------------
lint__user_exclude_ere() {
    local root="$1"
    shift || true
    local entries="" line
    if [ -f "$root/.standards.yml" ]; then
        entries=$(yaml_nested_list "lint" "exclude" "$root/.standards.yml")
    fi
    local alts="" frag
    while IFS= read -r line; do
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$line" in
            \"*) line="${line#\"}"; line="${line%%\"*}" ;;
            \'*) line="${line#\'}"; line="${line%%\'*}" ;;
            \#*) line="" ;;
            *)   line=$(printf '%s' "$line" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
        esac
        line="${line#./}"
        line="${line%/}"
        [ -z "$line" ] && continue
        frag=$(lint__glob_to_ere "$line")
        if [ -z "$alts" ]; then alts="$frag"; else alts="$alts|$frag"; fi
    done <<EOF
$entries
$(printf '%s\n' "$@")
${LINT_MEMBER_EXCLUDE:-}
EOF
    [ -n "$alts" ] && printf '^(%s)(/|$)' "$alts"
    return 0
}

# ---------------------------------------------------------------------------
# Raw, NUL-delimited enumeration (project-relative paths).
# ---------------------------------------------------------------------------

# lint__raw_tracked <root>: tracked files, or the runner's --since/--changed
# list when one was exported. Empty outside a git repo.
lint__raw_tracked() {
    local root="$1"
    if [ -n "${LINT_FILE_LIST:-}" ] && [ -r "$LINT_FILE_LIST" ]; then
        cat "$LINT_FILE_LIST"
    elif lint__in_git_repo "$root"; then
        git -C "$root" ls-files -z 2>/dev/null
    fi
    return 0
}

# lint__raw_untracked <root>: untracked-but-not-ignored files in a git repo;
# a pruned find (never descends into excluded dirs) elsewhere.
lint__raw_untracked() {
    local root="$1"
    if lint__in_git_repo "$root"; then
        git -C "$root" ls-files -z -o --exclude-standard 2>/dev/null
    else
        local prune=() name
        for name in "${LINT_DEFAULT_EXCLUDE_DIRS[@]}"; do
            case "$name" in
                */*) prune+=(-o -path "*/$name") ;;
                *)   prune+=(-o -name "$name") ;;
            esac
        done
        # ${prune[@]:1} drops the leading "-o". Strip "<root>/" from each
        # NUL-terminated entry without touching any other byte.
        find "$root" -mindepth 1 \( "${prune[@]:1}" \) -prune -o -type f -print0 2>/dev/null \
            | lint__strip_prefix_nul "$root/"
    fi
    return 0
}

# lint__strip_prefix_nul <prefix>: stdin NUL-delimited → stdout NUL-delimited
# with <prefix> removed from the start of each entry.
lint__strip_prefix_nul() {
    local prefix="$1" entry
    while IFS= read -r -d '' entry || [ -n "$entry" ]; do
        printf '%s\0' "${entry#"$prefix"}"
        entry=""
    done
}

# ---------------------------------------------------------------------------
# lint__nul_to_lines [badfile]
#
# stdin: NUL-delimited names. stdout: one name per line, for every name that
# contains no newline. Names that do contain a newline cannot be represented
# in a newline-delimited list; each is appended to <badfile> (newline shown as
# "\n") when given, and never printed. The common case (no such name) is a
# single `tr`; the per-entry loop only runs when the counts disagree.
# ---------------------------------------------------------------------------
lint__nul_to_lines() {
    local bad="${1:-}" tmp entries lines
    tmp=$(mktemp "${TMPDIR:-/tmp}/lint-nul.XXXXXX")
    cat > "$tmp"
    entries=$(tr -cd '\0' < "$tmp" | wc -c | tr -d ' ')
    lines=$(tr '\0' '\n' < "$tmp" | wc -l | tr -d ' ')
    if [ "$entries" -eq "$lines" ]; then
        tr '\0' '\n' < "$tmp"
    else
        local f
        while IFS= read -r -d '' f || [ -n "$f" ]; do
            case "$f" in
                *$'\n'*) [ -n "$bad" ] && printf '%s\n' "${f//$'\n'/\\n}" >> "$bad" ;;
                *)       printf '%s\n' "$f" ;;
            esac
            f=""
        done < "$tmp"
    fi
    rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# lint__apply_policy <strict true|false> <tracked|untracked> <default-ere> <user-ere>
#
# stdin → stdout filter implementing the exclusion policy from the header:
# built-in exclusions always apply to untracked content and, unless strict, to
# tracked content; lint.exclude / per-check entries apply unless strict.
# ---------------------------------------------------------------------------
lint__apply_policy() {
    local strict="$1" kind="$2" default_ere="$3" user_ere="$4" out
    out=$(cat)
    [ -z "$out" ] && return 0
    if [ "$kind" = "untracked" ] || [ "$strict" = false ]; then
        out=$(printf '%s\n' "$out" | lint__drop_matching "$default_ere")
    fi
    if [ "$strict" = false ] && [ -n "$user_ere" ] && [ -n "$out" ]; then
        out=$(printf '%s\n' "$out" | lint__drop_matching "$user_ere")
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
}

# lint__drop_matching <ere>: stdin → stdout without the lines matching <ere>.
# grep exits 1 when every line was dropped (a legitimate empty result) and 2
# when the pattern itself is invalid; the latter must never be mistaken for
# "nothing to scan", so the input is passed through unfiltered with a note on
# stderr — scanning too much is the safe failure.
lint__drop_matching() {
    local ere="$1" input out rc
    input=$(cat)
    out=$(printf '%s\n' "$input" | grep -vE -- "$ere" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "lint-files: invalid exclusion pattern ignored: $ere" >&2
        printf '%s\n' "$input"
        return 0
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
}

# ---------------------------------------------------------------------------
# lint__regular_files_only <root>
#
# stdin: project-relative paths, one per line. stdout: the same paths prefixed
# with "<root>/", keeping only regular files. `find -maxdepth 0 -type f` on
# the paths themselves never follows a symlink, so a tracked link (to a file
# outside the project, or to a FIFO that would block grep) is dropped, as is a
# tracked path that no longer exists in the working tree.
# ---------------------------------------------------------------------------
lint__regular_files_only() {
    local root="$1"
    # find needs its paths before the expression, and xargs appends them at the
    # end, so a tiny sh wrapper puts each batch in front.
    awk -v r="$root/" '{ print r $0 }' \
        | tr '\n' '\0' \
        | xargs -0 sh -c 'find "$@" -maxdepth 0 -type f -print0 2>/dev/null' _ \
        | lint__nul_to_lines
}

# ---------------------------------------------------------------------------
# lint_list_files [--strict] <root> [extra-exclude ...]
#
# Prints candidate files (one per line, prefixed with <root>/) for a check to
# scan: tracked + untracked-not-ignored files in a git repo, or a pruned find
# otherwise, minus the exclusions described in the header. With --strict,
# tracked files bypass every exclusion and lint.exclude is ignored entirely.
# ---------------------------------------------------------------------------
lint_list_files() {
    local strict=false
    if [ "${1:-}" = "--strict" ]; then
        strict=true
        shift
    fi
    local root="${1:-.}"
    shift || true

    local default_ere user_ere="" tracked untracked rel_list
    default_ere=$(lint__default_exclude_ere)
    if [ "$strict" = false ]; then
        user_ere=$(lint__user_exclude_ere "$root" "$@")
    fi
    tracked=$(lint__raw_tracked "$root" | lint__nul_to_lines \
        | lint__apply_policy "$strict" tracked "$default_ere" "$user_ere")
    untracked=$(lint__raw_untracked "$root" | lint__nul_to_lines \
        | lint__apply_policy "$strict" untracked "$default_ere" "$user_ere")

    rel_list=$(printf '%s\n%s\n' "$tracked" "$untracked" | grep -v '^$' | sort -u)
    [ -z "$rel_list" ] && return 0

    printf '%s\n' "$rel_list" | lint__regular_files_only "$root"
}

# ---------------------------------------------------------------------------
# lint_unscannable_files [--strict] <root> [extra-exclude ...]
#
# Prints, one per line with embedded newlines shown as "\n", every candidate
# filename that lint_list_files could not carry because it contains a newline
# — after the same exclusion policy, so a name under an excluded path is not
# reported. Modules report these so a file is never skipped silently.
# ---------------------------------------------------------------------------
lint_unscannable_files() {
    local strict=false
    if [ "${1:-}" = "--strict" ]; then
        strict=true
        shift
    fi
    local root="${1:-.}"
    shift || true

    local default_ere user_ere="" tbad ubad tracked untracked
    default_ere=$(lint__default_exclude_ere)
    if [ "$strict" = false ]; then
        user_ere=$(lint__user_exclude_ere "$root" "$@")
    fi
    tbad=$(mktemp "${TMPDIR:-/tmp}/lint-bad.XXXXXX")
    ubad=$(mktemp "${TMPDIR:-/tmp}/lint-bad.XXXXXX")
    lint__raw_tracked "$root" | lint__nul_to_lines "$tbad" >/dev/null
    lint__raw_untracked "$root" | lint__nul_to_lines "$ubad" >/dev/null
    tracked=$(lint__apply_policy "$strict" tracked "$default_ere" "$user_ere" < "$tbad")
    untracked=$(lint__apply_policy "$strict" untracked "$default_ere" "$user_ere" < "$ubad")
    rm -f "$tbad" "$ubad"
    printf '%s\n%s\n' "$tracked" "$untracked" | grep -v '^$' | sort -u
    return 0
}

# ---------------------------------------------------------------------------
# lint_grep_files <newline-separated files> <grep args...>
#
# Runs grep over the file list in batches (xargs -0), skipping binaries.
# Handles paths with spaces. Never fails the caller: no match prints nothing.
# ---------------------------------------------------------------------------
lint_grep_files() {
    local files="$1"
    shift
    [ -z "$files" ] && return 0
    printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -I "$@" -- 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# lint_grep_hits <newline-separated files> <root> <comment-ere> <pattern>
#
# Prints "<project-relative path>:<line>:<content>" for every line matching
# <pattern> (ERE) whose content does not start with <comment-ere> (e.g. "#" or
# "//|\*"). Two stages keep the parsing unambiguous however odd the filename:
#   1. one batched `grep -l --null` finds the files that match at all;
#   2. each of those (normally a handful) is grepped on its own with -n, so
#      the output is "<line>:<content>" with no filename to confuse the
#      suppression anchor (`^[0-9]+:`), and the path is prefixed afterwards.
# Empty <comment-ere> disables suppression. Never fails the caller.
# ---------------------------------------------------------------------------
lint_grep_hits() {
    local files="$1" root="$2" comment_ere="$3" pattern="$4"
    [ -z "$files" ] && return 0
    local f rel line
    while IFS= read -r -d '' f || [ -n "$f" ]; do
        rel="${f#"$root/"}"
        grep -InE -- "$pattern" "$f" 2>/dev/null \
            | { if [ -n "$comment_ere" ]; then grep -vE "^[0-9]+:[[:space:]]*($comment_ere)"; else cat; fi; } \
            | head -5 \
            | while IFS= read -r line; do printf '%s:%s\n' "$rel" "$line"; done
        f=""
    done < <(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -IlE --null -- "$pattern" 2>/dev/null || true)
    return 0
}

# ---------------------------------------------------------------------------
# lint_strip_root <root>
# Filter: removes the leading "<root>/" from each stdin line so messages show
# project-relative paths.
# ---------------------------------------------------------------------------
lint_strip_root() {
    awk -v r="$1/" 'index($0, r) == 1 { print substr($0, length(r) + 1); next } { print }'
}

# ---------------------------------------------------------------------------
# lint_scope_is_changed
# True when the runner restricted the scan to changed files (--since/--changed).
# ---------------------------------------------------------------------------
lint_scope_is_changed() {
    [ -n "${LINT_FILE_LIST:-}" ] && [ -r "$LINT_FILE_LIST" ]
}
