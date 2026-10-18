#!/bin/bash
# Setup script for integrating standards into a new project
#
# Usage:
#   ./scripts/setup.sh [--agents <list>|all|detect] [--languages <list>]
#                      [--role <role>] [--workflow] [--dry-run] [-h|--help]
#
# Run with --help for the full option reference.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

KNOWN_AGENTS="claude-code cursor copilot gemini codex aider"

usage() {
    cat <<EOF
Usage: $0 [options]

Install coding standards and AI agent configurations into the current project.

Options:
  --agents <list>      Comma-separated agents to configure, or 'all', or 'detect'
                       (default). Agents: ${KNOWN_AGENTS// /, }.
                       With an explicit list, setup installs ONLY that agent's
                       artifacts: no git hooks, git aliases, Cursor commands,
                       .claude/settings.json or .gemini/ unless that agent is
                       in the list. 'detect' configures the agents already
                       present in the project plus git hooks and aliases.
                       Standards-owned files (.standards.yml,
                       .standards-checksums, .gitignore entries,
                       .trufflehog-ignore, detected language tool configs)
                       are installed in every mode.
  --languages <list>   Comma-separated languages (skips auto-detection), e.g.
                       typescript,python
  --role <role>        Project role block to include (default: service)
  --workflow           Also install the opt-in GitHub workflow templates
                       (standards-review.yml, trufflehog.yml)
  --migrate            Upgrade a pre-1.2 install (agent configs citing
                       renamed standards paths, a .codexrc, a legacy
                       .standards-config): rewrite the dead references in place from
                       docs/reference/renamed-files.md, convert .codexrc to
                       AGENTS.md, raise legacy 90/80 coverage tiers to the
                       95% floor, seed .standards.yml from detection plus a
                       legacy .standards-config, then run the normal safe
                       setup (assembled configs staged, checksums written,
                       MERGE_PLAN.md with a Migration section).
  --dry-run            Print every write that would happen; modify nothing
  -h, --help           Show this help and exit

Examples:
  $0                                 # detect agents, full install
  $0 --agents codex                  # AGENTS.md + standards-owned files only
  $0 --agents claude-code,cursor --languages typescript
  $0 --migrate                       # upgrade a pre-1.2 consumer
  $0 --dry-run
EOF
}

# Exit 2 with a usage error, mirroring lint-standards.sh. Nothing has been
# written to disk at this point, so an unknown flag never triggers an install.
usage_error() {
    echo "$1" >&2
    usage >&2
    exit 2
}

# Require that option "$1" received a value in "$2". A missing, empty, or
# option-like value (anything starting with '-') is a usage error, so
# `--languages --help` does not swallow `--help` as a language and proceed
# with a full install.
require_option_value() {
    if [ $# -lt 2 ] || [ -z "$2" ]; then
        usage_error "Option $1 requires a value"
    fi
    case "$2" in
        -*) usage_error "Option $1 requires a value (got '$2')" ;;
    esac
}

# Parse arguments
ROLE="service"
ROLE_EXPLICIT=false
AGENTS_OVERRIDE=""
LANGUAGES_OVERRIDE=""
DRY_RUN=false
INSTALL_WORKFLOW=false
MIGRATE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --role)
            require_option_value "$@"
            ROLE="$2"
            ROLE_EXPLICIT=true
            shift 2
            ;;
        --role=*)
            require_option_value "--role" "${1#--role=}"
            ROLE="${1#--role=}"
            ROLE_EXPLICIT=true
            shift
            ;;
        --migrate)
            MIGRATE=true
            shift
            ;;
        --agents)
            require_option_value "$@"
            AGENTS_OVERRIDE="$2"
            shift 2
            ;;
        --agents=*)
            require_option_value "--agents" "${1#--agents=}"
            AGENTS_OVERRIDE="${1#--agents=}"
            shift
            ;;
        --languages)
            require_option_value "$@"
            LANGUAGES_OVERRIDE="$2"
            shift 2
            ;;
        --languages=*)
            require_option_value "--languages" "${1#--languages=}"
            LANGUAGES_OVERRIDE="${1#--languages=}"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --workflow)
            INSTALL_WORKFLOW=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage_error "Unknown option: $1"
            ;;
    esac
done

# --- Agent-scoped install -----------------------------------------------------
# When --agents names an explicit list, only that agent's artifacts are
# installed. Workstation extras (git hooks, global git aliases) and other
# agents' side files are skipped unless the owning agent is in the list.

# True when the caller passed an explicit agent list (not detect/default).
agents_explicit() {
    [ -n "$AGENTS_OVERRIDE" ] && [ "$AGENTS_OVERRIDE" != "detect" ]
}

# Resolve the explicit --agents value to a space-separated list.
explicit_agent_list() {
    if [ "$AGENTS_OVERRIDE" = "all" ]; then
        echo "$KNOWN_AGENTS"
    else
        echo "$AGENTS_OVERRIDE" | tr ',' ' '
    fi
}

# agent_requested <agent>: should <agent>'s side artifacts be installed?
# In detect mode (default) every agent-side artifact is installed (the legacy
# full install); with an explicit list only listed agents qualify.
agent_requested() {
    local wanted="$1"
    if ! agents_explicit; then
        return 0
    fi
    local a
    for a in $(explicit_agent_list); do
        [ "$a" = "$wanted" ] && return 0
    done
    return 1
}

# Workstation extras (git hooks, global git aliases) are not owned by any
# agent, so they install only in detect mode.
install_git_extras() {
    ! agents_explicit
}

# Strip leading and trailing whitespace from "$1" (bash 3.2 compatible).
trim_ws() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# Validate the explicit --agents list field by field before anything else runs.
# Word splitting would silently drop empty or whitespace-only fields (",",
# "codex,", "codex, ,cursor", "   ") and leave an explicit list that installs
# no agent at all, so every comma-delimited field must be a known agent name.
# Surrounding whitespace is tolerated and normalised away.
if agents_explicit && [ "$AGENTS_OVERRIDE" != "all" ]; then
    normalised=""
    rest="$AGENTS_OVERRIDE,"
    while [ -n "$rest" ]; do
        field="$(trim_ws "${rest%%,*}")"
        rest="${rest#*,}"
        if [ -z "$field" ]; then
            usage_error "Option --agents contains an empty agent name: '$AGENTS_OVERRIDE'"
        fi
        case " $KNOWN_AGENTS " in
            *" $field "*) ;;
            *) usage_error "Unknown agent: $field (expected one of: ${KNOWN_AGENTS// /, }, all, detect)" ;;
        esac
        normalised="${normalised:+$normalised,}$field"
    done
    AGENTS_OVERRIDE="$normalised"
    unset normalised rest field
fi

# Refuse to run from inside the .standards/ submodule (see lib/guard.sh).
# This runs after argument parsing, which has no side effects, so --help and
# usage errors behave the same everywhere; every write still sits behind it.
# shellcheck source=lib/guard.sh disable=SC1091
source "$SCRIPT_DIR/lib/guard.sh"
refuse_if_inside_standards_dir "$PROJECT_ROOT" "setup.sh" || exit 2

# Dry-run aware file operations (shared: scripts/lib/dry-run.sh)
# shellcheck source=lib/dry-run.sh disable=SC1091
source "$SCRIPT_DIR/lib/dry-run.sh"

if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN — showing what would change (no files modified)"
    echo ""
fi

# Source checksum helpers
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
fi
if [ ! -f "$SCRIPT_DIR/lib/assembly.sh" ]; then
    echo "Error: required library 'assembly.sh' not found at $SCRIPT_DIR/lib/assembly.sh" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/assembly.sh"

# Map detected languages to block filenames (shared: scripts/lib/languages.sh)
# shellcheck source=lib/languages.sh disable=SC1091
source "$SCRIPT_DIR/lib/languages.sh"

# Monorepo members (shared: scripts/lib/members.sh)
# shellcheck source=lib/members.sh disable=SC1091
source "$SCRIPT_DIR/lib/members.sh"

# Worktree root (`worktree_dir:` in .standards.yml, default .claude/worktrees):
# gitignored by setup and guarded by the pre-commit template (proc-04, #190).
# shellcheck source=lib/worktrees.sh disable=SC1091
source "$SCRIPT_DIR/lib/worktrees.sh"

