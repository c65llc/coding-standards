#!/bin/bash
# Emit the agent-neutral skills (standards/skills/*.md) in each declared
# agent's own shape (proc-04, #194).
#
# Usage:
#   assemble-skills.sh [--project-root <dir>] [--skills-dir <dir>] [--dry-run]
#                      [--quiet] <agent> [<agent> ...]
#
# Per agent:
#   claude-code  .claude/skills/<name>/SKILL.md      (frontmatter kept)
#   cursor       .cursor/commands/<name>.md          (description frontmatter)
#   copilot      .github/prompts/<name>.prompt.md    (description frontmatter)
#   codex, gemini, aider — nothing is written here: their assembled config
#                carries a "## Skills" index (see assemble-config.sh).
#
# Options:
#   --project-root <dir>  Consumer project root (default: git toplevel, else pwd).
#   --skills-dir <dir>    Source directory (default: ../standards/skills next
#                         to this script).
#   --dry-run             Print every write that would happen; modify nothing.
#   --quiet               Print only the per-agent summary and any warnings.
#   -h, --help            Show this help.
#
# A skill is installed as written: no template variables are resolved, so the
# installed runbook is the same text the single-file agents read from
# standards/skills/ (a skill that mentions `{{WORKTREE_DIR}}` means the literal
# placeholder). A file is rewritten only when its rendered content differs from
# what is installed, so a repeated run is a no-op.
#
# Installed skill files are recorded in .standards-checksums under their
# project-relative path, like the assembled configs. A destination that differs
# and is not recorded as standards-owned (a pre-existing project file), or whose
# recorded hash no longer matches (edited since it was installed), is never
# replaced: the new version is staged to .standards-pending/<path> for review.
#
# Exit codes: 0 success (staged files included), 1 a write failed, 2 usage error.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

PROJECT_ROOT=""
SKILLS_DIR="$SCRIPT_DIR/../standards/skills"
DRY_RUN=false
QUIET=false
AGENTS=""

while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)
            [ $# -ge 2 ] || { echo "ERROR: --project-root requires a directory" >&2; exit 2; }
            PROJECT_ROOT="$2"; shift 2 ;;
        --skills-dir)
            [ $# -ge 2 ] || { echo "ERROR: --skills-dir requires a directory" >&2; exit 2; }
            SKILLS_DIR="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --quiet)   QUIET=true; shift ;;
        -h|--help) usage; exit 0 ;;
        -*)        echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)         AGENTS="${AGENTS:+$AGENTS }$1"; shift ;;
    esac
done

if [ -z "$AGENTS" ]; then
    echo "ERROR: at least one agent is required" >&2
    usage >&2
    exit 2
fi

# shellcheck source=lib/skills.sh disable=SC1091
source "$SCRIPT_DIR/lib/skills.sh"

for agent in $AGENTS; do
    if ! skills_agent_known "$agent"; then
        echo "ERROR: Unknown agent: $agent (expected one of: $SKILLS_FILE_AGENTS $SKILLS_INDEX_AGENTS)" >&2
        exit 2
    fi
done

if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if [ ! -d "$SKILLS_DIR" ]; then
    echo "WARNING: skills directory not found: $SKILLS_DIR — nothing to install" >&2
    exit 0
fi
SKILLS_DIR="$(cd "$SKILLS_DIR" && pwd)"

# Ownership guard: read_stored_hash, update_checksum_entry and the
# CHECKSUMS_FILE / PENDING_DIR names come from lib/checksums.sh; the hash is
# skill_file_hash (whole file — see lib/skills.sh). Without the library every
# differing destination counts as not ours and is staged.
HAVE_CHECKSUMS=false
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck source=lib/checksums.sh disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
    HAVE_CHECKSUMS=true
fi
CHECKSUMS_PATH="$PROJECT_ROOT/${CHECKSUMS_FILE:-.standards-checksums}"
PENDING_ROOT="$PROJECT_ROOT/${PENDING_DIR:-.standards-pending}"
CHECKSUMS_CONTENT=""
CHECKSUMS_DIRTY=false
if [ -f "$CHECKSUMS_PATH" ]; then
    CHECKSUMS_CONTENT=$(cat "$CHECKSUMS_PATH")
fi

