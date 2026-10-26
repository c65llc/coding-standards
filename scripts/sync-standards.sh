#!/bin/bash
# Sync script to update standards in existing projects
#
# Usage:
#   ./.standards/scripts/sync-standards.sh [--dry-run] [--aliases]
#
# Run it from the project root. Every side effect is gated on the agents
# declared in .standards.yml (`agents:`): Cursor commands only for `cursor`,
# .gemini/settings.json only for `gemini`, .claude/ extras only for
# `claude-code`, and so on.
#
# Options:
#   --dry-run   Print every write that would happen; modify nothing.
#   --aliases   Also run setup-git-aliases.sh (changes *global* git config).
#               Off by default — a project sync never touches your git config.
#   -h, --help  Show this help.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Parse arguments
DRY_RUN=false
SETUP_ALIASES=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --aliases)
            SETUP_ALIASES=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run '$0 --help' for usage." >&2
            exit 2
            ;;
    esac
done

# Refuse to run from inside the .standards/ submodule (see lib/guard.sh).
# shellcheck source=lib/guard.sh disable=SC1091
source "$SCRIPT_DIR/lib/guard.sh"
refuse_if_inside_standards_dir "$PROJECT_ROOT" "sync-standards.sh" || exit 2

# Dry-run aware file operations (shared: scripts/lib/dry-run.sh)
# shellcheck source=lib/dry-run.sh disable=SC1091
source "$SCRIPT_DIR/lib/dry-run.sh"

if [ "$DRY_RUN" = true ]; then
    echo "🔍 DRY RUN — showing what would change (no files modified)"
    echo ""
fi

# Source checksum helpers
CHECKSUMS_LIB=""
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    CHECKSUMS_LIB="$SCRIPT_DIR/lib/checksums.sh"
elif [ -n "$STANDARDS_DIR" ] && [ -f "$STANDARDS_DIR/scripts/lib/checksums.sh" ]; then
    CHECKSUMS_LIB="$STANDARDS_DIR/scripts/lib/checksums.sh"
fi
if [ -n "$CHECKSUMS_LIB" ]; then
    # shellcheck disable=SC1090,SC1091
    source "$CHECKSUMS_LIB"
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

# Filled-in Project Overview / Key Commands capture (#183)
if [ -f "$SCRIPT_DIR/lib/project-sections.sh" ]; then
    # shellcheck source=lib/project-sections.sh disable=SC1091
    source "$SCRIPT_DIR/lib/project-sections.sh"
fi

# Pre-1.2 shape detection (#184): a consumer with no checksums and configs
# citing renamed standards paths is told to run setup.sh --migrate, because a
# sync alone skips every such file as "manually created" and fixes nothing.
if [ -f "$SCRIPT_DIR/lib/migrate.sh" ]; then
    # shellcheck source=lib/migrate.sh disable=SC1091
    source "$SCRIPT_DIR/lib/migrate.sh"
fi
# .aiderrc refresh that keeps the project's `model =` line (install_aiderrc in
# lib/migrate.sh); a plain copy when the lib is not shipped.
_sync_install_aiderrc() {
    if declare -f install_aiderrc >/dev/null 2>&1; then
        install_aiderrc "$1" "$2"
    else
        cp "$1" "$2"
    fi
}

