#!/bin/bash
# Sync script to update standards in existing projects

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Parse arguments
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Dry-run aware file operations
dry_run_cp() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would copy: $1 → $2"
    else
        cp "$1" "$2"
    fi
}

dry_run_mkdir() {
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would create directory: $1"
    else
        mkdir -p "$1"
    fi
}

dry_run_write() {
    local target="$1"
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would write: $target"
        cat > /dev/null
    else
        cat > "$target"
    fi
}

dry_run_append() {
    local target="$1"
    if [ "$DRY_RUN" = true ]; then
        echo "  [dry-run] Would append to: $target"
        cat > /dev/null
    else
        cat >> "$target"
    fi
}

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

# Map detected languages to block filenames (shared with setup.sh)
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
        esac
    done
    # Deduplicate and output
    printf '%s\n' "${BLOCKS[@]}" | sort -u | tr '\n' ' '
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

    # Read project configuration (.standards.yml or legacy .standards-config)
    local ROLE="service"
    local DETECTED_LANGS=""
    local AGENTS_LIST=""

    if ! read_standards_config "$PROJECT_ROOT"; then
        echo "⚠️  No .standards.yml or .standards-config found. Running auto-detection (default role: service)."
        STD_ROLE="service"
        STD_LANGUAGES=""
        STD_AGENTS=""
    fi
    ROLE="$STD_ROLE"
    DETECTED_LANGS="$STD_LANGUAGES"
    AGENTS_LIST="$STD_AGENTS"

    # If no languages from config, try auto-detection
    if [ -z "$DETECTED_LANGS" ]; then
        local DETECT_SCRIPT="$SCRIPT_DIR/detect-languages.sh"
        if [ -x "$DETECT_SCRIPT" ]; then
            DETECTED_LANGS=$("$DETECT_SCRIPT" "$PROJECT_ROOT")
        fi
    fi

    # Default agents list if not in config
    if [ -z "$AGENTS_LIST" ]; then
        AGENTS_LIST="claude-code cursor copilot gemini codex aider"
    fi

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
            1) echo "⚠️  $agent config customized — update staged to $PENDING_DIR/" ;;
            2) echo "⚠️  $agent config was manually created — skipping, backup in $PENDING_DIR/" ;;
            3) echo "⚠️  Failed to sync $agent config (non-fatal, continuing...)" ;;
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
                    if cp "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
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
                    if cp "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
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

    # Copy merge-standards skill if it exists and has changed
    local SKILL_SOURCE="$AGENTS_DIR/claude-code/skills/merge-standards.md"
    if [ -f "$SKILL_SOURCE" ]; then
        dry_run_mkdir "$PROJECT_ROOT/.claude/skills"
        if [ "$DRY_RUN" = true ]; then
            if ! cmp -s "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md" 2>/dev/null; then
                echo "  [dry-run] Would sync: $SKILL_SOURCE → $PROJECT_ROOT/.claude/skills/merge-standards.md"
            fi
        elif ! cmp -s "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md" 2>/dev/null; then
            cp "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md"
            echo "✅ /merge-standards skill synced"
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

    # Claude Code settings.json (only create if missing)
    if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ]; then
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

    # Sync Gemini settings.json (separate from GEMINI.md which is now assembled)
    local GEMINI_SOURCE=""
    if [ -n "$STANDARDS_DIR" ] && [ -d "$STANDARDS_DIR/.gemini" ]; then
        GEMINI_SOURCE="$STANDARDS_DIR/.gemini"
    elif [ -d "$SCRIPT_DIR/../.gemini" ]; then
        GEMINI_SOURCE="$SCRIPT_DIR/../.gemini"
    fi

    if [ -n "$GEMINI_SOURCE" ] && [ -f "$GEMINI_SOURCE/settings.json" ]; then
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
        LOCAL=$(git rev-parse HEAD)
        git fetch origin >/dev/null 2>&1
        REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)

        if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
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

# Update Cursor custom commands if they exist
if [ -d "$STANDARDS_DIR/.cursor/commands" ]; then
    CURSOR_COMMANDS_SOURCE="$STANDARDS_DIR/.cursor/commands"
elif [ -d "$SCRIPT_DIR/../.cursor/commands" ]; then
    CURSOR_COMMANDS_SOURCE="$SCRIPT_DIR/../.cursor/commands"
else
    CURSOR_COMMANDS_SOURCE=""
fi

if [ -n "$CURSOR_COMMANDS_SOURCE" ] && [ -d "$CURSOR_COMMANDS_SOURCE" ]; then
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

# Sync multi-agent configurations
echo ""
echo "🤖 Syncing AI agent configurations..."
sync_ai_agents "$STANDARDS_DIR" "$SCRIPT_DIR" "$PROJECT_ROOT"

# Update git aliases if setup script exists
if [ -d "$STANDARDS_DIR" ]; then
    GIT_ALIASES_SCRIPT="$STANDARDS_DIR/scripts/setup-git-aliases.sh"
elif [ -f "$SCRIPT_DIR/setup-git-aliases.sh" ]; then
    GIT_ALIASES_SCRIPT="$SCRIPT_DIR/setup-git-aliases.sh"
else
    GIT_ALIASES_SCRIPT=""
fi

if [ -n "$GIT_ALIASES_SCRIPT" ] && [ -f "$GIT_ALIASES_SCRIPT" ] && command -v git >/dev/null 2>&1; then
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "  [dry-run] Would set up git aliases and configuration"
    else
        # Always check for new aliases, not just when updated
        # The setup script will skip existing aliases, so it's safe to run
        echo ""
        echo "🔧 Checking git aliases and configuration..."
        echo "   (Ensuring all aliases are up to date)"
        if bash "$GIT_ALIASES_SCRIPT" 2>/dev/null; then
            echo "✅ Git aliases checked/updated"
        else
            echo "⚠️  Git aliases update had issues (non-fatal, continuing...)"
        fi
    fi
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
