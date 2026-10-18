#!/bin/bash
# scripts/worktree-gc.sh — remove finished agent worktrees and report the rest
# (proc-04 § Worktree Hygiene, #190).
#
# Usage:
#   ./scripts/worktree-gc.sh [--dry-run] [--max-age <days>] [--keep-dirty]
#                            [--no-fetch] [--base <ref>] [project-root]
#   make worktree-gc
#
# Run with --help for the option reference. bash 3.2 compatible.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/worktrees.sh disable=SC1091
source "$SCRIPT_DIR/lib/worktrees.sh"

usage() {
    cat <<EOF
Usage: $0 [options] [project-root]

Remove the linked worktrees of a repository that are finished, delete their
merged branches, prune stale registrations and report what remains with its
idle age and size. The main checkout and the worktree you run it from are
never touched.

A worktree is removed when it is
  merged     its HEAD is contained in the base branch (origin/main by default)
  gone       its branch tracks an upstream that was deleted (PR merged, remote
             branch removed) — the local branch is deleted too
  idle       nothing was committed or checked out in it for more than
             --max-age days (default ${WORKTREE_TTL_DAYS_DEFAULT}); its branch is KEPT, since the work
             is not merged
  prunable   its directory is already gone; only the registration remains
Uncommitted changes in a removed worktree are a warning, not a blocker
(pass --keep-dirty to leave such worktrees alone). Locked worktrees are
skipped. Directories under the worktree root that are not registered
worktrees are reported, never deleted.

Options:
  --dry-run            Print what would be removed; change nothing
  --max-age <days>     Idle threshold in days (default ${WORKTREE_TTL_DAYS_DEFAULT})
  --keep-dirty         Never remove a worktree with uncommitted changes
  --no-fetch           Do not 'git fetch --prune origin' first (merged/gone are
                       then judged from the local refs)
  --base <ref>         Branch to judge "merged" against (default: origin/main,
                       origin/master, main or master, whichever exists)
  -h, --help           Show this help and exit

The worktree root is 'worktree_dir:' in .standards.yml (default ${WORKTREE_DIR_DEFAULT}).
Exit 0 on success, 1 when a removal failed or the directory is not a git
repository, 2 on a usage error.
EOF
}

usage_error() {
    echo "$1" >&2
    usage >&2
    exit 2
}

require_option_value() {
    if [ $# -lt 2 ] || [ -z "$2" ]; then
        usage_error "Option $1 requires a value"
    fi
    case "$2" in
        -*) usage_error "Option $1 requires a value (got '$2')" ;;
    esac
}

DRY_RUN=false
MAX_AGE="$WORKTREE_TTL_DAYS_DEFAULT"
KEEP_DIRTY=false
DO_FETCH=true
BASE_OVERRIDE=""
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)    DRY_RUN=true; shift ;;
        --keep-dirty) KEEP_DIRTY=true; shift ;;
        --no-fetch)   DO_FETCH=false; shift ;;
        --max-age)    require_option_value "$@"; MAX_AGE="$2"; shift 2 ;;
        --max-age=*)  require_option_value "--max-age" "${1#--max-age=}"; MAX_AGE="${1#--max-age=}"; shift ;;
        --base)       require_option_value "$@"; BASE_OVERRIDE="$2"; shift 2 ;;
        --base=*)     require_option_value "--base" "${1#--base=}"; BASE_OVERRIDE="${1#--base=}"; shift ;;
        -h|--help)    usage; exit 0 ;;
        -*)           usage_error "Unknown option: $1" ;;
        *)
            [ -z "$TARGET" ] || usage_error "Unexpected argument: $1"
            TARGET="$1"; shift ;;
    esac
done

case "$MAX_AGE" in
    ''|*[!0-9]*) usage_error "--max-age expects a whole number of days (got '$MAX_AGE')" ;;
esac

TARGET="${TARGET:-.}"
if [ ! -d "$TARGET" ]; then
    echo "❌ $TARGET: no such directory" >&2
    exit 1