# Pre-1.2 migration (#184): rename map, dead-reference rewriter, .codexrc
# conversion, and the shape detection doctor.sh and sync-standards.sh share.
# shellcheck source=lib/migrate.sh disable=SC1091
source "$SCRIPT_DIR/lib/migrate.sh"

# Filled-in Project Overview / Key Commands capture (#183)
if [ -f "$SCRIPT_DIR/lib/project-sections.sh" ]; then
    # shellcheck source=lib/project-sections.sh disable=SC1091
    source "$SCRIPT_DIR/lib/project-sections.sh"
fi

# Members of this project (root-relative sub-roots), resolved from the existing
# root .standards.yml (`members:`) or by auto-discovery before setup rewrites
# that file. MEMBERS_EXPLICIT records whether the key was declared so it is
# preserved verbatim in the regenerated config.
MEMBERS=""
MEMBERS_EXPLICIT=false

# Function to setup AI agent configurations
setup_ai_agents() {
    local STANDARDS_DIR="$1"
    local SCRIPT_DIR="$2"
    local PROJECT_ROOT="$3"

    local AGENTS_DIR=""
    if [ -d "$STANDARDS_DIR/standards/agents" ]; then
        AGENTS_DIR="$STANDARDS_DIR/standards/agents"
    elif [ -d "$SCRIPT_DIR/../standards/agents" ]; then
        AGENTS_DIR="$SCRIPT_DIR/../standards/agents"
    else
        echo "⚠️  No agent configurations found (standards/agents directory missing)"
        return
    fi

    local BLOCKS_DIR=""
    if [ -d "$STANDARDS_DIR/standards/shared/blocks" ]; then
        BLOCKS_DIR="$STANDARDS_DIR/standards/shared/blocks"
    elif [ -d "$SCRIPT_DIR/../standards/shared/blocks" ]; then
        BLOCKS_DIR="$SCRIPT_DIR/../standards/shared/blocks"
    else
        echo "⚠️  No content blocks found (standards/shared/blocks directory missing)"
        return
    fi

    local ASSEMBLE_SCRIPT=""
    if [ -x "$SCRIPT_DIR/assemble-config.sh" ]; then
        ASSEMBLE_SCRIPT="$SCRIPT_DIR/assemble-config.sh"
    elif [ -n "$STANDARDS_DIR" ] && [ -x "$STANDARDS_DIR/scripts/assemble-config.sh" ]; then
        ASSEMBLE_SCRIPT="$STANDARDS_DIR/scripts/assemble-config.sh"
    else
        echo "⚠️  assemble-config.sh not found, cannot assemble agent configs"
        return
    fi

    # Detect project languages. With members (#179) the root detection skips
    # the member directories and each member contributes its own languages
    # (declared in its .standards.yml, else detected), so the root agent
    # configs — the only ones Cursor, Copilot and Aider read — cover every
    # member's rules.
    #
    # Two lists: ROOT_LANGS is what the root itself is (written to the root
    # .standards.yml, where lint-standards reads a non-empty list as "the root
    # is a project" and runs language checks against it); DETECTED_LANGS is
    # the union with the members, used only to assemble agent configs and
    # tool permissions. Writing the union into the root config would make a
    # pure aggregator fail its members' checks (no tsconfig.json at the root).
    local DETECTED_LANGS="" ROOT_LANGS=""
    local DETECT_SCRIPT="$SCRIPT_DIR/detect-languages.sh"
    #
    # The root's own languages come from the root's own manifests only
    # (--root-only): a tsconfig.json under apps/web says nothing about the
    # root, and listing typescript at the root would make lint-standards look
    # for a tsconfig.json there. The conventional sub-root walk still feeds
    # the agent configs, and a sub-root that is not a member is pointed out.
    # sync-standards.sh and diff-standards.sh build the same union
    # (root languages + subroot_languages + members), so they agree.
    local SUBROOT_LANGS=""
    if [ -n "$LANGUAGES_OVERRIDE" ]; then
        # --languages names the root's own languages; sub-roots and members
        # still contribute theirs to the agent configs.
        ROOT_LANGS=$(echo "$LANGUAGES_OVERRIDE" | tr ',' ' ')
    elif [ -x "$DETECT_SCRIPT" ]; then
        ROOT_LANGS=$("$DETECT_SCRIPT" --root-only "$PROJECT_ROOT")
    fi
    SUBROOT_LANGS=$(subroot_languages "$PROJECT_ROOT" "$MEMBERS" "$DETECT_SCRIPT")
    DETECTED_LANGS=$(dedupe_words "$ROOT_LANGS" "$SUBROOT_LANGS")
    if [ -n "$MEMBERS" ]; then
        DETECTED_LANGS=$(aggregate_member_languages "$PROJECT_ROOT" "$DETECTED_LANGS" "$MEMBERS" "$DETECT_SCRIPT")
    fi
    local extra_langs="" l
    for l in $SUBROOT_LANGS; do
        case " $ROOT_LANGS " in
            *" $l "*) ;;
            *) extra_langs="${extra_langs:+$extra_langs }$l" ;;
        esac
    done
    if [ -n "$extra_langs" ]; then
        echo "💡 Languages found in sub-roots (apps/*, packages/*, crates/*, …) but not at the root: ${extra_langs// /, }"
        echo "   They are assembled into the agent configs. Give each such sub-root its own .standards.yml and"
        echo "   declare it under members: in .standards.yml so lint-standards checks it under its own config."
    fi

    # Build block arguments: language blocks + role block
    # shellcheck disable=SC2086
    local LANG_BLOCKS
    LANG_BLOCKS=$(map_languages_to_blocks "$DETECTED_LANGS")
    local ROLE_BLOCK="role-${ROLE}.md"

    # Build full block list
    local BLOCK_ARGS=()
    for b in $LANG_BLOCKS; do
        BLOCK_ARGS+=("$b")
    done
    if [ -f "$BLOCKS_DIR/$ROLE_BLOCK" ]; then
        BLOCK_ARGS+=("$ROLE_BLOCK")
    fi

    # Determine which agents to set up
    local AGENTS_LIST
    if agents_explicit; then
        AGENTS_LIST=$(explicit_agent_list)
        echo "ℹ️  Explicit agents: $AGENTS_LIST (installing only their artifacts)"
    else
        # Default: detect agents already in use in the project.
        # Use the pre-detection snapshot captured before .cursor/commands was installed.
        AGENTS_LIST="${PRE_DETECTED_AGENTS:-}"
        DETECTED_AGENTS="$AGENTS_LIST"
        if [ -z "$AGENTS_LIST" ]; then
            echo "ℹ️  No agent configs detected. Pass --agents <list> or --agents all to install."
            echo "   Detected agents: (none)"
            echo "   Available: claude-code, cursor, copilot, gemini, codex, aider"
            AGENTS_LIST=""
        else
            echo "ℹ️  Detected agents: $AGENTS_LIST"
        fi
    fi

    ASSEMBLED_AGENTS_LIST=""
    local NEW_CHECKSUMS=""
    PENDING_LIST=""

    for agent in $AGENTS_LIST; do
        local BASE_TEMPLATE="$AGENTS_DIR/$agent/base-$agent.md"
        if [ ! -f "$BASE_TEMPLATE" ]; then
            continue
        fi

        local OUTPUT_PATH=""
        case "$agent" in
            claude-code) OUTPUT_PATH="$PROJECT_ROOT/CLAUDE.md" ;;
            cursor)      OUTPUT_PATH="$PROJECT_ROOT/.cursorrules" ;;
            copilot)     OUTPUT_PATH="$PROJECT_ROOT/.github/copilot-instructions.md" ;;
            gemini)      OUTPUT_PATH="$PROJECT_ROOT/.gemini/GEMINI.md" ;;
            codex)       OUTPUT_PATH="$PROJECT_ROOT/AGENTS.md" ;;
            aider)       OUTPUT_PATH="$PROJECT_ROOT/.aider-instructions.md" ;;
            *)           continue ;;
        esac

        # Create parent directories as needed
        case "$agent" in
            copilot) dry_run_mkdir "$PROJECT_ROOT/.github" ;;
            gemini)  dry_run_mkdir "$PROJECT_ROOT/.gemini" ;;
        esac

        echo "📝 Assembling $agent config..."
        local CHECKSUMS_PATH="$PROJECT_ROOT/$CHECKSUMS_FILE"
        local rc=0
        assemble_agent_config_guarded \
            "$agent" "$ASSEMBLE_SCRIPT" "$BLOCKS_DIR" "$BASE_TEMPLATE" \
            "$OUTPUT_PATH" "$CHECKSUMS_PATH" "$DRY_RUN" \
            ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"} || rc=$?

        case "$rc" in
            0)
                echo "✅ $agent config assembled"
                if [ "$DRY_RUN" = false ] && type compute_hash &>/dev/null; then
                    local new_hash
                    new_hash=$(compute_hash "$OUTPUT_PATH")
                    NEW_CHECKSUMS=$(update_checksum_entry "$(basename "$OUTPUT_PATH")" "$new_hash" "$NEW_CHECKSUMS")
                fi
                ;;
            1)
                echo "⚠️  $agent config already exists and differs — staged to $PENDING_DIR/"
                PENDING_LIST="${PENDING_LIST:+$PENDING_LIST }$(basename "$OUTPUT_PATH")"
                # Filled-in overview/commands that .standards.yml does not persist
                # are the usual reason a config can never match its checksum (#183).
                if declare -f print_capture_hint >/dev/null 2>&1; then
                    print_capture_hint "$PROJECT_ROOT" "$OUTPUT_PATH" "${OUTPUT_PATH#"$PROJECT_ROOT"/}" || true
                fi
                ;;
            2)
                PENDING_LIST="${PENDING_LIST:+$PENDING_LIST }$(basename "$OUTPUT_PATH")"
                if [ "$MIGRATE" = true ]; then
                    echo "⚠️  $agent config predates 1.2 — assembled version staged to $PENDING_DIR/ for /merge-standards"
                    # Migration baseline (#184): record the hash of the
                    # assembled version staged in .standards-pending/, not of
                    # the migrated file. sync then treats the migrated file as
                    # customized — stages a fresh assembly, never overwrites
                    # it — until the staged version is adopted or merged, at
                    # which point the checksum matches. Recording the migrated
                    # file's own hash would instead let the next sync replace
                    # it wholesale.
                    local staged="$PROJECT_ROOT/$PENDING_DIR/$(basename "$OUTPUT_PATH")"
                    if [ "$DRY_RUN" = false ] && [ -f "$staged" ] && type compute_hash &>/dev/null; then
                        local staged_hash
                        staged_hash=$(compute_hash "$staged")
                        NEW_CHECKSUMS=$(update_checksum_entry "$(basename "$OUTPUT_PATH")" "$staged_hash" "$NEW_CHECKSUMS")
                    fi
                else
                    echo "⚠️  $agent config was manually created — backup in $PENDING_DIR/"
                fi
                ;;
            3)
                echo "⚠️  Failed to assemble $agent config (non-fatal, continuing...)"
                continue
                ;;
            4)
                echo "ℹ️  $agent config is curated (managed: false in .standards.yml) — left as is."
                echo "   Review upstream template changes with diff-standards.sh."
                # Record the curated file's hash so .standards-checksums has a
                # baseline for it: doctor then inspects the file (labelling a
                # later edit curated, not drifted) instead of never seeing it.
                if [ "$DRY_RUN" = false ] && [ -f "$OUTPUT_PATH" ] && type compute_hash &>/dev/null; then
                    local curated_hash
                    curated_hash=$(compute_hash "$OUTPUT_PATH")
                    NEW_CHECKSUMS=$(update_checksum_entry "$(basename "$OUTPUT_PATH")" "$curated_hash" "$NEW_CHECKSUMS")
                fi
                ;;
        esac

        # Aider special handling: also copy aiderrc.template to .aiderrc.
        # Checksum-guarded like sync-standards (#184): an existing .aiderrc
        # that setup did not write (no stored hash) or that was edited since
        # is never overwritten — the template is staged to .standards-pending/
        # instead. A file identical to the template, or matching its stored
        # hash, is simply refreshed.
        if [ "$agent" = "aider" ] && [ -f "$AGENTS_DIR/aider/aiderrc.template" ]; then
            local rc_template="$AGENTS_DIR/aider/aiderrc.template"
            local rc_target="$PROJECT_ROOT/.aiderrc"
            local rc_stored="" rc_current="" rc_refresh=true
            if [ -f "$rc_target" ]; then
                if type read_stored_hash &>/dev/null; then
                    rc_stored=$(read_stored_hash ".aiderrc" "$CHECKSUMS_PATH")
                fi
                rc_current=$(shasum -a 256 "$rc_target" | awk '{print $1}')
                if [ -n "$rc_stored" ] && [ "$rc_current" = "$rc_stored" ]; then
                    rc_refresh=true
                elif cmp -s "$rc_template" "$rc_target" 2>/dev/null; then
                    rc_refresh=true
                else
                    rc_refresh=false
                fi
            fi
            if [ "$DRY_RUN" = true ]; then
                if [ "$rc_refresh" = true ]; then
                    echo "  [dry-run] Would copy: $rc_template → $rc_target"
                else
                    echo "  [dry-run] Would stage: $rc_template → $PROJECT_ROOT/$PENDING_DIR/.aiderrc (.aiderrc differs and was not written by setup)"
                fi
            elif [ "$rc_refresh" = true ]; then
                # install_aiderrc (lib/migrate.sh) carries a project's own
                # `model =` line forward: the template no longer pins one.
                if install_aiderrc "$rc_template" "$rc_target" 2>/dev/null; then
                    echo "   ✅ Aider .aiderrc installed"
                    if type compute_hash &>/dev/null; then
                        local rc_hash
                        rc_hash=$(shasum -a 256 "$rc_target" | awk '{print $1}')
                        NEW_CHECKSUMS=$(update_checksum_entry ".aiderrc" "$rc_hash" "$NEW_CHECKSUMS")
                    fi
                fi
            else
                mkdir -p "$PROJECT_ROOT/$PENDING_DIR"
                cp "$rc_template" "$PROJECT_ROOT/$PENDING_DIR/.aiderrc"
                echo "   ⚠️  .aiderrc differs from aiderrc.template and was not written by setup — template staged to $PENDING_DIR/.aiderrc"
                PENDING_LIST="${PENDING_LIST:+$PENDING_LIST }.aiderrc"
                if [ "$MIGRATE" = true ] && type compute_hash &>/dev/null; then
                    # Same baseline rule as the assembled configs above: the
                    # staged template is the recorded version, so sync keeps
                    # reporting .aiderrc as customized until it is adopted.
                    local rc_hash
                    rc_hash=$(shasum -a 256 "$rc_template" | awk '{print $1}')
                    NEW_CHECKSUMS=$(update_checksum_entry ".aiderrc" "$rc_hash" "$NEW_CHECKSUMS")
                fi
            fi
        fi

        # Track assembled agents
        if [ -n "$ASSEMBLED_AGENTS_LIST" ]; then
            ASSEMBLED_AGENTS_LIST="$ASSEMBLED_AGENTS_LIST,$agent"
        else
            ASSEMBLED_AGENTS_LIST="$agent"
        fi
    done

    # Codex: deprecation warning for old .codexrc
    if [ -f "$PROJECT_ROOT/.codexrc" ]; then
        echo "⚠️  .codexrc is deprecated. Codex now uses AGENTS.md."
        echo "   Your .codexrc has been preserved. Remove it when ready."
    fi

    # Claude Code settings.json and permissions — only when claude-code is requested
    if ! agent_requested claude-code; then
        : # skipped: claude-code not in --agents list
    elif [ ! -f "$PROJECT_ROOT/.claude/settings.json" ] || [ "$DRY_RUN" = true ]; then
        if [ "$DRY_RUN" = false ]; then
            mkdir -p "$PROJECT_ROOT/.claude"
        fi
        local BUILD_SCRIPT="$SCRIPT_DIR/build-claude-settings.sh"
        local BASE_SETTINGS="$AGENTS_DIR/claude-code/settings.json.example"
        local PERMS_DIR="$AGENTS_DIR/claude-code/permissions"
        local DETECT_SCRIPT="$SCRIPT_DIR/detect-languages.sh"

        if [ "$DRY_RUN" = true ]; then
            if [ -f "$PROJECT_ROOT/.claude/settings.json" ]; then
                echo "ℹ️  .claude/settings.json already exists, skipping"
            else
                dry_run_mkdir "$PROJECT_ROOT/.claude"
                echo "  [dry-run] Would write: $PROJECT_ROOT/.claude/settings.json"
            fi
        elif [ -x "$DETECT_SCRIPT" ] && [ -x "$BUILD_SCRIPT" ] && [ -d "$PERMS_DIR" ]; then
            if [ -n "$DETECTED_LANGS" ]; then
                # shellcheck disable=SC2086
                if "$BUILD_SCRIPT" "$BASE_SETTINGS" "$PERMS_DIR" $DETECTED_LANGS > "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null; then
                    echo "✅ Claude Code settings installed at .claude/settings.json"
                    # shellcheck disable=SC2086
                    echo "   Detected languages: $(echo $DETECTED_LANGS | tr '\n' ' ')"
                else
                    echo "⚠️  Failed to build language-aware settings, using base template..."
                    cp "$BASE_SETTINGS" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
                fi
            else
                if cp "$BASE_SETTINGS" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null; then
                    echo "✅ Claude Code settings installed at .claude/settings.json (no languages detected)"
                else
                    echo "⚠️  Failed to install Claude Code settings (non-fatal, continuing...)"
                fi
            fi
        elif [ -f "$BASE_SETTINGS" ]; then
            # Fallback: scripts not available, use base template
            if cp "$BASE_SETTINGS" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null; then
                echo "✅ Claude Code settings installed at .claude/settings.json"
            else
                echo "⚠️  Failed to install Claude Code settings (non-fatal, continuing...)"
            fi
        fi
    else
        echo "ℹ️  .claude/settings.json already exists, skipping"
    fi

    # Copy language-specific tool configs (dotglob for .prettierrc, .rubocop.yml, etc.)
    if [ -n "$DETECTED_LANGS" ]; then
        for lang in $DETECTED_LANGS; do
            local LANG_CONFIG_DIR="$AGENTS_DIR/$lang"
            if [ -d "$LANG_CONFIG_DIR" ]; then
                (
                    shopt -s dotglob nullglob
                    for config_file in "$LANG_CONFIG_DIR"/*; do
                        [ -f "$config_file" ] || continue
                        config_name="$(basename "$config_file")"
                        if [ ! -f "$PROJECT_ROOT/$config_name" ]; then
                            if [ "$DRY_RUN" = true ]; then
                                echo "  [dry-run] Would copy: $config_file → $PROJECT_ROOT/$config_name"
                            elif cp "$config_file" "$PROJECT_ROOT/$config_name" 2>/dev/null; then
                                echo "   ✅ Installed $config_name ($lang)"
                            fi
                        fi
                    done
                )
            fi
        done
    fi

    # Gemini settings.json (separate from GEMINI.md which is now assembled).
    # Only when gemini is requested — otherwise .gemini/ must not appear.
    local GEMINI_SOURCE=""
    if ! agent_requested gemini; then
        GEMINI_SOURCE=""
    elif [ -n "$STANDARDS_DIR" ] && [ -d "$STANDARDS_DIR/.gemini" ]; then
        GEMINI_SOURCE="$STANDARDS_DIR/.gemini"
    elif [ -d "$SCRIPT_DIR/../.gemini" ]; then
        GEMINI_SOURCE="$SCRIPT_DIR/../.gemini"
    fi

    if [ -n "$GEMINI_SOURCE" ] && [ -f "$GEMINI_SOURCE/settings.json" ]; then
        dry_run_mkdir "$PROJECT_ROOT/.gemini"
        local GEMINI_JSON_VALID=true
        # Validate JSON syntax before copying
        if command -v python3 >/dev/null 2>&1; then
            if ! python3 -m json.tool "$GEMINI_SOURCE/settings.json" >/dev/null 2>&1; then
                echo "⚠️  Invalid JSON in Gemini settings.json, skipping..."
                GEMINI_JSON_VALID=false
            fi
        elif command -v jq >/dev/null 2>&1; then
            if ! jq empty "$GEMINI_SOURCE/settings.json" >/dev/null 2>&1; then
                echo "⚠️  Invalid JSON in Gemini settings.json, skipping..."
                GEMINI_JSON_VALID=false
            fi
        fi
        if [ "$GEMINI_JSON_VALID" = true ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "  [dry-run] Would copy: $GEMINI_SOURCE/settings.json → $PROJECT_ROOT/.gemini/settings.json"
            elif cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                echo "✅ Gemini CLI settings installed at .gemini/settings.json"
            else
                echo "⚠️  Failed to install Gemini settings (non-fatal, continuing...)"
            fi
        fi
    fi

    # Hand-written blocks the regenerated file must carry across verbatim
    # (#183, #190): the persisted project text, the curated-file map, the hook
    # manager and the worktree root. Captured before the write below, which
    # truncates the file.
    local PRESERVED_YML="" _k _blk
    if [ -f "$PROJECT_ROOT/.standards.yml" ] && declare -f yaml_raw_block >/dev/null 2>&1; then
        for _k in project_overview key_commands managed hooks worktree_dir; do
            _blk=$(yaml_raw_block "$_k" "$PROJECT_ROOT/.standards.yml")
            [ -n "$_blk" ] || continue
            PRESERVED_YML="${PRESERVED_YML:+$PRESERVED_YML
}$_blk"
        done
    fi

    # Write .standards.yml
    {
        echo "# .standards.yml — Project standards configuration"
        echo "# Generated by coding-standards setup.sh"
        echo "version: 1"
        if [ -n "$ROOT_LANGS" ]; then
            echo "languages:"
            for lang in $ROOT_LANGS; do echo "  - $lang"; done
        else
            echo "languages: []"
        fi
        if [ -n "$MEMBERS" ] && [ "$DETECTED_LANGS" != "$ROOT_LANGS" ]; then
            echo "# Only the root's own languages are listed above. Member languages"
            echo "# (${DETECTED_LANGS// /, }) come from each member's .standards.yml and are"
            echo "# assembled into the root agent configs; listing them here would make"
            echo "# lint-standards run their checks against the root as well."
        fi
        if [ -n "$ASSEMBLED_AGENTS_LIST" ]; then
            echo "agents:"
            for agent in $(echo "$ASSEMBLED_AGENTS_LIST" | tr ',' ' '); do echo "  - $agent"; done
        else
            echo "agents: []"
        fi
        echo "role: $ROLE"
        if [ "$MEMBERS_EXPLICIT" = true ]; then
            echo "# Monorepo members: sub-roots with their own .standards.yml. lint-standards,"
            echo "# doctor and sync iterate them; the root agent configs cover their languages."
            if [ -n "$MEMBERS" ]; then
                echo "members:"
                for m in $MEMBERS; do echo "  - $(member_yaml_scalar "$m")"; done
            else
                echo "members: []"
            fi
        elif [ -n "$MEMBERS" ]; then
            echo "# Monorepo members auto-discovered (*/.standards.yml, one or two levels down):"
            echo "#   ${MEMBERS// /, }"
            echo "# Declare 'members:' to pin the list, or 'members: []' to disable discovery."
        fi
        echo "coverage:"
        echo "  minimum: 95"
        echo "  domain: 100"
        echo "tests:"
        echo "  slow_threshold_ms: 2000"
        echo "architecture: clean"
        echo "security: strict"
        if [ -n "$PRESERVED_YML" ]; then
            echo "# Project text, curated files, hook manager and worktree root (kept from"
            echo "# the previous .standards.yml; see templates/standards.yml.example)."
            printf '%s\n' "$PRESERVED_YML"
        else
            echo "# Project text assembled into the agent configs ({{PROJECT_OVERVIEW}} /"
            echo "# {{KEY_COMMANDS}}). Persist it here so re-assembly reproduces it and the"
            echo "# checksum stays stable; /merge-standards fills it in."
            echo "# project_overview: |"
            echo "#   One paragraph: what this project is and how it is organised."
            echo "# key_commands: |"
            echo "#   make test    # run the test suite"
            echo "# Hand-curated agent configs that sync must not regenerate (doctor and"
            echo "# sync report them as curated, diff-standards still previews changes):"
            echo "# managed:"
            echo "#   CLAUDE.md: false"
            echo "# Git hook manager owning post-merge/commit-msg: standards (default,"
            echo "# native hooks written by setup.sh) | lefthook | husky | custom."
            echo "# hooks: custom"
            echo "# Agent worktree root (proc-04 Worktree Hygiene): one gitignored directory"
            echo "# per repo; setup ignores it, the pre-commit guard refuses commits under it,"
            echo "# doctor and worktree-gc report what lives there. Default .claude/worktrees."
            echo "# worktree_dir: .claude/worktrees"
        fi
        echo "# Conventional Commits enforcement — uncomment to tune. Defaults: the last"
        echo "# 50 non-merge commits locally; the PR's own commits in the standards-review"
        echo "# action. Precedence: since > PR range (CI) > window, so a window only"
        echo "# applies when no range is available and never widens a PR check."
        echo "# commits:"
        echo "#   window: 50             # inspect the last N non-merge commits"
        echo "#   since: origin/main     # or inspect <ref>..HEAD"
        echo "#   scopes: [api, domain]  # allow-list for scoped commits"
    } | dry_run_write "$PROJECT_ROOT/.standards.yml"
    if [ "$DRY_RUN" = false ]; then
        echo "✅ .standards.yml created"
    fi

    # Members: bootstrap a .standards.yml for a declared member that has none
    # (languages detected in that directory, same role); an existing member
    # config is the member's own and is never rewritten.
    if [ -n "$MEMBERS" ]; then
        echo "📦 Members:"
        local m member_dir member_langs
        for m in $MEMBERS; do
            member_dir="$PROJECT_ROOT/$m"
            if [ ! -d "$member_dir" ]; then
                echo "   ⚠️  $m: declared in members: but no such directory"
                continue
            fi
            member_langs=$(member_languages "$PROJECT_ROOT" "$m" "$DETECT_SCRIPT" "$MEMBERS")
            if [ -f "$member_dir/.standards.yml" ]; then
                echo "   - $m: .standards.yml present (languages: ${member_langs:-none})"
                continue
            fi
            # resolve_members already drops a member whose config is a symlink;
            # never write through one regardless (a dangling link fails -f).
            if [ -L "$member_dir/.standards.yml" ]; then
                echo "   ⚠️  $m: .standards.yml is a symlink; not writing through it"
                continue
            fi
            {
                echo "# .standards.yml — member '$m' of the project at the repository root"
                echo "# Generated by coding-standards setup.sh"
                echo "version: 1"
                if [ -n "$member_langs" ]; then
                    echo "languages:"
                    for lang in $member_langs; do echo "  - $lang"; done
                else
                    echo "languages: []"
                fi
                echo "role: $ROLE"
            } | dry_run_write "$member_dir/.standards.yml"
            if [ "$DRY_RUN" = false ]; then
                echo "   ✅ $m: .standards.yml created (languages: ${member_langs:-none})"
            fi
        done
    fi

    # Write initial checksums
    if [ "$DRY_RUN" = false ] && type compute_hash &>/dev/null && [ -n "$NEW_CHECKSUMS" ]; then
        echo "$NEW_CHECKSUMS" > "$PROJECT_ROOT/$CHECKSUMS_FILE"
        echo "✅ .standards-checksums created"
    elif [ "$DRY_RUN" = true ] && [ -n "$NEW_CHECKSUMS" ]; then
        echo "  [dry-run] Would write: $PROJECT_ROOT/$CHECKSUMS_FILE"
    fi

    # Install merge-standards skill (lives under .claude/, so claude-code only)
    local SKILL_SOURCE="$AGENTS_DIR/claude-code/skills/merge-standards.md"
    if agent_requested claude-code && [ -f "$SKILL_SOURCE" ]; then
        dry_run_mkdir "$PROJECT_ROOT/.claude/skills"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would copy: $SKILL_SOURCE → $PROJECT_ROOT/.claude/skills/merge-standards.md"
        else
            cp "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md"
            echo "✅ /merge-standards skill installed"
        fi
    fi
}