# record_hash <rel> <file> — remember <file>'s hash under <rel> for the
# checksums write at the end (no-op without the checksum library).
record_hash() {
    [ "$HAVE_CHECKSUMS" = true ] || return 0
    local hash
    hash=$(skill_file_hash "$2")
    if ! printf '%s\n' "$CHECKSUMS_CONTENT" | grep -qxF "$1 $hash"; then
        CHECKSUMS_CONTENT=$(update_checksum_entry "$1" "$hash" "$CHECKSUMS_CONTENT")
        CHECKSUMS_DIRTY=true
    fi
}

# ownership <rel> <dest> — "ours" when <dest> is the file we installed and it
# is unmodified, "customized" when we installed it and it was edited since,
# "foreign" when nothing records it as standards-owned.
ownership() {
    local stored current
    [ "$HAVE_CHECKSUMS" = true ] || { echo foreign; return 0; }
    stored=$(read_stored_hash "$1" "$CHECKSUMS_PATH")
    [ -n "$stored" ] || { echo foreign; return 0; }
    current=$(skill_file_hash "$2")
    if [ "$current" = "$stored" ]; then echo ours; else echo customized; fi
}

STATUS=0
for agent in $AGENTS; do
    target_dir=$(skills_agent_dir "$agent")
    if [ -z "$target_dir" ]; then
        [ "$QUIET" = true ] || echo "[$agent] Skills are indexed in the assembled config (no skill files for this agent)"
        continue
    fi

    written=0; unchanged=0; staged=0; failed=0
    for name in $(skills_list "$SKILLS_DIR"); do
        src="$SKILLS_DIR/$name.md"
        rel=$(skills_agent_target "$agent" "$name")
        dest="$PROJECT_ROOT/$rel"
        tmp=$(mktemp "${TMPDIR:-/tmp}/assemble-skill.XXXXXX")
        render_skill_for_agent "$agent" "$src" > "$tmp"

        if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
            unchanged=$((unchanged + 1))
            rm -f "$tmp"
            # Identical content is ours by definition: keep the baseline current.
            [ "$DRY_RUN" = true ] || record_hash "$rel" "$dest"
            continue
        fi

        own="ours"
        [ -f "$dest" ] && own=$(ownership "$rel" "$dest")
        if [ "$own" != "ours" ]; then
            reason="was edited since the standards installed it"
            [ "$own" = foreign ] && reason="exists but was not installed by the standards"
            pending="$PENDING_ROOT/$rel"
            if [ "$DRY_RUN" = true ]; then
                echo "  [dry-run] Would stage: $pending ($rel $reason)"
                rm -f "$tmp"
            elif mkdir -p "$(dirname "$pending")" 2>/dev/null && mv "$tmp" "$pending" 2>/dev/null; then
                echo "   ⚠️  $rel $reason — kept; new version staged to ${pending#"$PROJECT_ROOT"/}" >&2
            else
                failed=$((failed + 1)); STATUS=1
                rm -f "$tmp"
                echo "   ⚠️  Failed to stage $rel" >&2
                continue
            fi
            staged=$((staged + 1))
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would write: $dest"
            written=$((written + 1))
            rm -f "$tmp"
            continue
        fi
        if mkdir -p "$(dirname "$dest")" 2>/dev/null && mv "$tmp" "$dest" 2>/dev/null; then
            written=$((written + 1))
            record_hash "$rel" "$dest"
            [ "$QUIET" = true ] || echo "   ✅ $rel"
        else
            failed=$((failed + 1)); STATUS=1
            rm -f "$tmp"
            echo "   ⚠️  Failed to write $rel" >&2
        fi
    done

    staged_note=""
    [ "$staged" -gt 0 ] && staged_note=", $staged staged to ${PENDING_DIR:-.standards-pending}/"
    if [ "$DRY_RUN" = true ]; then
        echo "[$agent] Would install $written skill(s) to $target_dir/ ($unchanged unchanged$staged_note)"
    elif [ "$written" -eq 0 ] && [ "$failed" -eq 0 ] && [ "$staged" -eq 0 ]; then
        echo "[$agent] Skills up to date in $target_dir/ ($unchanged unchanged)"
    else
        echo "[$agent] Installed $written skill(s) to $target_dir/ ($unchanged unchanged$staged_note, $failed failed)"
    fi
done

if [ "$DRY_RUN" = false ] && [ "$CHECKSUMS_DIRTY" = true ]; then
    if ! printf '%s\n' "$CHECKSUMS_CONTENT" > "$CHECKSUMS_PATH" 2>/dev/null; then
        echo "   ⚠️  Failed to update ${CHECKSUMS_FILE:-.standards-checksums}" >&2
        STATUS=1
    fi
fi

exit "$STATUS"