fi
if [ "$(git -C "$TARGET" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    echo "❌ $TARGET is not inside a git repository" >&2
    exit 1
fi

# The worktree the command targets (its cwd or the given root) is never removed:
# deleting the directory a shell is running in leaves the caller stranded.
CURRENT=$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)
MAIN=$(worktree_main_path "$TARGET")
if [ -z "$MAIN" ]; then
    echo "❌ could not list the worktrees of $TARGET" >&2
    exit 1
fi

WT_ROOT=$(worktree_root_dir "$MAIN")
WT_ROOT_PROBLEM=$(worktree_dir_problem "$MAIN")
if [ -n "$WT_ROOT_PROBLEM" ]; then
    echo "⚠️  worktree_dir: '$WT_ROOT_PROBLEM' in .standards.yml is not a relative path inside the project; using $WORKTREE_DIR_DEFAULT"
fi

if [ "$DO_FETCH" = true ] && git -C "$MAIN" remote get-url origin >/dev/null 2>&1; then
    if ! git -C "$MAIN" fetch --prune --quiet origin 2>/dev/null; then
        echo "⚠️  git fetch --prune origin failed; merged/gone are judged from the local refs"
    fi
fi

BASE="$BASE_OVERRIDE"
if [ -z "$BASE" ]; then
    BASE=$(worktree_base_ref "$MAIN" 2>/dev/null) || BASE=""
elif ! git -C "$MAIN" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
    echo "⚠️  --base $BASE is not a known ref; 'merged' cannot be judged"
    BASE=""
fi

if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN — showing what worktree-gc would do (no files modified)"
fi
echo "🧹 Worktree GC — $MAIN"
echo "   worktree root: $WT_ROOT   base: ${BASE:-(none)}   max idle age: ${MAX_AGE}d"
echo ""

