#!/bin/bash
# scripts/lib/worktrees.sh — worktree root, listing, age and size helpers
# shared by worktree-gc.sh, doctor.sh, setup.sh, members.sh and lint-files.sh
# (proc-04 § Worktree Hygiene, #190).
#
# Source this file; do not execute it directly. bash 3.2 compatible.
#
#   worktree_root_dir <project_root>   → the configured worktree root
#                                         (`worktree_dir:` in .standards.yml,
#                                         default .claude/worktrees), validated
#   worktree_list <project_root>       → "<path>\t<branch>\t<state>" per worktree,
#                                         main checkout first
#   worktree_last_active <path>        → epoch seconds of the last activity
#   worktree_age_days <path>           → idle days (integer)
#   dir_size_kb <path> / human_kb <kb> → sizes
#   worktree_nested_in <path> <paths>  → the linked worktree <path> lies inside

WORKTREE_DIR_DEFAULT=".claude/worktrees"
WORKTREE_TTL_DAYS_DEFAULT=14
# Roots that agents create on their own; the pre-commit guard refuses all of
# them in addition to the configured root, and doctor reports worktrees found
# under one of them as outside the root (#194 will unify the agent text).
WORKTREE_KNOWN_ROOTS=".claude/worktrees .worktrees .Codex/worktrees .codex/worktrees .cursor/worktrees .workspaces"

# yaml_block_scalar lives in checksums.sh; load it when the caller has not.
if ! declare -f yaml_block_scalar >/dev/null 2>&1; then
    # shellcheck source=checksums.sh
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/checksums.sh"
fi

# worktree_dir_normalize <value>
#
# Prints the normalized project-relative form of a declared worktree root
# ("./" and trailing slashes stripped, repeated slashes collapsed). Returns 1,
# printing nothing, when the value is empty, absolute, home-relative, or
# escapes the project through ".." — a worktree root must stay inside the
# checkout so .gitignore can cover it and the guard can match it.
worktree_dir_normalize() {
    local p="$1"
    p=$(printf '%s' "$p" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$p" in
        \"*) p="${p#\"}"; p="${p%%\"*}" ;;
        \'*) p="${p#\'}"; p="${p%%\'*}" ;;
        *)   p=$(printf '%s' "$p" | sed 's/[[:space:]]#.*$//; s/[[:space:]]*$//') ;;
    esac
    [ -n "$p" ] || return 1
    case "$p" in
        /*|~*|*\\*) return 1 ;;
    esac
    p=$(printf '%s' "$p" | sed 's#//*#/#g; s#^\./##; s#/\./#/#g; s#/\.$##; s#/$##')
    [ -n "$p" ] || return 1
    [ "$p" = "." ] && return 1
    local rest="$p" seg
    while [ -n "$rest" ]; do
        seg="${rest%%/*}"
        if [ "$seg" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        [ "$seg" = ".." ] && return 1
    done
    printf '%s\n' "$p"
}

# worktree__read_dir <project_root>
#
# Prints "<status>\t<value>" for the declared worktree root:
#   default  <default>      no `worktree_dir:` key
#   ok       <normalized>   declared and valid
#   invalid  <raw value>    declared but rejected ("(empty)" for a bare key)
worktree__read_dir() {
    local yml="$1/.standards.yml" raw="" norm
    if [ ! -f "$yml" ] || ! grep -q '^worktree_dir:' "$yml" 2>/dev/null; then
        printf 'default\t%s\n' "$WORKTREE_DIR_DEFAULT"
        return 0
    fi
    raw=$(yaml_block_scalar "worktree_dir" "$yml" | head -1)
    if [ -z "$raw" ]; then
        printf 'invalid\t(empty)\n'
    elif norm=$(worktree_dir_normalize "$raw"); then
        printf 'ok\t%s\n' "$norm"
    else
        printf 'invalid\t%s\n' "$raw"
    fi
}

# worktree_root_dir <project_root>
#
# Prints the project-relative worktree root: `worktree_dir:` from the root
# .standards.yml when declared and valid, else the default (also when the
# declared value is invalid — see worktree_dir_problem).
worktree_root_dir() {
    local status value
    IFS=$'\t' read -r status value <<EOF
$(worktree__read_dir "$1")
EOF
    case "$status" in
        ok) printf '%s\n' "$value" ;;
        *)  printf '%s\n' "$WORKTREE_DIR_DEFAULT" ;;
    esac
}

# worktree_dir_problem <project_root>
#
# Prints the raw `worktree_dir:` value when it is declared but not a relative
# path inside the project ("(empty)" for a bare key); prints nothing when the
# key is absent or valid. Callers warn and fall back to the default.
worktree_dir_problem() {
    local status value
    IFS=$'\t' read -r status value <<EOF
$(worktree__read_dir "$1")
EOF
    [ "$status" = "invalid" ] && printf '%s\n' "$value"
    return 0
}

# worktree_under_root <project-relative path> <root>
# True when <path> is <root> itself or lies below it.
worktree_under_root() {
    local p="$1" r="$2"
    [ -n "$r" ] || return 1
    [ "$p" = "$r" ] && return 0
    case "$p" in
        "$r"/*) return 0 ;;
    esac
    return 1
}

# worktree_root_ignored <.gitignore path> <root>
#
# True when the .gitignore file itself lists the worktree root (with or
# without a leading or trailing slash) or one of its parent directories. The
# file is read rather than `git check-ignore` asked, so a root ignored only by
# a global or per-clone exclude still gets the entry every clone needs.
worktree_root_ignored() {
    local file="$1" root="$2" cand
    [ -f "$file" ] || return 1
    cand="$root"
    while [ -n "$cand" ]; do
        if grep -qxF -e "$cand" -e "$cand/" -e "/$cand" -e "/$cand/" "$file" 2>/dev/null; then
            return 0
        fi
        case "$cand" in
            */*) cand="${cand%/*}" ;;
            *)   cand="" ;;
        esac
    done
    return 1
}