echo "🔧 Setting up project standards..."

# Determine if we're in the standards repo or a project using it
if [ "$SCRIPT_DIR" = "$PROJECT_ROOT" ]; then
    # We're in the standards repo itself
    echo "📋 Detected standards repository."
else
    # We're in a project using standards
    STANDARDS_DIR="$PROJECT_ROOT/.standards"

    if [ -d "$STANDARDS_DIR" ]; then
        echo "📋 Found standards submodule at .standards"
    elif [ -d "$SCRIPT_DIR/../standards" ]; then
        echo "📋 Using standards from script location"
        STANDARDS_DIR="$SCRIPT_DIR/.."
    else
        echo "❌ Error: Could not find standards directory"
        exit 1
    fi

    # --- Pre-1.2 migration (#184) ------------------------------------------
    # Runs before agent detection (a converted AGENTS.md must be detected) and
    # before anything reads or writes .standards.yml (a legacy
    # .standards-config seeds it). Without --migrate a pre-1.2 shape is only
    # reported, so a plain setup never rewrites a file the operator did not
    # ask it to.
    RENAME_MAP=$(rename_map_path "$STANDARDS_DIR" "$SCRIPT_DIR") || RENAME_MAP=""
    PRE12_REASONS=$(pre12_shape "$PROJECT_ROOT" "$RENAME_MAP") || PRE12_REASONS=""
    MIGRATE_EXTRA_AGENTS=""
    SETUP_CMD="./scripts/setup.sh"
    [ "$STANDARDS_DIR" = "$PROJECT_ROOT/.standards" ] && SETUP_CMD=".standards/scripts/setup.sh"

    run_pre12_migration() {
        local rel f
        echo "$PRE12_REASONS" | sed 's/^/   - /'

        # Legacy .standards-config (KEY=value) seeds the .standards.yml this run
        # writes: role and languages unless given on the command line, agents
        # in addition to the detected ones. It is then retired to a gitignored
        # backup so doctor stops reporting the legacy format.
        if [ -f "$PROJECT_ROOT/.standards-config" ] && [ ! -f "$PROJECT_ROOT/.standards.yml" ] \
           && declare -f read_standards_config >/dev/null 2>&1 \
           && read_standards_config "$PROJECT_ROOT" 2>/dev/null; then
            if [ "$ROLE_EXPLICIT" = false ] && [ -n "${STD_ROLE:-}" ]; then
                ROLE="$STD_ROLE"
            fi
            local legacy_langs
            legacy_langs=$(trim_ws "${STD_LANGUAGES:-}")
            if [ -z "$LANGUAGES_OVERRIDE" ] && [ -n "$legacy_langs" ]; then
                LANGUAGES_OVERRIDE=$(echo "$legacy_langs" | tr ' ' ',')
            fi
            MIGRATE_EXTRA_AGENTS=$(trim_ws "${STD_AGENTS:-}")
            echo "   📄 .standards-config: role=$ROLE languages=${legacy_langs:-<detect>} agents=${MIGRATE_EXTRA_AGENTS:-<detect>} → seeds .standards.yml"
            if [ "$DRY_RUN" = true ]; then
                echo "  [dry-run] Would retire .standards-config → .standards-config.pre-standards-setup"
            else
                mv "$PROJECT_ROOT/.standards-config" "$PROJECT_ROOT/.standards-config.pre-standards-setup"
                echo "   ✅ .standards-config retired → .standards-config.pre-standards-setup (.standards.yml replaces it)"
            fi
        fi

        # Dead standards references, rewritten in place from the rename map.
        if [ -n "$RENAME_MAP" ]; then
            echo "   🔁 Rewriting renamed standards references (map: ${RENAME_MAP#"$PROJECT_ROOT"/})"
            for rel in $MIGRATE_AGENT_CONFIGS; do
                [ "$rel" = ".codexrc" ] && continue   # converted below
                f="$PROJECT_ROOT/$rel"
                [ -f "$f" ] || continue
                rewrite_dead_refs "$f" "$RENAME_MAP" "$DRY_RUN" "$PROJECT_ROOT"
                if [ "$rel" = ".aiderrc" ]; then
                    fix_legacy_tiers "$f" "$DRY_RUN" "$PROJECT_ROOT"
                fi
            done
        else
            echo "   ⚠️  docs/reference/renamed-files.md not found in $STANDARDS_DIR — dead references are not rewritten"
        fi

        # .codexrc → AGENTS.md (Codex reads AGENTS.md since #40).
        if [ -f "$PROJECT_ROOT/.codexrc" ]; then
            convert_codexrc "$PROJECT_ROOT" "$RENAME_MAP" "$DRY_RUN" "$PROJECT_ROOT/$PENDING_DIR"
            MIGRATE_EXTRA_AGENTS="${MIGRATE_EXTRA_AGENTS:+$MIGRATE_EXTRA_AGENTS }codex"
        fi

        # Notes for the MERGE_PLAN Migration section.
        _migrate_append MIGRATE_NOTES "- Rewrote $MIGRATE_REWRITES renamed standards reference(s) in place; each changed file's original is kept as \`<file>.pre-standards-setup\`. The map is \`.standards/docs/reference/renamed-files.md\`."
        _migrate_append MIGRATE_NOTES "- The checksum baseline for every staged file is the **staged assembled version**, so \`sync-standards\` keeps staging a fresh assembly (never overwriting the migrated file) until you adopt or merge it; once adopted, the checksum matches."
        local line
        if [ -n "$MIGRATE_DROPPED" ]; then
            _migrate_append MIGRATE_NOTES "- Dropped lines that only cited a removed standard:"
            while IFS= read -r line; do
                [ -n "$line" ] && _migrate_append MIGRATE_NOTES "  - \`$line\`"
            done <<EOF
$MIGRATE_DROPPED
EOF
        fi
        if [ -n "$MIGRATE_UNRESOLVED" ]; then
            _migrate_append MIGRATE_NOTES "- Still cites a removed standard (left in place — delete the sentence or point it at the replacement named in the map's Notes column):"
            while IFS= read -r line; do
                [ -n "$line" ] && _migrate_append MIGRATE_NOTES "  - \`$line\`"
            done <<EOF
$MIGRATE_UNRESOLVED
EOF
        fi
    }

    if [ "$MIGRATE" = true ]; then
        echo ""
        echo "🧭 Migrating a pre-1.2 install..."
        if [ -z "$PRE12_REASONS" ]; then
            echo "ℹ️  Nothing to migrate: no pre-1.2 artefacts found (no renamed standards references, .codexrc or legacy .standards-config). Running a normal setup."
        else
            run_pre12_migration
        fi
    elif [ -n "$PRE12_REASONS" ]; then
        echo ""
        echo "⚠️  Pre-1.2 install detected:"
        echo "$PRE12_REASONS" | sed 's/^/   - /'
        echo "   Run: $SETUP_CMD --migrate  (rewrites the dead references, converts .codexrc, bootstraps .standards.yml and checksums; stages anything ambiguous)"
        echo "   Map of renamed files: ${RENAME_MAP:-docs/reference/renamed-files.md}"
    fi

    # Resolve monorepo members before anything rewrites the root .standards.yml.
    MEMBERS=$(resolve_members "$PROJECT_ROOT" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    if members_declared "$PROJECT_ROOT"; then
        MEMBERS_EXPLICIT=true
    fi
    while IFS= read -r rejected; do
        [ -z "$rejected" ] && continue
        echo "⚠️  members: $rejected"
    done <<EOF
$(rejected_members "$PROJECT_ROOT" 2>/dev/null)
EOF
    if [ -n "$MEMBERS" ]; then
        if [ "$MEMBERS_EXPLICIT" = true ]; then
            echo "📦 Members declared in .standards.yml: ${MEMBERS// /, }"
        else
            echo "📦 Members auto-discovered (*/.standards.yml): ${MEMBERS// /, }"
        fi
    fi

    # Detect agents early — before .cursor/commands install modifies the filesystem.
    # This snapshot is used by setup_ai_agents() when --agents detect (default).
    if [ -z "$AGENTS_OVERRIDE" ] || [ "$AGENTS_OVERRIDE" = "detect" ]; then
        if [ -f "$SCRIPT_DIR/lib/detect-agents.sh" ]; then
            # shellcheck disable=SC1091
            source "$SCRIPT_DIR/lib/detect-agents.sh"
            PRE_DETECTED_AGENTS=$(detect_installed_agents "$PROJECT_ROOT")
        fi
        # --migrate: a .codexrc means Codex (AGENTS.md is assembled for it),
        # and a legacy .standards-config's agents: list still counts.
        if [ -n "$MIGRATE_EXTRA_AGENTS" ]; then
            PRE_DETECTED_AGENTS=$(dedupe_words "$PRE_DETECTED_AGENTS" "$MIGRATE_EXTRA_AGENTS")
        fi
    fi

    # Copy Cursor custom commands if they exist (only when cursor is requested)
    if ! agent_requested cursor; then
        CURSOR_COMMANDS_SOURCE=""
    elif [ -d "$STANDARDS_DIR/.cursor/commands" ]; then
        CURSOR_COMMANDS_SOURCE="$STANDARDS_DIR/.cursor/commands"
    elif [ -d "$SCRIPT_DIR/../.cursor/commands" ]; then
        CURSOR_COMMANDS_SOURCE="$SCRIPT_DIR/../.cursor/commands"
    else
        CURSOR_COMMANDS_SOURCE=""
    fi

    if [ -n "$CURSOR_COMMANDS_SOURCE" ] && [ -d "$CURSOR_COMMANDS_SOURCE" ]; then
        echo "📝 Setting up Cursor custom commands..."
        dry_run_mkdir "$PROJECT_ROOT/.cursor/commands"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would copy: $CURSOR_COMMANDS_SOURCE/* → $PROJECT_ROOT/.cursor/commands/"
        elif cp -r "$CURSOR_COMMANDS_SOURCE"/* "$PROJECT_ROOT/.cursor/commands/" 2>/dev/null; then
            echo "✅ Cursor commands installed"
            echo "⚠️  Please fully quit and restart Cursor to load custom commands"
        else
            echo "⚠️  Failed to install Cursor commands (non-fatal, continuing...)"
        fi
    fi

    # Setup multi-agent configurations (now assembly-based)
    echo ""
    echo "🤖 Setting up AI agent configurations..."
    setup_ai_agents "$STANDARDS_DIR" "$SCRIPT_DIR" "$PROJECT_ROOT"

    # Emit MERGE_PLAN.md if setup staged any pending updates (or --migrate has
    # notes to hand over). Never in dry-run: nothing was staged.
    if [ -f "$SCRIPT_DIR/lib/merge-plan.sh" ] && [ "$DRY_RUN" = false ] \
       && { [ -n "${PENDING_LIST:-}" ] || [ -n "${MIGRATE_NOTES:-}" ]; }; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/lib/merge-plan.sh"
        write_merge_plan "$PROJECT_ROOT" "$PENDING_LIST" "${DETECTED_AGENTS:-}" "${ASSEMBLED_AGENTS_LIST:-}" "${MIGRATE_NOTES:-}"
        echo ""
        echo "📋 Pending updates staged. See .standards-pending/MERGE_PLAN.md or run:"
        echo "   Claude Code: /merge-standards"
        echo "   Cursor:      /merge-standards"
        echo "   CLI:         make merge-standards"
    fi
fi

# Worktree root (proc-04 § Worktree Hygiene, #190): read after .standards.yml
# was (re)written above, which carries a declared worktree_dir: across. An
# invalid value is reported and the default used, as doctor.sh does.
WORKTREE_DIR=$(worktree_root_dir "$PROJECT_ROOT")
WORKTREE_DIR_PROBLEM=$(worktree_dir_problem "$PROJECT_ROOT")
if [ -n "$WORKTREE_DIR_PROBLEM" ]; then
    echo "⚠️  worktree_dir: '$WORKTREE_DIR_PROBLEM' in .standards.yml is not a relative path inside the project; using $WORKTREE_DIR_DEFAULT"
fi
# Templates live in the standards checkout (the submodule, or this repo itself).
TEMPLATES_DIR="${STANDARDS_DIR:-$SCRIPT_DIR/..}/templates"

# Set up git hooks (workstation extra: skipped when --agents names an explicit list)
GIT_HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

# hooks: in .standards.yml names the manager that owns the hooks (#183). With
# lefthook, husky or a custom manager declared, the native post-merge hook is
# theirs to provide (and would not run under core.hooksPath anyway).
DECLARED_HOOKS=""
if declare -f read_standards_config >/dev/null 2>&1 && read_standards_config "$PROJECT_ROOT" 2>/dev/null; then
    DECLARED_HOOKS="${STD_HOOKS:-}"
fi
# Only a recognised external manager skips the native hook. An unrecognised
# value (a typo, say) is reported and treated as undeclared — as doctor.sh
# does — so a fresh project still gets a post-merge hook rather than none.
UNRECOGNISED_HOOKS=""
case "$DECLARED_HOOKS" in
    ""|standards|lefthook|husky|custom) ;;
    *) UNRECOGNISED_HOOKS="$DECLARED_HOOKS"; DECLARED_HOOKS="" ;;
esac
warn_unrecognised_hooks() {
    [ -n "$UNRECOGNISED_HOOKS" ] || return 0
    echo "⚠️  hooks: '$UNRECOGNISED_HOOKS' in .standards.yml is not recognised (expected standards, lefthook, husky or custom) — installing the native post-merge hook."
}

if ! install_git_extras; then
    echo "ℹ️  Skipping git hooks (explicit --agents). Run without --agents to install them."
elif [ -n "$DECLARED_HOOKS" ] && [ "$DECLARED_HOOKS" != "standards" ]; then
    echo "🪝 Setting up git hooks..."
    echo "ℹ️  hooks: $DECLARED_HOOKS declared in .standards.yml — not installing the native post-merge hook."
    echo "   Keep the standards-sync reminder in your $DECLARED_HOOKS post-merge hook (see templates/lefthook.yml.example)."
elif [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "🪝 Setting up git hooks..."
    echo "⚠️  Not a git repository. Skipping git hooks setup."
elif [ "$DRY_RUN" = true ]; then
    echo "🪝 Setting up git hooks..."
    warn_unrecognised_hooks
    echo "  [dry-run] Would write: $GIT_HOOKS_DIR/post-merge"
else
    echo "🪝 Setting up git hooks..."
    warn_unrecognised_hooks
    # Post-merge hook to sync standards
    cat > "$GIT_HOOKS_DIR/post-merge" << 'HOOK'
#!/bin/bash
# Auto-sync standards after merge/pull

if [ -d ".standards" ]; then
    cd .standards
    git fetch origin >/dev/null 2>&1
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)

    if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
        echo "📋 Standards repository has updates. Run: cd .standards && git pull"
    fi
fi
HOOK

    chmod +x "$GIT_HOOKS_DIR/post-merge"
    echo "✅ Git hooks installed"
fi

# Pre-commit worktree guard (proc-04 § Worktree Hygiene, #190): refuses a
# commit that stages a path under the worktree root (a worktree committed as
# a submodule, or its files). Installed natively when no pre-commit hook
# exists and the standards own the hooks; otherwise setup prints how to adopt
# the template, since an existing hook or another manager is the project's.
GUARD_TEMPLATE="$TEMPLATES_DIR/pre-commit-worktree-guard.example"
GUARD_RELATIVE=".standards/templates/pre-commit-worktree-guard.example"
if [ ! -f "$GUARD_TEMPLATE" ]; then
    : # template not shipped with this checkout
elif ! install_git_extras; then
    : # explicit --agents: git hooks are skipped (reported above)
elif [ ! -d "$GIT_HOOKS_DIR" ]; then
    : # not a git repository (reported above)
elif [ -n "$DECLARED_HOOKS" ] && [ "$DECLARED_HOOKS" != "standards" ]; then
    echo "ℹ️  Worktree guard (refuses commits that add paths under $WORKTREE_DIR/) — add it to your $DECLARED_HOOKS hooks:"
    case "$DECLARED_HOOKS" in
        husky)    echo "   echo 'sh $GUARD_RELATIVE' >> .husky/pre-commit" ;;
        lefthook) echo "   merge the pre-commit block from $TEMPLATES_DIR/lefthook.yml.example into your lefthook config, then: lefthook install" ;;
        *)        echo "   run 'sh $GUARD_RELATIVE' from your pre-commit hook" ;;
    esac
elif [ -f "$GIT_HOOKS_DIR/pre-commit" ]; then
    if grep -q "standards-worktree-guard" "$GIT_HOOKS_DIR/pre-commit" 2>/dev/null; then
        echo "✅ Pre-commit worktree guard already installed"
    else
        echo "ℹ️  $GIT_HOOKS_DIR/pre-commit already exists — left as is. To add the worktree guard"
        echo "   (refuses commits that add paths under $WORKTREE_DIR/), call it from that hook:"
        echo "   sh $GUARD_RELATIVE"
    fi
elif [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] Would write: $GIT_HOOKS_DIR/pre-commit (worktree guard)"
else
    cp "$GUARD_TEMPLATE" "$GIT_HOOKS_DIR/pre-commit"
    chmod +x "$GIT_HOOKS_DIR/pre-commit"
    echo "✅ Pre-commit worktree guard installed (refuses commits that add paths under $WORKTREE_DIR/)"
fi

# Conventional Commits commit-msg hook templates — never auto-installed: the
# hook manager is a project decision, so setup only prints how to adopt one.
LEFTHOOK_CFG=""
for _lh in lefthook.yml lefthook.yaml .lefthook.yml .lefthook.yaml; do
    if [ -f "$PROJECT_ROOT/$_lh" ]; then
        LEFTHOOK_CFG="$_lh"
        break
    fi
done
if [ -f "$STANDARDS_DIR/templates/husky-commit-msg.example" ] \
   && [ ! -f "$PROJECT_ROOT/.husky/commit-msg" ]; then
    if [ -n "$LEFTHOOK_CFG" ]; then
        # Already on lefthook: do not suggest a second config file.
        if ! grep -qE '^commit-msg:' "$PROJECT_ROOT/$LEFTHOOK_CFG" 2>/dev/null; then
            echo "ℹ️  $LEFTHOOK_CFG has no commit-msg hook. Merge the commit-msg block from"
            echo "   $STANDARDS_DIR/templates/lefthook.yml.example into $LEFTHOOK_CFG, then: lefthook install"
        fi
    else
        echo "ℹ️  Conventional Commits commit-msg hook templates available (not auto-installed):"
        if [ -d "$PROJECT_ROOT/.husky" ]; then
            echo "   husky:    cp $STANDARDS_DIR/templates/husky-commit-msg.example .husky/commit-msg && chmod +x .husky/commit-msg"
        else
            echo "   husky:    npx husky init && cp $STANDARDS_DIR/templates/husky-commit-msg.example .husky/commit-msg && chmod +x .husky/commit-msg"
        fi
        echo "   lefthook: cp $STANDARDS_DIR/templates/lefthook.yml.example lefthook.yml && lefthook install"
        echo "   Note: squash-merge uses the PR title; the standards-review action checks it in CI."
    fi
fi

# Install standards review workflow template
if [ "$INSTALL_WORKFLOW" = true ] && [ -d "$STANDARDS_DIR/.github/actions/standards-review" ]; then
    if [ ! -f "$PROJECT_ROOT/.github/workflows/standards-review.yml" ]; then
        if [ -f "$STANDARDS_DIR/templates/standards-review.yml.example" ]; then
            dry_run_mkdir "$PROJECT_ROOT/.github/workflows"
            if [ "$DRY_RUN" = true ]; then
                echo "  [dry-run] Would copy: $STANDARDS_DIR/templates/standards-review.yml.example → $PROJECT_ROOT/.github/workflows/standards-review.yml"
            else
                cp "$STANDARDS_DIR/templates/standards-review.yml.example" "$PROJECT_ROOT/.github/workflows/standards-review.yml"
                echo "✅ Standards review workflow installed at .github/workflows/standards-review.yml"
            fi
        fi
    fi
elif [ -d "$STANDARDS_DIR/.github/actions/standards-review" ] && [ ! -f "$PROJECT_ROOT/.github/workflows/standards-review.yml" ]; then
    echo "ℹ️  standards-review workflow available. To install: ./setup.sh --workflow"
fi

# Install TruffleHog secret-scanning allowlist (never clobber an existing one)
if [ -f "$STANDARDS_DIR/templates/.trufflehog-ignore" ] && [ ! -f "$PROJECT_ROOT/.trufflehog-ignore" ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would copy: $STANDARDS_DIR/templates/.trufflehog-ignore → $PROJECT_ROOT/.trufflehog-ignore"
    else
        cp "$STANDARDS_DIR/templates/.trufflehog-ignore" "$PROJECT_ROOT/.trufflehog-ignore"
        echo "✅ TruffleHog allowlist installed at .trufflehog-ignore"
    fi
fi

# Install TruffleHog secret-scanning workflow (opt-in, like standards-review)
if [ "$INSTALL_WORKFLOW" = true ] && [ -f "$STANDARDS_DIR/templates/trufflehog.yml.example" ]; then
    if [ ! -f "$PROJECT_ROOT/.github/workflows/trufflehog.yml" ]; then
        dry_run_mkdir "$PROJECT_ROOT/.github/workflows"
        if [ "$DRY_RUN" = true ]; then
            echo "  [dry-run] Would copy: $STANDARDS_DIR/templates/trufflehog.yml.example → $PROJECT_ROOT/.github/workflows/trufflehog.yml"
        else
            cp "$STANDARDS_DIR/templates/trufflehog.yml.example" "$PROJECT_ROOT/.github/workflows/trufflehog.yml"
            echo "✅ TruffleHog secret-scan workflow installed at .github/workflows/trufflehog.yml"
        fi
    fi
elif [ -f "$STANDARDS_DIR/templates/trufflehog.yml.example" ] && [ ! -f "$PROJECT_ROOT/.github/workflows/trufflehog.yml" ]; then
    echo "ℹ️  TruffleHog secret-scan workflow available. To install: ./setup.sh --workflow"
fi

# Set up git aliases (global configuration; skipped when --agents names an explicit list)
if ! install_git_extras; then
    echo "ℹ️  Skipping global git aliases (explicit --agents). Run scripts/setup-git-aliases.sh to install them."
elif command -v git >/dev/null 2>&1; then
    # Determine path to setup-git-aliases.sh
    if [ "$SCRIPT_DIR" = "$PROJECT_ROOT" ]; then
        # We're in the standards repo itself
        GIT_ALIASES_SCRIPT="$SCRIPT_DIR/setup-git-aliases.sh"
    else
        # We're in a project using standards
        if [ -d "$STANDARDS_DIR" ]; then
            GIT_ALIASES_SCRIPT="$STANDARDS_DIR/scripts/setup-git-aliases.sh"
        elif [ -f "$SCRIPT_DIR/setup-git-aliases.sh" ]; then
            GIT_ALIASES_SCRIPT="$SCRIPT_DIR/setup-git-aliases.sh"
        else
            GIT_ALIASES_SCRIPT=""
        fi
    fi

    if [ -n "$GIT_ALIASES_SCRIPT" ] && [ -f "$GIT_ALIASES_SCRIPT" ]; then
        if [ "$DRY_RUN" = true ]; then
            echo ""
            echo "  [dry-run] Would set up git aliases and configuration"
        else
            echo ""
            echo "🔧 Setting up git aliases and configuration..."
            echo "   (This configures global git settings and aliases for your system)"
            if bash "$GIT_ALIASES_SCRIPT"; then
                echo "✅ Git aliases and configuration set up"
            else
                echo "⚠️  Git setup had issues (non-fatal, continuing...)"
            fi
        fi
    fi
else
    echo "⚠️  Git not found. Skipping git aliases setup."
fi

# Create .gitignore entries if needed
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if ! grep -q ".cursorrules.backup" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ".cursorrules.backup"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
    fi
    if ! grep -q ".standards_tmp" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Standards temporary files"
            echo ".standards_tmp/"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
    fi
    if ! grep -q "coverage/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Test coverage output"
            echo "coverage/"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
    fi
    if ! grep -q ".pre-standards-setup" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo "*.pre-standards-setup"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
    fi
    # Note: .standards.yml should be committed (not gitignored) — it is the project's declared config.
    # Remove legacy .standards-config from gitignore if present (it was previously gitignored).
    if [ "$DRY_RUN" = false ] && grep -q "^\.standards-config$" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        tmp_gitignore="${PROJECT_ROOT}/.gitignore.tmp.$$"
        if sed '/^\.standards-config$/d' "$PROJECT_ROOT/.gitignore" > "$tmp_gitignore" 2>/dev/null; then
            mv "$tmp_gitignore" "$PROJECT_ROOT/.gitignore"
        else
            rm -f "$tmp_gitignore"
        fi
    fi
    if ! grep -q ".standards-pending" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ".standards-pending/"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
    fi
    # Agent worktree root (proc-04 § Worktree Hygiene): ignored so a worktree
    # can never be committed and the linter never walks it.
    if ! worktree_root_ignored "$PROJECT_ROOT/.gitignore" "$WORKTREE_DIR"; then
        {
            echo ""
            echo "# Agent worktree root (proc-04 Worktree Hygiene; worktree_dir: in .standards.yml)"
            echo "$WORKTREE_DIR/"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
        if [ "$DRY_RUN" = false ]; then
            echo "✅ Worktree root $WORKTREE_DIR/ added to .gitignore"
        fi
    fi
elif [ "$SCRIPT_DIR" != "$PROJECT_ROOT" ]; then
    # Create .gitignore if it doesn't exist (only for client projects, not standards repo itself)
    {
        echo "# Test coverage output"
        echo "coverage/"
        echo ""
        echo "# Standards temporary files"
        echo ".standards_tmp/"
        echo ".standards-pending/"
        echo ""
        echo "# Backup files"
        echo ".cursorrules.backup"
        echo "*.pre-standards-setup"
        echo ""
        echo "# Agent worktree root (proc-04 Worktree Hygiene; worktree_dir: in .standards.yml)"
        echo "$WORKTREE_DIR/"
        echo ""
        echo "# Note: .standards.yml should be committed — it is the project's declared config."
    } | dry_run_write "$PROJECT_ROOT/.gitignore"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "🔧 GitHub Project Lifecycle Automation:"
echo ""
echo "To use the gh-task CLI tool:"
echo "1. Symlink to your PATH:"
echo "   mkdir -p bin && ln -s $STANDARDS_DIR/bin/gh-task bin/gh-task"
echo "2. Configure your project:"
echo "   mkdir -p .gemini"
echo "   cp $STANDARDS_DIR/templates/settings.json.example .gemini/settings.json"
echo "   # Edit .gemini/settings.json with your PROJECT_ID"
echo "3. See documentation:"
echo "   - Complete guide: $STANDARDS_DIR/docs/GH_TASK_GUIDE.md"
echo "   - AI agent guide: $STANDARDS_DIR/docs/TOOLING.md"
echo ""
echo "Next steps:"
echo "1. Fully quit and restart Cursor to load .cursorrules and custom commands"
echo "2. If using GitHub Copilot, restart your IDE to load .github/copilot-instructions.md"
echo "3. If using Aider, it will automatically use .aiderrc and .aider-instructions.md"
echo "4. If using Codex, it will read AGENTS.md in the project root"
echo "5. If using Claude Code, customize CLAUDE.md with your project details"
echo "6. If using Gemini CLI, it will automatically use .gemini/GEMINI.md and .gemini/settings.json"
echo "7. If using submodule, ensure it's initialized: git submodule update --init"
echo "8. To sync standards later, run from the project root: ./.standards/scripts/sync-standards.sh"
echo "   Note: After syncing, fully restart your IDE again to load updated configurations"
echo "9. Agent worktrees go under $WORKTREE_DIR/ (one gitignored root, never nested); collect finished"
echo "   ones with: ./.standards/scripts/worktree-gc.sh  (--dry-run to preview)"
