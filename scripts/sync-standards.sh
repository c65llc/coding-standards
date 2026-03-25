#!/bin/bash
# Sync script to update standards in existing projects

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

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

    # Read .standards-config for persisted settings
    local ROLE="service"
    local DETECTED_LANGS=""
    local AGENTS_LIST=""

    if [ -f "$PROJECT_ROOT/.standards-config" ]; then
        # shellcheck disable=SC1091
        source "$PROJECT_ROOT/.standards-config"
        ROLE="${STANDARDS_ROLE:-service}"
        # Convert comma-separated to space-separated
        DETECTED_LANGS=$(echo "${STANDARDS_LANGUAGES:-}" | tr ',' ' ')
        AGENTS_LIST=$(echo "${STANDARDS_AGENTS:-}" | tr ',' ' ')
    else
        echo "⚠️  No .standards-config found. Running auto-detection (default role: service)."
        ROLE="service"
        DETECTED_LANGS=""
    fi

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
            copilot) mkdir -p "$PROJECT_ROOT/.github" ;;
            gemini)  mkdir -p "$PROJECT_ROOT/.gemini" ;;
        esac

        echo "📝 Re-assembling $agent config..."
        if "$ASSEMBLE_SCRIPT" "$agent" "$BLOCKS_DIR" "$BASE_TEMPLATE" "$OUTPUT_PATH" ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"}; then
            echo "✅ $agent config synced"
        else
            echo "⚠️  Failed to sync $agent config (non-fatal, continuing...)"
        fi

        # Aider special handling: also sync aiderrc.template to .aiderrc
        if [ "$agent" = "aider" ] && [ -f "$AGENTS_DIR/aider/aiderrc.template" ]; then
            if ! cmp -s "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                if cp "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                    echo "   ✅ Aider .aiderrc synced"
                fi
            fi
        fi
    done

    # Codex: deprecation warning for old .codexrc
    if [ -f "$PROJECT_ROOT/.codexrc" ]; then
        echo "⚠️  .codexrc is deprecated. Codex now uses AGENTS.md."
        echo "   Your .codexrc has been preserved. Remove it when ready."
    fi

    # Claude Code settings.json (unchanged from original — only create if missing)
    if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ]; then
        if [ -f "$AGENTS_DIR/claude-code/settings.json.example" ]; then
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
                            if cp "$config_file" "$PROJECT_ROOT/$config_name" 2>/dev/null; then
                                echo "   ✅ Added $config_name ($lang)"
                            fi
                        elif ! cmp -s "$config_file" "$PROJECT_ROOT/$config_name" 2>/dev/null; then
                            if [ "$UPDATED" = true ]; then
                                if cp "$config_file" "$PROJECT_ROOT/$config_name" 2>/dev/null; then
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
        mkdir -p "$PROJECT_ROOT/.gemini"
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
                echo "📝 Adding Gemini CLI settings (not yet configured)..."
                if cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                    echo "✅ Gemini CLI settings added at .gemini/settings.json"
                fi
            elif [ "$UPDATED" = true ] || ! cmp -s "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                echo "📝 Updating Gemini CLI settings..."
                if cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                    echo "✅ Gemini CLI settings updated"
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
    mkdir -p "$PROJECT_ROOT/.cursor/commands"
    if cp -r "$CURSOR_COMMANDS_SOURCE"/* "$PROJECT_ROOT/.cursor/commands/" 2>/dev/null; then
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
