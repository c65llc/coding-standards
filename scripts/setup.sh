#!/bin/bash
# Setup script for integrating standards into a new project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

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
    
    # Setup GitHub Copilot
    if [ -f "$AGENTS_DIR/copilot/.github/copilot-instructions.md" ]; then
        echo "📝 Setting up GitHub Copilot..."
        mkdir -p "$PROJECT_ROOT/.github"
        if cp "$AGENTS_DIR/copilot/.github/copilot-instructions.md" "$PROJECT_ROOT/.github/copilot-instructions.md" 2>/dev/null; then
            echo "✅ GitHub Copilot instructions installed at .github/copilot-instructions.md"
        else
            echo "⚠️  Failed to install Copilot instructions (non-fatal, continuing...)"
        fi
    fi
    
    # Setup Aider (Claude Code)
    if [ -f "$AGENTS_DIR/aider/.aiderrc" ]; then
        echo "📝 Setting up Aider (Claude Code)..."
        if cp "$AGENTS_DIR/aider/.aiderrc" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
            echo "✅ Aider configuration installed at .aiderrc"
        else
            echo "⚠️  Failed to install Aider config (non-fatal, continuing...)"
        fi
    fi
    
    # Setup OpenAI Codex
    if [ -f "$AGENTS_DIR/codex/.codexrc" ]; then
        echo "📝 Setting up OpenAI Codex..."
        if cp "$AGENTS_DIR/codex/.codexrc" "$PROJECT_ROOT/.codexrc" 2>/dev/null; then
            echo "✅ Codex configuration installed at .codexrc"
        else
            echo "⚠️  Failed to install Codex config (non-fatal, continuing...)"
        fi
    fi

    # Setup Claude Code
    if [ -f "$AGENTS_DIR/claude-code/CLAUDE.md.template" ]; then
        echo "📝 Setting up Claude Code..."
        if [ ! -f "$PROJECT_ROOT/CLAUDE.md" ]; then
            if cp "$AGENTS_DIR/claude-code/CLAUDE.md.template" "$PROJECT_ROOT/CLAUDE.md" 2>/dev/null; then
                echo "✅ CLAUDE.md template installed at project root"
                echo "💡 Customize CLAUDE.md with your project-specific details"
            else
                echo "⚠️  Failed to install CLAUDE.md (non-fatal, continuing...)"
            fi
        else
            echo "ℹ️  CLAUDE.md already exists, skipping (won't overwrite project-specific guide)"
        fi
        if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ]; then
            mkdir -p "$PROJECT_ROOT/.claude"
            if cp "$AGENTS_DIR/claude-code/settings.json.example" "$PROJECT_ROOT/.claude/settings.json" 2>/dev/null; then
                echo "✅ Claude Code settings installed at .claude/settings.json"
            else
                echo "⚠️  Failed to install Claude Code settings (non-fatal, continuing...)"
            fi
        else
            echo "ℹ️  .claude/settings.json already exists, skipping"
        fi
    fi

    # Setup Gemini CLI & Antigravity
    if [ -d "$STANDARDS_DIR/.gemini" ]; then
        GEMINI_SOURCE="$STANDARDS_DIR/.gemini"
    elif [ -d "$SCRIPT_DIR/../.gemini" ]; then
        GEMINI_SOURCE="$SCRIPT_DIR/../.gemini"
    else
        GEMINI_SOURCE=""
    fi

    if [ -n "$GEMINI_SOURCE" ] && [ -d "$GEMINI_SOURCE" ]; then
        echo "📝 Setting up Gemini CLI & Antigravity..."
        mkdir -p "$PROJECT_ROOT/.gemini"
        if [ -f "$GEMINI_SOURCE/GEMINI.md" ]; then
            if cp "$GEMINI_SOURCE/GEMINI.md" "$PROJECT_ROOT/.gemini/GEMINI.md" 2>/dev/null; then
                echo "✅ Gemini configuration installed at .gemini/GEMINI.md"
            else
                echo "⚠️  Failed to install Gemini config (non-fatal, continuing...)"
            fi
        fi
        if [ -f "$GEMINI_SOURCE/settings.json" ]; then
            # Validate JSON syntax before copying
            if command -v python3 >/dev/null 2>&1; then
                if ! python3 -m json.tool "$GEMINI_SOURCE/settings.json" >/dev/null 2>&1; then
                    echo "⚠️  Invalid JSON in Gemini settings.json, skipping..."
                elif cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                    echo "✅ Gemini CLI settings installed at .gemini/settings.json"
                else
                    echo "⚠️  Failed to install Gemini settings (non-fatal, continuing...)"
                fi
            elif command -v jq >/dev/null 2>&1; then
                if ! jq empty "$GEMINI_SOURCE/settings.json" >/dev/null 2>&1; then
                    echo "⚠️  Invalid JSON in Gemini settings.json, skipping..."
                elif cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                    echo "✅ Gemini CLI settings installed at .gemini/settings.json"
                else
                    echo "⚠️  Failed to install Gemini settings (non-fatal, continuing...)"
                fi
            else
                # No JSON validator available, copy without validation
                if cp "$GEMINI_SOURCE/settings.json" "$PROJECT_ROOT/.gemini/settings.json" 2>/dev/null; then
                    echo "✅ Gemini CLI settings installed at .gemini/settings.json"
                else
                    echo "⚠️  Failed to install Gemini settings (non-fatal, continuing...)"
                fi
            fi
        fi
    fi
}