# Function to sync AI agent configurations
sync_ai_agents() {
    local STANDARDS_DIR="$1"
    local SCRIPT_DIR="$2"
    local PROJECT_ROOT="$3"

    local AGENTS_DIR=""
    if [ -d "$STANDARDS_DIR/standards/agents" ]; then
        AGENTS_DIR="$STANDARDS_DIR/standards/agents"
    elif [ -d "$SCRIPT_DIR/../standards/agents" ]; then
        AGENTS_DIR="$SCRIPT_DIR/../standards/agents"
    else
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
        echo "⚠️  assemble-config.sh not found, cannot sync agent configs"
        return
    fi

    # ROLE, DETECTED_LANGS and AGENTS_LIST are read once at top level (from
    # .standards.yml) so that every side effect in this script shares one view
    # of the declared agents.

    # Build block arguments: language blocks + role block
    # shellcheck disable=SC2086
    local LANG_BLOCKS
    LANG_BLOCKS=$(map_languages_to_blocks "$DETECTED_LANGS")
    local ROLE_BLOCK="role-${ROLE}.md"

    local BLOCK_ARGS=()
    for b in $LANG_BLOCKS; do
        BLOCK_ARGS+=("$b")
    done
    if [ -f "$BLOCKS_DIR/$ROLE_BLOCK" ]; then
        BLOCK_ARGS+=("$ROLE_BLOCK")
    fi
    # Profile blocks (#227): after the role block, in declared order. A block
    # the pinned standards do not ship yet is skipped with a warning.
    local pb
    for pb in $(map_profiles_to_blocks "$PROFILES"); do
        if [ -f "$BLOCKS_DIR/$pb" ]; then
            BLOCK_ARGS+=("$pb")
        else
            echo "⚠️  profile block $pb not found; skipping" >&2
        fi
    done

    # Checksum accumulator for tracking assembled file hashes
    local CHECKSUMS_PATH="$PROJECT_ROOT/$CHECKSUMS_FILE"
    local NEW_CHECKSUMS=""
    if [ -f "$CHECKSUMS_PATH" ]; then
        NEW_CHECKSUMS=$(cat "$CHECKSUMS_PATH")
    fi

    # Re-assemble each agent config
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

        # Checksum-guarded assembly: skip customized files, stage pending updates
        local rc=0
        assemble_agent_config_guarded \
            "$agent" "$ASSEMBLE_SCRIPT" "$BLOCKS_DIR" "$BASE_TEMPLATE" \
            "$OUTPUT_PATH" "$CHECKSUMS_PATH" "$DRY_RUN" \
            ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"} || rc=$?

        case "$rc" in
            0)
                echo "✅ $agent config synced"
                if [ "$DRY_RUN" = false ]; then
                    local new_hash
                    new_hash=$(compute_hash "$OUTPUT_PATH")
                    NEW_CHECKSUMS=$(update_checksum_entry "$(basename "$OUTPUT_PATH")" "$new_hash" "$NEW_CHECKSUMS")
                fi
                ;;
            1)
                echo "⚠️  $agent config customized — update staged to $PENDING_DIR/"
                # Filled-in overview/commands that .standards.yml does not persist
                # are the usual reason a config can never match its checksum (#183).
                if declare -f print_capture_hint >/dev/null 2>&1; then
                    print_capture_hint "$PROJECT_ROOT" "$OUTPUT_PATH" "${OUTPUT_PATH#"$PROJECT_ROOT"/}" || true
                fi
                ;;
            2) echo "⚠️  $agent config was manually created — skipping, backup in $PENDING_DIR/" ;;
            3) echo "⚠️  Failed to sync $agent config (non-fatal, continuing...)" ;;
            4)
                echo "ℹ️  $agent config is curated (managed: false in .standards.yml) — not regenerated."
                echo "   Review upstream template changes with diff-standards.sh."
                # Keep a checksum baseline for the curated file (see setup.sh).
                if [ "$DRY_RUN" = false ] && [ -f "$OUTPUT_PATH" ]; then
                    local curated_hash
                    curated_hash=$(compute_hash "$OUTPUT_PATH")
                    NEW_CHECKSUMS=$(update_checksum_entry "$(basename "$OUTPUT_PATH")" "$curated_hash" "$NEW_CHECKSUMS")
                fi
                ;;
        esac

        # Aider special handling: also sync aiderrc.template to .aiderrc
        if [ "$agent" = "aider" ] && [ -f "$AGENTS_DIR/aider/aiderrc.template" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "  [dry-run] Would sync: $AGENTS_DIR/aider/aiderrc.template → $PROJECT_ROOT/.aiderrc"
            elif [ -n "$CHECKSUMS_LIB" ]; then
                # Checksum-protected: compare full-file hash
                local stored_rc_hash
                stored_rc_hash=$(read_stored_hash ".aiderrc" "$CHECKSUMS_PATH")
                local current_rc_hash=""
                if [ -f "$PROJECT_ROOT/.aiderrc" ]; then
                    current_rc_hash=$(shasum -a 256 "$PROJECT_ROOT/.aiderrc" | awk '{print $1}')
                fi

                if [ ! -f "$PROJECT_ROOT/.aiderrc" ] || [ -z "$stored_rc_hash" ] || [ "$current_rc_hash" = "$stored_rc_hash" ]; then
                    # The project's own `model =` line is carried forward
                    # (install_aiderrc, lib/migrate.sh): the template no
                    # longer pins a model and a sync never changes it (#184).
                    if _sync_install_aiderrc "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                        echo "   ✅ Aider .aiderrc synced"
                        local new_rc_hash
                        new_rc_hash=$(shasum -a 256 "$PROJECT_ROOT/.aiderrc" | awk '{print $1}')
                        NEW_CHECKSUMS=$(update_checksum_entry ".aiderrc" "$new_rc_hash" "$NEW_CHECKSUMS")
                    fi
                else
                    echo "   ⚠️  Aider .aiderrc customized — skipping"
                fi
            else
                # Fallback: no checksum library
                if ! cmp -s "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                    if _sync_install_aiderrc "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                        echo "   ✅ Aider .aiderrc synced"
                    fi
                fi
            fi
        fi
    done

    # Write accumulated checksums atomically
    if [ "$DRY_RUN" = false ] && [ -n "$CHECKSUMS_LIB" ] && [ -n "$NEW_CHECKSUMS" ]; then
        echo "$NEW_CHECKSUMS" > "$CHECKSUMS_PATH"
    fi

    # Skills (#194): standards/skills/*.md emitted per declared agent — Claude
    # Code skill files, Cursor commands, Copilot prompt files. Codex, Gemini
    # and Aider carry a "## Skills" index in their assembled config instead.
    # assemble-skills.sh rewrites a file only when its content changed.
    local SKILLS_SCRIPT="" SKILLS_SOURCE="" skill_agents="" a
    if [ -x "$SCRIPT_DIR/assemble-skills.sh" ]; then
        SKILLS_SCRIPT="$SCRIPT_DIR/assemble-skills.sh"
    elif [ -x "$STANDARDS_DIR/scripts/assemble-skills.sh" ]; then
        SKILLS_SCRIPT="$STANDARDS_DIR/scripts/assemble-skills.sh"
    fi
    if [ -d "$STANDARDS_DIR/standards/skills" ]; then
        SKILLS_SOURCE="$STANDARDS_DIR/standards/skills"
    elif [ -d "$SCRIPT_DIR/../standards/skills" ]; then
        SKILLS_SOURCE="$SCRIPT_DIR/../standards/skills"
    fi
    for a in claude-code cursor copilot; do
        agent_enabled "$a" && skill_agents="${skill_agents:+$skill_agents }$a"
    done
    if [ -n "$SKILLS_SCRIPT" ] && [ -n "$SKILLS_SOURCE" ] && [ -n "$skill_agents" ]; then
        local dry_flag=""
        [ "$DRY_RUN" = true ] && dry_flag="--dry-run"
        # shellcheck disable=SC2086
        if ! "$SKILLS_SCRIPT" --project-root "$PROJECT_ROOT" --skills-dir "$SKILLS_SOURCE" --profiles "$PROFILES" --quiet $dry_flag $skill_agents; then
            echo "⚠️  Failed to sync some skills (non-fatal, continuing...)"
        fi
    fi

    # Add .standards-pending/ to .gitignore if not already present
    if [ -f "$PROJECT_ROOT/.gitignore" ] && ! grep -q ".standards-pending" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ".standards-pending/"
        } | dry_run_append "$PROJECT_ROOT/.gitignore"
    fi

    # Codex: deprecation warning for old .codexrc
    if [ -f "$PROJECT_ROOT/.codexrc" ]; then
        echo "⚠️  .codexrc is deprecated. Codex now uses AGENTS.md."
        echo "   Your .codexrc has been preserved. Remove it when ready."
    fi

    # Claude Code settings.json (claude-code only; only create if missing)
    if agent_enabled claude-code && [ ! -f "$PROJECT_ROOT/.claude/settings.json" ]; then
        if [ -f "$AGENTS_DIR/claude-code/settings.json.example" ]; then
            if [ "$DRY_RUN" = true ]; then
                dry_run_mkdir "$PROJECT_ROOT/.claude"
                echo "  [dry-run] Would write: $PROJECT_ROOT/.claude/settings.json"
            else
                echo "📝 Adding Claude Code settings..."
                mkdir -p "$PROJECT_ROOT/.claude"
                local BUILD_SCRIPT=""
                local DETECT_SCRIPT=""
                if [ -n "$STANDARDS_DIR" ]; then
                    DETECT_SCRIPT="$STANDARDS_DIR/scripts/detect-languages.sh"
                    BUILD_SCRIPT="$STANDARDS_DIR/scripts/build-claude-settings.sh"
                fi
                [ ! -x "$DETECT_SCRIPT" ] && DETECT_SCRIPT="$SCRIPT_DIR/detect-languages.sh"
                [ ! -x "$BUILD_SCRIPT" ] && BUILD_SCRIPT="$SCRIPT_DIR/build-claude-settings.sh"

                local BASE_SETTINGS="$AGENTS_DIR/claude-code/settings.json.example"
                local PERMS_DIR="$AGENTS_DIR/claude-code/permissions"

                if [ -x "$DETECT_SCRIPT" ] && [ -x "$BUILD_SCRIPT" ] && [ -d "$PERMS_DIR" ]; then
                    local SETTINGS_LANGS="$DETECTED_LANGS"
                    if [ -z "$SETTINGS_LANGS" ]; then
                        SETTINGS_LANGS=$("$DETECT_SCRIPT" "$PROJECT_ROOT")
                    fi
                    if [ -n "$SETTINGS_LANGS" ]; then
                        # shellcheck disable=SC2086
                        if "$BUILD_SCRIPT" "$BASE_SETTINGS" "$PERMS_DIR" $SETTINGS_LANGS > "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null; then
                            echo "✅ Claude Code settings added at .claude/settings.json"
                            # shellcheck disable=SC2086
                            echo "   Detected languages: $(echo $SETTINGS_LANGS | tr '\n' ' ')"
                        else
                            cp "$BASE_SETTINGS" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
                            echo "✅ Claude Code settings added at .claude/settings.json (base template)"
                        fi
                    else
                        cp "$BASE_SETTINGS" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
                        echo "✅ Claude Code settings added at .claude/settings.json"
                    fi
                else
                    cp "$BASE_SETTINGS" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null
                    echo "✅ Claude Code settings added at .claude/settings.json"
                fi
            fi
        fi
    fi

    # Sync language-specific tool configs (only if language detected and file differs)
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
                                echo "   ✅ Added $config_name ($lang)"
                            fi
                        elif ! cmp -s "$config_file" "$PROJECT_ROOT/$config_name" 2>/dev/null; then
                            if [ "$UPDATED" = true ]; then
                                if [ "$DRY_RUN" = true ]; then
                                    echo "  [dry-run] Would update: $PROJECT_ROOT/$config_name"
                                elif cp "$config_file" "$PROJECT_ROOT/$config_name" 2>/dev/null; then
                                    echo "   ✅ Updated $config_name ($lang)"
                                fi
                            fi
                        fi
                    done
                )
            fi
        done
    fi

    # Sync Gemini settings.json (gemini only; separate from the assembled GEMINI.md)
    local GEMINI_SOURCE=""
    if [ -n "$STANDARDS_DIR" ] && [ -d "$STANDARDS_DIR/.gemini" ]; then
        GEMINI_SOURCE="$STANDARDS_DIR/.gemini"
    elif [ -d "$SCRIPT_DIR/../.gemini" ]; then
        GEMINI_SOURCE="$SCRIPT_DIR/../.gemini"
    fi

    if agent_enabled gemini && [ -n "$GEMINI_SOURCE" ] && [ -f "$GEMINI_SOURCE/settings.json" ]; then
        dry_run_mkdir "$PROJECT_ROOT/.gemini"
        # Validate JSON syntax before copying
        local JSON_VALID=true
        if command -v python3 >/dev/null 2>&1; then
            if ! python3 -m json.tool "$GEMINI_SOURCE/settings.json" >/dev/null 2>&1; then
                echo "⚠️  Invalid JSON in Gemini settings.json, skipping update..."
                JSON_VALID=false
            fi
        elif command -v jq >/dev/null 2>&1; then
            if ! jq empty "$GEMINI_SOURCE/settings.json" >/dev/null 2>&1; then
                echo "⚠️  Invalid JSON in Gemini settings.json, skipping update..."
                JSON_VALID=false
            fi
        fi

        if [ "$JSON_VALID" = true ]; then
            if [ ! -f "$PROJECT_ROOT/.gemini/settings.json" ]; then
                if [ "$DRY_RUN" = true ]; then
                    echo "  [dry-run] Would create: $PROJECT_ROOT/.gemini/settings.json"
                else
                    echo "📝 Adding Gemini CLI settings (not yet configured)..."
                    if cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                        echo "✅ Gemini CLI settings added at .gemini/settings.json"
                    fi
                fi
            elif [ "$UPDATED" = true ] || ! cmp -s "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                if [ "$DRY_RUN" = true ]; then
                    echo "  [dry-run] Would update: $PROJECT_ROOT/.gemini/settings.json"
                else
                    echo "📝 Updating Gemini CLI settings..."
                    if cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                        echo "✅ Gemini CLI settings updated"
                    fi
                fi
            fi
        fi
    fi
}