# worktree_list <project_root>
#
# One line per worktree of the repository that contains <project_root>:
#   <absolute path> TAB <branch or (detached)> TAB <state>
# where state is ok, locked or prunable (registration whose directory is
# gone). The main checkout is the first line, as `git worktree list` orders
# it. Prints nothing outside a git repository.
worktree_list() {
    local root="$1"
    git -C "$root" worktree list --porcelain 2>/dev/null | awk '
        function emit() {
            if (path == "") return
            printf "%s\t%s\t%s\n", path, (branch == "" ? "(detached)" : branch), state
        }
        /^worktree / { emit(); path = substr($0, 10); branch = ""; state = "ok"; next }
        /^branch /   { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch); next }
        /^detached/  { branch = "(detached)"; next }
        /^locked/    { state = "locked"; next }
        /^prunable/  { state = "prunable"; next }
        END { emit() }
    '
}

# worktree_main_path <project_root> → absolute path of the main checkout.
worktree_main_path() {
    worktree_list "$1" | head -1 | cut -f1
}

# file_mtime <path> → modification time in epoch seconds (GNU or BSD stat), 0
# when the path does not exist.
file_mtime() {
    [ -e "$1" ] || { echo 0; return 0; }
    if stat -c %Y / >/dev/null 2>&1; then
        stat -c %Y "$1" 2>/dev/null || echo 0
    else
        stat -f %m "$1" 2>/dev/null || echo 0
    fi
}

