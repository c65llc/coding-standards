#!/bin/bash
# Sync script to update standards in existing projects

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

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
    
    # Sync GitHub Copilot
    if [ -f "$AGENTS_DIR/copilot/.github/copilot-instructions.md" ]; then
        if [ ! -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]; then
            # File doesn't exist, automatically apply it
            echo "📝 Adding GitHub Copilot instructions (not yet configured)..."
            mkdir -p "$PROJECT_ROOT/.github"
            if cp "$AGENTS_DIR/copilot/.github/copilot-instructions.md" "$PROJECT_ROOT/.github/copilot-instructions.md" 2>/dev/null; then
                echo "✅ GitHub Copilot instructions added at .github/copilot-instructions.md"
                echo "💡 To enable Copilot code review: Settings > Copilot > Code review > 'Use custom instructions when reviewing pull requests'"
            fi
        elif [ "$UPDATED" = true ] || ! cmp -s "$AGENTS_DIR/copilot/.github/copilot-instructions.md" "$PROJECT_ROOT/.github/copilot-instructions.md" 2>/dev/null; then
            # File exists but is different or standards were updated
            echo "📝 Updating GitHub Copilot instructions..."
            mkdir -p "$PROJECT_ROOT/.github"
            if cp "$AGENTS_DIR/copilot/.github/copilot-instructions.md" "$PROJECT_ROOT/.github/copilot-instructions.md" 2>/dev/null; then
                echo "✅ GitHub Copilot instructions updated"
                echo "⚠️  Please restart your IDE to load updated instructions"
            fi
        fi
    fi
    
    # Sync Aider (Claude Code)
    if [ -f "$AGENTS_DIR/aider/.aiderrc" ]; then
        if [ ! -f "$PROJECT_ROOT/.aiderrc" ]; then
            # File doesn't exist, automatically apply it
            echo "📝 Adding Aider (Claude Code) configuration (not yet configured)..."
            if cp "$AGENTS_DIR/aider/.aiderrc" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                echo "✅ Aider configuration added at .aiderrc"
            fi
        elif [ "$UPDATED" = true ] || ! cmp -s "$AGENTS_DIR/aider/.aiderrc" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
            # File exists but is different or standards were updated
            echo "📝 Updating Aider configuration..."
            if cp "$AGENTS_DIR/aider/.aiderrc" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                echo "✅ Aider configuration updated"
            fi
        fi
    fi
    
    # Sync OpenAI Codex
    if [ -f "$AGENTS_DIR/codex/.codexrc" ]; then
        if [ ! -f "$PROJECT_ROOT/.codexrc" ]; then
            # File doesn't exist, automatically apply it
            echo "📝 Adding OpenAI Codex configuration (not yet configured)..."
            if cp "$AGENTS_DIR/codex/.codexrc" "$PROJECT_ROOT/.codexrc" 2>/dev/null; then
                echo "✅ Codex configuration added at .codexrc"
            fi
        elif [ "$UPDATED" = true ] || ! cmp -s "$AGENTS_DIR/codex/.codexrc" "$PROJECT_ROOT/.codexrc" 2>/dev/null; then
            # File exists but is different or standards were updated
            echo "📝 Updating Codex configuration..."
            if cp "$AGENTS_DIR/codex/.codexrc" "$PROJECT_ROOT/.codexrc" 2>/dev/null; then
                echo "✅ Codex configuration updated"
            fi
        fi
    fi
    
    # Sync Gemini CLI & Antigravity
    if [ -d "$STANDARDS_DIR/.gemini" ]; then
        GEMINI_SOURCE="$STANDARDS_DIR/.gemini"
    elif [ -d "$SCRIPT_DIR/../.gemini" ]; then
        GEMINI_SOURCE="$SCRIPT_DIR/../.gemini"
    else
        GEMINI_SOURCE=""
    fi
    
    if [ -n "$GEMINI_SOURCE" ] && [ -d "$GEMINI_SOURCE" ]; then
        mkdir -p "$PROJECT_ROOT/.gemini"
        
        # Sync GEMINI.md
        if [ -f "$GEMINI_SOURCE/GEMINI.md" ]; then
            if [ ! -f "$PROJECT_ROOT/.gemini/GEMINI.md" ]; then
                echo "📝 Adding Gemini CLI configuration (not yet configured)..."
                if cp "$GEMINI_SOURCE/GEMINI.md" "$PROJECT_ROOT/.gemini/GEMINI.md" 2>/dev/null; then
                    echo "✅ Gemini configuration added at .gemini/GEMINI.md"
                fi
            elif [ "$UPDATED" = true ] || ! cmp -s "$GEMINI_SOURCE/GEMINI.md" "$PROJECT_ROOT/.gemini/GEMINI.md" 2>/dev/null; then
                echo "📝 Updating Gemini configuration..."
                if cp "$GEMINI_SOURCE/GEMINI.md" "$PROJECT_ROOT/.gemini/GEMINI.md" 2>/dev/null; then
                    echo "✅ Gemini configuration updated"
                fi
            fi
        fi
        
        # Sync settings.json
        if [ -f "$GEMINI_SOURCE/settings.json" ]; then
            # Validate JSON syntax before copying
            JSON_VALID=true
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
    fi
}

echo "🔄 Syncing project standards..."

# Determine standards location
STANDARDS_DIR=""
CURSORRULES_SOURCE=""

if [ -d "$PROJECT_ROOT/.standards" ]; then
    STANDARDS_DIR="$PROJECT_ROOT/.standards"
    CURSORRULES_SOURCE="$STANDARDS_DIR/.cursorrules"
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
elif [ -f "$SCRIPT_DIR/../.cursorrules" ]; then
    # Standards are in script directory (standards repo itself)
    CURSORRULES_SOURCE="$SCRIPT_DIR/../.cursorrules"
    echo "📋 Using standards from script location"
    UPDATED=false
else
    echo "❌ Error: Could not find standards directory"
    exit 1
fi

# Update .cursorrules if it exists and is different
if [ -f "$PROJECT_ROOT/.cursorrules" ]; then
    if [ "$UPDATED" = true ] || ! cmp -s "$CURSORRULES_SOURCE" "$PROJECT_ROOT/.cursorrules"; then
        if [ -L "$PROJECT_ROOT/.cursorrules" ]; then
            echo "🔗 .cursorrules is a symlink, no update needed"
        else
            echo "📝 Updating .cursorrules..."
            cp "$CURSORRULES_SOURCE" "$PROJECT_ROOT/.cursorrules"
            echo "✅ .cursorrules updated"
            echo "⚠️  Please restart Cursor to load updated rules"
        fi
    else
        echo "✅ .cursorrules is up to date"
    fi
else
    echo "📝 Creating .cursorrules..."
    cp "$CURSORRULES_SOURCE" "$PROJECT_ROOT/.cursorrules"
    echo "✅ .cursorrules created"
    echo "⚠️  Please restart Cursor to load rules"
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

