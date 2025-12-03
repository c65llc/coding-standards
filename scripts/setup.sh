#!/bin/bash
# Setup script for integrating standards into a new project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

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
        cp -r "$CURSOR_COMMANDS_SOURCE"/* "$PROJECT_ROOT/.cursor/commands/" 2>/dev/null || true
        echo "✅ Cursor commands installed"
    fi
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
        echo "" >> "$PROJECT_ROOT/.gitignore"
        echo "# Standards temporary files" >> "$PROJECT_ROOT/.gitignore"
        echo ".standards_tmp/" >> "$PROJECT_ROOT/.gitignore"
    fi
elif [ "$SCRIPT_DIR" != "$PROJECT_ROOT" ]; then
    # Create .gitignore if it doesn't exist (only for client projects, not standards repo itself)
    cat > "$PROJECT_ROOT/.gitignore" << 'GITIGNORE'
# Standards temporary files
.standards_tmp/

# Backup files
.cursorrules.backup
GITIGNORE
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Restart Cursor to load .cursorrules"
echo "2. If using submodule, ensure it's initialized: git submodule update --init"
echo "3. To sync standards later, run: ./sync-standards.sh (or cd .standards && git pull)"