# worktree_last_active <worktree path>
#
# Epoch seconds of the most recent sign of life in a linked worktree: the
# last commit on its HEAD, or the last checkout/index write (HEAD, index and
# the HEAD reflog in its private git dir), or a change to the directory
# itself. A registration whose directory is gone reports its git-dir times.
worktree_last_active() {
    local wt="$1" gitdir="" best=0 t f
    if [ -d "$wt" ]; then
        gitdir=$(git -C "$wt" rev-parse --git-dir 2>/dev/null)
        case "$gitdir" in
            "") ;;
            /*) ;;
            *) gitdir="$wt/$gitdir" ;;
        esac
        t=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo 0)
        [ -n "$t" ] && [ "$t" -gt "$best" ] 2>/dev/null && best=$t
        t=$(file_mtime "$wt")
        [ "$t" -gt "$best" ] 2>/dev/null && best=$t
    fi
    if [ -n "$gitdir" ] && [ -d "$gitdir" ]; then
        for f in HEAD index logs/HEAD; do
            t=$(file_mtime "$gitdir/$f")
            [ "$t" -gt "$best" ] 2>/dev/null && best=$t
        done
    fi
    echo "$best"
}

# worktree_age_days <worktree path> → whole days since worktree_last_active;
# 0 when nothing could be measured (so an unmeasurable worktree is never
# treated as stale).
worktree_age_days() {
    local last now
    last=$(worktree_last_active "$1")
    [ "$last" -gt 0 ] 2>/dev/null || { echo 0; return 0; }
    now=$(date +%s)
    echo $(( (now - last) / 86400 ))
}

# dir_size_kb <path> → disk usage in KiB (0 when missing).
dir_size_kb() {
    [ -d "$1" ] || { echo 0; return 0; }
    du -sk "$1" 2>/dev/null | awk '{ print $1 + 0 }'
}

# human_kb <kib> → "512K", "3.2M", "1.1G".
human_kb() {
    awk -v k="${1:-0}" 'BEGIN {
        if (k < 1024) printf "%dK\n", k
        else if (k < 1048576) printf "%.1fM\n", k / 1024
        else printf "%.1fG\n", k / 1048576
    }'
}

# worktree_nested_in <path> <newline-separated linked worktree paths>
#
# Prints the first linked worktree whose directory encloses <path>, i.e. a
# worktree created from inside another worktree (`.claude/worktrees/a/.claude/
# worktrees/b`). Prints nothing when <path> is not nested. The main checkout
# must not be in the list: every linked worktree normally lives below it.
worktree_nested_in() {
    local p="$1" others="$2" q
    while IFS= read -r q; do
        [ -n "$q" ] || continue
        [ "$q" = "$p" ] && continue
        case "$p" in
            "$q"/*) printf '%s\n' "$q"; return 0 ;;
        esac
    done <<EOF
$others
EOF
    return 1
}

# worktree_encloses <path> <newline-separated linked worktree paths>
#
# Prints the linked worktrees whose directories lie inside <path>, one per
# line (the inverse of worktree_nested_in). A worktree that encloses another
# must never be removed with --force: that would delete the child's files
# before the child is looked at. Returns 1, printing nothing, when none does.
worktree_encloses() {
    local p="$1" others="$2" q found=1
    while IFS= read -r q; do
        [ -n "$q" ] || continue
        [ "$q" = "$p" ] && continue
        case "$q" in
            "$p"/*) printf '%s\n' "$q"; found=0 ;;
        esac
    done <<EOF
$others
EOF
    return $found
}

# worktree_base_ref <project_root> → the integration branch to judge
# "merged" against: origin/main, origin/master, main or master, whichever
# exists first; empty when none does.
worktree_base_ref() {
    local root="$1" ref
    for ref in origin/main origin/master main master; do
        if git -C "$root" rev-parse --verify --quiet "refs/remotes/$ref" >/dev/null 2>&1 \
           || git -C "$root" rev-parse --verify --quiet "refs/heads/$ref" >/dev/null 2>&1; then
            printf '%s\n' "$ref"
            return 0
        fi
    done
    return 1
}

# worktree_branch_gone <project_root> <branch> → true when the branch tracks
# an upstream that no longer exists (deleted on the remote after its PR merged).
worktree_branch_gone() {
    local root="$1" branch="$2" track
    track=$(git -C "$root" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)
    [ "$track" = "[gone]" ]
}