echo "🔧 Setting up project standards..."

# Check if .cursorrules already exists
if [ -f "$PROJECT_ROOT/.cursorrules" ]; then
    echo "⚠️  .cursorrules already exists. Backing up to .cursorrules.backup"
    cp "$PROJECT_ROOT/.cursorrules" "$PROJECT_ROOT/.cursorrules.backup"
fi

# Determine if we're in the standards repo or a project using it
if [ "$SCRIPT_DIR" = "$PROJECT_ROOT" ]; then
    # We're in the standards repo itself
    echo "📋 Detected standards repository. Creating .cursorrules..."
    if [ ! -f "$PROJECT_ROOT/.cursorrules" ]; then
        echo "✅ .cursorrules created in standards repository"
    fi
else
    # We're in a project using standards
    STANDARDS_DIR="$PROJECT_ROOT/.standards"
    
    if [ -d "$STANDARDS_DIR" ]; then
        echo "📋 Found standards submodule at .standards"
        CURSORRULES_SOURCE="$STANDARDS_DIR/.cursorrules"
    elif [ -f "$SCRIPT_DIR/../.cursorrules" ]; then
        echo "📋 Using standards from script location"
        CURSORRULES_SOURCE="$SCRIPT_DIR/../.cursorrules"
    else
        echo "❌ Error: Could not find .cursorrules"
        exit 1
    fi
    
    # Create symlink or copy .cursorrules
    if [ -L "$PROJECT_ROOT/.cursorrules" ]; then
        echo "🔗 .cursorrules is already a symlink"
    else
        echo "📝 Creating .cursorrules..."
        cp "$CURSORRULES_SOURCE" "$PROJECT_ROOT/.cursorrules"
        echo "✅ .cursorrules created"
    fi
    
    # Copy Cursor custom commands if they exist
    if [ -d "$STANDARDS_DIR/.cursor/commands" ]; then
        CURSOR_COMMANDS_SOURCE="$STANDARDS_DIR/.cursor/commands"
    elif [ -d "$SCRIPT_DIR/../.cursor/commands" ]; then
        CURSOR_COMMANDS_SOURCE="$SCRIPT_DIR/../.cursor/commands"
    else
        CURSOR_COMMANDS_SOURCE=""
    fi
    
    if [ -n "$CURSOR_COMMANDS_SOURCE" ] && [ -d "$CURSOR_COMMANDS_SOURCE" ]; then
        echo "📝 Setting up Cursor custom commands..."
        mkdir -p "$PROJECT_ROOT/.cursor/commands"
        if cp -r "$CURSOR_COMMANDS_SOURCE"/* "$PROJECT_ROOT/.cursor/commands/" 2>/dev/null; then
            echo "✅ Cursor commands installed"
            echo "⚠️  Please fully quit and restart Cursor to load custom commands"
        else
            echo "⚠️  Failed to install Cursor commands (non-fatal, continuing...)"
        fi
    fi
    
    # Setup multi-agent configurations
    echo ""
    echo "🤖 Setting up AI agent configurations..."
    setup_ai_agents "$STANDARDS_DIR" "$SCRIPT_DIR" "$PROJECT_ROOT"
fi

# Set up git hooks
echo "🪝 Setting up git hooks..."

GIT_HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "⚠️  Not a git repository. Skipping git hooks setup."
else
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

# Set up git aliases (global configuration)
if command -v git >/dev/null 2>&1; then
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
        echo ""
        echo "🔧 Setting up git aliases and configuration..."
        echo "   (This configures global git settings and aliases for your system)"
        if bash "$GIT_ALIASES_SCRIPT"; then
            echo "✅ Git aliases and configuration set up"
        else
            echo "⚠️  Git setup had issues (non-fatal, continuing...)"
        fi
    fi
else
    echo "⚠️  Git not found. Skipping git aliases setup."
fi

# Create .gitignore entries if needed
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if ! grep -q ".cursorrules.backup" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        echo ".cursorrules.backup" >> "$PROJECT_ROOT/.gitignore"
    fi
    if ! grep -q ".standards_tmp" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Standards temporary files"
            echo ".standards_tmp/"
        } >> "$PROJECT_ROOT/.gitignore"
    fi
    if ! grep -q "coverage/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Test coverage output"
            echo "coverage/"
        } >> "$PROJECT_ROOT/.gitignore"
    fi
elif [ "$SCRIPT_DIR" != "$PROJECT_ROOT" ]; then
    # Create .gitignore if it doesn't exist (only for client projects, not standards repo itself)
    cat > "$PROJECT_ROOT/.gitignore" << 'GITIGNORE'
# Test coverage output
coverage/

# Standards temporary files
.standards_tmp/

# Backup files
.cursorrules.backup
GITIGNORE
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
echo "3. If using Aider, it will automatically use .aiderrc"
echo "4. If using Codex, ensure your IDE reads .codexrc"
echo "5. If using Claude Code, customize CLAUDE.md with your project details"
echo "6. If using Gemini CLI, it will automatically use .gemini/GEMINI.md and .gemini/settings.json"
echo "7. If using submodule, ensure it's initialized: git submodule update --init"
echo "8. To sync standards later, run: ./sync-standards.sh (or cd .standards && git pull)"
echo "   Note: After syncing, fully restart your IDE again to load updated configurations"

