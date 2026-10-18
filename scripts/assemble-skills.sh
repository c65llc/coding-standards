#!/bin/bash
# Emit the agent-neutral skills (standards/skills/*.md) in each declared
# agent's own shape (proc-04, #194).
#
# Usage:
#   assemble-skills.sh [--project-root <dir>] [--skills-dir <dir>] [--dry-run]
#                      [--quiet] <agent> [<agent> ...]
#
# Per agent:
#   claude-code  .claude/skills/<name>.md            (frontmatter kept)
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
#   --quiet               Print only the per-agent summary line.
#   -h, --help            Show this help.
#
# A skill file is rewritten only when its rendered content differs from what
# is installed, so a repeated run is a no-op. Template variables
# ({{WORKTREE_DIR}} and friends) are resolved from the project root.
#
# Exit codes: 0 success, 1 a write failed, 2 usage error.

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

# Template variables ({{WORKTREE_DIR}}, {{PROJECT_NAME}}, ...) resolve against
# the consumer project, as they do for the assembled configs.
_TV_LIB="$SCRIPT_DIR/lib/template-vars.sh"
if [ -f "$_TV_LIB" ]; then
    # shellcheck disable=SC1090,SC1091
    source "$_TV_LIB"
fi

# render_to <agent> <skill_file> <tmp> — the rendered skill with template
# variables resolved, written to <tmp>.
render_to() {
    render_skill_for_agent "$1" "$2" > "$3"
    if declare -f resolve_template_vars >/dev/null 2>&1; then
        resolve_template_vars "$3" "$PROJECT_ROOT"
    fi
}

STATUS=0
for agent in $AGENTS; do
    target_dir=$(skills_agent_dir "$agent")
    if [ -z "$target_dir" ]; then
        [ "$QUIET" = true ] || echo "[$agent] Skills are indexed in the assembled config (no skill files for this agent)"
        continue
    fi

    written=0; unchanged=0; failed=0
    for name in $(skills_list "$SKILLS_DIR"); do
        src="$SKILLS_DIR/$name.md"
        rel=$(skills_agent_target "$agent" "$name")
        dest="$PROJECT_ROOT/$rel"
        tmp=$(mktemp "${TMPDIR:-/tmp}/assemble-skill.XXXXXX")
        render_to "$agent" "$src" "$tmp"
        if [ -f "$dest" ] && cmp -s "$tmp" "$dest"; then
            unchanged=$((unchanged + 1))
            rm -f "$tmp"
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
            [ "$QUIET" = true ] || echo "   ✅ $rel"
        else
            failed=$((failed + 1)); STATUS=1
            rm -f "$tmp"
            echo "   ⚠️  Failed to write $rel" >&2
        fi
    done

    if [ "$DRY_RUN" = true ]; then
        echo "[$agent] Would install $written skill(s) to $target_dir/ ($unchanged unchanged)"
    elif [ "$written" -eq 0 ] && [ "$failed" -eq 0 ]; then
        echo "[$agent] Skills up to date in $target_dir/ ($unchanged unchanged)"
    else
        echo "[$agent] Installed $written skill(s) to $target_dir/ ($unchanged unchanged, $failed failed)"
    fi
done

exit "$STATUS"