echo "🔄 Syncing project standards..."

# Determine standards location
# Profiles (#227): validate the declared list before the submodule pull, the
# first side effect of this script, so an unknown name changes nothing.
if declare -f read_standards_config >/dev/null 2>&1 && read_standards_config "$PROJECT_ROOT" 2>/dev/null; then
    for _p in ${STD_PROFILES:-}; do
        if ! profile_supported "$_p"; then
            echo "ERROR: Unknown profile: $_p (expected one of: ${SUPPORTED_PROFILES// /, })" >&2
            exit 2
        fi
    done
    unset _p
fi
# Validate member declarations before fetching or pulling the submodule too.
aggregate_member_profiles "$PROJECT_ROOT" "${STD_PROFILES:-}" "$(resolve_members "$PROJECT_ROOT")" >/dev/null || exit 2

STANDARDS_DIR=""

if [ -d "$PROJECT_ROOT/.standards" ]; then
    STANDARDS_DIR="$PROJECT_ROOT/.standards"
    echo "📋 Found standards submodule at .standards"

    # Update submodule
    cd "$STANDARDS_DIR"
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would fetch and pull .standards/ submodule"
        UPDATED=true  # Assume updates for preview purposes
    else
        LOCAL=$(git rev-parse HEAD 2>/dev/null || true)
        REMOTE=""
        if git fetch origin >/dev/null 2>&1; then
            # --verify --quiet: print nothing (rather than the literal ref name)
            # when the ref does not exist, so REMOTE stays empty and we fall through.
            REMOTE=$(git rev-parse --verify --quiet origin/main 2>/dev/null \
                || git rev-parse --verify --quiet origin/master 2>/dev/null || true)
        else
            # Leave REMOTE empty: a cached origin/main that differs from HEAD
            # would otherwise send us into a pull against the same unreachable
            # remote, which dies under set -e before any config is assembled.
            echo "⚠️  Could not fetch standards remote (offline?) — syncing from the local checkout"
        fi

        if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
            echo "📥 Pulling latest standards..."
            git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
            UPDATED=true
        else
            echo "✅ Standards are up to date"
            UPDATED=false
        fi
    fi
    cd "$PROJECT_ROOT"