# rel_path <absolute path> → path relative to the main checkout when below it.
rel_path() {
    case "$1" in
        "$MAIN"/*) printf '%s\n' "${1#"$MAIN"/}" ;;
        *)         printf '%s\n' "$1" ;;
    esac
}

ALL=$(worktree_list "$MAIN")
LINKED=$(printf '%s\n' "$ALL" | tail -n +2)
LINKED_PATHS=$(printf '%s\n' "$LINKED" | cut -f1)

if [ -z "$(printf '%s' "$LINKED" | tr -d '[:space:]')" ]; then
    echo "✅ No linked worktrees (main checkout only)."
fi

removed=0 kept=0 failed=0 reclaimed_kb=0 branches_deleted=0 warnings=0
report_line() {
    # report_line <verb> <rel> <branch> <reason> <age> <size>
    printf '  %-12s %-40s %-28s %-30s %4sd %8s\n' "$1" "$2" "$3" "$4" "$5" "$6"
}

while IFS=$'\t' read -r path branch state; do
    [ -n "$path" ] || continue
    rel=$(rel_path "$path")
    age=$(worktree_age_days "$path")
    size_kb=$(dir_size_kb "$path")
    size=$(human_kb "$size_kb")
    note=""

    enclosing=$(worktree_nested_in "$path" "$LINKED_PATHS") || enclosing=""
    if [ -n "$enclosing" ]; then
        echo "  ⚠️  nested: $rel was created inside $(rel_path "$enclosing") — create worktrees from the main checkout only"
        warnings=$((warnings + 1))
    fi
    if [ "$rel" != "$path" ] && ! worktree_under_root "$rel" "$WT_ROOT"; then
        note=" (outside $WT_ROOT)"
    fi

    action=keep
    reason=active
    delete_branch=false
    if [ "$state" = "prunable" ]; then
        action=prune
        reason="prunable (directory gone)"
    elif [ "$state" = "locked" ]; then
        reason="locked"
    elif [ "$path" = "$CURRENT" ]; then
        reason="current worktree"
    elif [ "$branch" != "(detached)" ] && [ -n "$BASE" ] \
         && git -C "$MAIN" merge-base --is-ancestor "refs/heads/$branch" "$BASE" 2>/dev/null; then
        action=remove
        reason="merged into $BASE"
        delete_branch=true
    elif [ "$branch" != "(detached)" ] && worktree_branch_gone "$MAIN" "$branch"; then
        action=remove
        reason="upstream gone"
        delete_branch=true
    elif [ "$age" -gt "$MAX_AGE" ]; then
        action=remove
        reason="idle ${age}d > ${MAX_AGE}d"
    fi

    dirty=false
    if [ "$action" = "remove" ] && [ -d "$path" ]; then
        if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
            dirty=true
        fi
    fi
    if [ "$dirty" = true ] && [ "$KEEP_DIRTY" = true ]; then
        action=keep
        reason="dirty (--keep-dirty)"
        delete_branch=false
    fi

    case "$action" in
        keep)
            report_line "✅ keep" "$rel$note" "$branch" "$reason" "$age" "$size"
            kept=$((kept + 1))
            ;;
        prune)
            if [ "$DRY_RUN" = true ]; then
                report_line "Would prune" "$rel$note" "$branch" "$reason" "$age" "-"
            else
                report_line "✂️  prune" "$rel$note" "$branch" "$reason" "$age" "-"
            fi
            ;;
        remove)
            if [ "$dirty" = true ]; then
                echo "  ⚠️  uncommitted changes in $rel will be discarded (git status is not clean)"
                warnings=$((warnings + 1))
            fi
            if [ "$DRY_RUN" = true ]; then
                report_line "Would remove" "$rel$note" "$branch" "$reason" "$age" "$size"
                if [ "$delete_branch" = true ]; then
                    echo "               would delete branch $branch"
                elif [ "$branch" != "(detached)" ]; then
                    echo "               branch kept: $branch (not merged)"
                fi
            elif git -C "$MAIN" worktree remove --force "$path" 2>/dev/null; then
                report_line "✂️  removed" "$rel$note" "$branch" "$reason" "$age" "$size"
                removed=$((removed + 1))
                reclaimed_kb=$((reclaimed_kb + size_kb))
                if [ "$delete_branch" = true ]; then
                    if git -C "$MAIN" branch -D "$branch" >/dev/null 2>&1; then
                        echo "               deleted branch $branch"
                        branches_deleted=$((branches_deleted + 1))
                    else
                        echo "  ⚠️  could not delete branch $branch (checked out elsewhere?)"
                        warnings=$((warnings + 1))
                    fi
                elif [ "$branch" != "(detached)" ]; then
                    echo "               branch kept: $branch (not merged)"
                fi
            else
                report_line "❌ failed" "$rel$note" "$branch" "$reason" "$age" "$size"
                failed=$((failed + 1))
            fi
            ;;
    esac
done <<EOF
$LINKED
EOF

# Registrations whose directories are gone (and anything removed above).
if [ "$DRY_RUN" = false ]; then
    git -C "$MAIN" worktree prune 2>/dev/null || true
fi

# Directories under the worktree root that git does not know about: leftovers
# of a `rm -rf` or a lost .git/worktrees entry. Reported with their size; the
# collector never deletes what it cannot attribute to a branch.
if [ -d "$MAIN/$WT_ROOT" ]; then
    for d in "$MAIN/$WT_ROOT"/*/; do
        d="${d%/}"
        [ -d "$d" ] || continue
        registered=false
        while IFS= read -r p; do
            [ "$p" = "$d" ] && { registered=true; break; }
        done <<EOF
$LINKED_PATHS
EOF
        [ "$registered" = true ] && continue
        echo "  ⚠️  $(rel_path "$d") is not a registered worktree ($(human_kb "$(dir_size_kb "$d")")) — remove it by hand: rm -rf $(rel_path "$d")"
        warnings=$((warnings + 1))
    done
fi

echo ""
if [ "$DRY_RUN" = true ]; then
    echo "Summary (dry run): nothing changed; $kept worktree(s) would be kept."
else
    echo "Summary: removed $removed worktree(s), $(human_kb "$reclaimed_kb") reclaimed, $branches_deleted branch(es) deleted, $kept kept, $warnings warning(s)."
fi
remaining=$(worktree_list "$MAIN" | tail -n +2 | grep -c . || true)
echo "Linked worktrees remaining: $remaining"

[ "$failed" -eq 0 ] || exit 1
exit 0