elif [ -d "$SCRIPT_DIR/../standards" ]; then
    # Standards are in script directory (standards repo itself)
    STANDARDS_DIR="$SCRIPT_DIR/.."
    echo "📋 Using standards from script location"
    UPDATED=false
else
    echo "❌ Error: Could not find standards directory"
    exit 1
fi

# ---------------------------------------------------------------------------
# Read project configuration once (.standards.yml or legacy .standards-config).
# Every side effect below is gated on the declared agents list.
# ---------------------------------------------------------------------------

ROLE="service"
DETECTED_LANGS=""
AGENTS_LIST=""
PROFILES=""

if declare -f read_standards_config >/dev/null 2>&1 && read_standards_config "$PROJECT_ROOT"; then
    ROLE="${STD_ROLE:-service}"
    DETECTED_LANGS="${STD_LANGUAGES:-}"
    AGENTS_LIST="${STD_AGENTS:-}"
    PROFILES="${STD_PROFILES:-}"
else
    echo "⚠️  No .standards.yml or .standards-config found. Running auto-detection (default role: service)."
fi

# Monorepo members (#179): declared in the root .standards.yml or
# auto-discovered. The root agent configs are assembled from the union of the
# root's languages and every member's, so an agent that only reads the root
# file (Cursor, Copilot, Aider) still sees each member's language rules.
MEMBERS=$(resolve_members "$PROJECT_ROOT" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
while IFS= read -r rejected; do
    [ -z "$rejected" ] && continue
    echo "⚠️  members: $rejected"
done <<EOF
$(rejected_members "$PROJECT_ROOT" 2>/dev/null)
EOF

# Same union as setup.sh: the root's languages (declared, else detected from
# the root's own manifests), plus the conventional sub-roots that are not
# members (lib/members.sh subroot_languages), plus every member below.
if [ -x "$SCRIPT_DIR/detect-languages.sh" ]; then
    if [ -z "$DETECTED_LANGS" ]; then
        DETECTED_LANGS=$("$SCRIPT_DIR/detect-languages.sh" --root-only "$PROJECT_ROOT")
    fi
    DETECTED_LANGS=$(dedupe_words "$DETECTED_LANGS" "$(subroot_languages "$PROJECT_ROOT" "$MEMBERS" "$SCRIPT_DIR/detect-languages.sh")")
fi

if [ -n "$MEMBERS" ]; then
    echo "📦 Members:"
    for m in $MEMBERS; do
        if problem=$(member_problem "$PROJECT_ROOT" "$m"); then
            echo "   - $m ($(member_languages "$PROJECT_ROOT" "$m" "$SCRIPT_DIR/detect-languages.sh" "$MEMBERS"))"
        else
            echo "   ⚠️  $m: $problem"
            if [ -d "$PROJECT_ROOT/$m" ]; then
                echo "        languages detected: $(member_languages "$PROJECT_ROOT" "$m" "$SCRIPT_DIR/detect-languages.sh" "$MEMBERS")"
            fi
        fi
    done
    DETECTED_LANGS=$(aggregate_member_languages "$PROJECT_ROOT" "$DETECTED_LANGS" "$MEMBERS" "$SCRIPT_DIR/detect-languages.sh")
    echo "🧩 Languages across root and members: ${DETECTED_LANGS:-(none)}"
fi

# Declared profiles (#227) reach assemble-config.sh through the environment
# so the guarded assembler's positional contract stays untouched.
PROFILES=$(aggregate_member_profiles "$PROJECT_ROOT" "$PROFILES" "$MEMBERS") || exit 2
export STANDARDS_PROFILES="$PROFILES"

# Default agents list if not in config
if [ -z "$AGENTS_LIST" ]; then
    AGENTS_LIST="claude-code cursor copilot gemini codex aider"
fi

# agent_enabled <name> — true when <name> is in the declared agents list.
agent_enabled() {
    case " $AGENTS_LIST " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

echo "🤖 Declared agents: $AGENTS_LIST"

# Update Cursor custom commands if they exist (cursor only)
if [ -d "$STANDARDS_DIR/.cursor/commands" ]; then
    CURSOR_COMMANDS_SOURCE="$STANDARDS_DIR/.cursor/commands"
elif [ -d "$SCRIPT_DIR/../.cursor/commands" ]; then
    CURSOR_COMMANDS_SOURCE="$SCRIPT_DIR/../.cursor/commands"
else
    CURSOR_COMMANDS_SOURCE=""
fi

if agent_enabled cursor && [ -n "$CURSOR_COMMANDS_SOURCE" ] && [ -d "$CURSOR_COMMANDS_SOURCE" ]; then
    echo "📝 Syncing Cursor custom commands..."
    dry_run_mkdir "$PROJECT_ROOT/.cursor/commands"
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would copy: $CURSOR_COMMANDS_SOURCE/* → $PROJECT_ROOT/.cursor/commands/"
    elif cp -r "$CURSOR_COMMANDS_SOURCE"/* "$PROJECT_ROOT/.cursor/commands/" 2>/dev/null; then
        echo "✅ Cursor commands synced"
        echo "⚠️  Please fully quit and restart Cursor to load new commands"
    else
        echo "⚠️  Failed to sync Cursor commands (non-fatal, continuing...)"
    fi
fi

# Pre-1.2 install (#184): point at the migration before the per-file skips.
if declare -f pre12_shape >/dev/null 2>&1; then
    PRE12_MAP=$(rename_map_path "$STANDARDS_DIR" "$SCRIPT_DIR") || PRE12_MAP=""
    if PRE12_REASONS=$(pre12_shape "$PROJECT_ROOT" "$PRE12_MAP") && [ -n "$PRE12_REASONS" ]; then
        echo ""
        echo "⚠️  Pre-1.2 install detected — a sync skips these files as manually created and fixes nothing:"
        echo "$PRE12_REASONS" | sed 's/^/   - /'
        echo "   Run: .standards/scripts/setup.sh --migrate  (rewrites the dead references, converts .codexrc, bootstraps .standards.yml and checksums)"
    fi
fi

# Sync multi-agent configurations
echo ""
echo "🤖 Syncing AI agent configurations..."
sync_ai_agents "$STANDARDS_DIR" "$SCRIPT_DIR" "$PROJECT_ROOT"

# Git aliases are opt-in (--aliases). They change *global* git config, which a
# project sync must never do on its own.
if [ "$SETUP_ALIASES" = true ]; then
    if [ -f "$STANDARDS_DIR/scripts/setup-git-aliases.sh" ]; then
        GIT_ALIASES_SCRIPT="$STANDARDS_DIR/scripts/setup-git-aliases.sh"
    elif [ -f "$SCRIPT_DIR/setup-git-aliases.sh" ]; then
        GIT_ALIASES_SCRIPT="$SCRIPT_DIR/setup-git-aliases.sh"
    else
        GIT_ALIASES_SCRIPT=""
    fi

    if [ -n "$GIT_ALIASES_SCRIPT" ] && command -v git >/dev/null 2>&1; then
        if [ "$DRY_RUN" = true ]; then
            echo ""
            echo "  [dry-run] Would set up git aliases and configuration (--aliases)"
        else
            echo ""
            echo "🔧 Setting up git aliases and configuration (--aliases)..."
            if bash "$GIT_ALIASES_SCRIPT" 2>/dev/null; then
                echo "✅ Git aliases checked/updated"
            else
                echo "⚠️  Git aliases update had issues (non-fatal, continuing...)"
            fi
        fi
    else
        echo "⚠️  --aliases requested but setup-git-aliases.sh (or git) not found — skipping"
    fi
else
    echo ""
    echo "ℹ️  Git aliases not changed (opt in with --aliases)"
fi

# Check for new standards files
if [ -d "$STANDARDS_DIR" ] || [ "$SCRIPT_DIR" = "$PROJECT_ROOT" ]; then
    STANDARDS_FILES_DIR="${STANDARDS_DIR:-$SCRIPT_DIR/..}"

    echo ""
    echo "📚 Available standards files:"
    find "$STANDARDS_FILES_DIR/standards" -name "*.md" 2>/dev/null | while read -r file; do
        basename "$file"
    done | head -10
    echo "..."
fi

echo ""
echo "✅ Sync complete!"
echo ""
echo "Note: Restart your IDE/editor to load updated AI agent configurations"
