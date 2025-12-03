#!/bin/bash
# Sync script to update standards in existing projects

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

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
    cp -r "$CURSOR_COMMANDS_SOURCE"/* "$PROJECT_ROOT/.cursor/commands/" 2>/dev/null || true
    echo "✅ Cursor commands synced"
fi

# Update git aliases if setup script exists
if [ -d "$STANDARDS_DIR" ]; then
    GIT_ALIASES_SCRIPT="$STANDARDS_DIR/scripts/setup-git-aliases.sh"
elif [ -f "$SCRIPT_DIR/setup-git-aliases.sh" ]; then
    GIT_ALIASES_SCRIPT="$SCRIPT_DIR/setup-git-aliases.sh"
else
    GIT_ALIASES_SCRIPT=""
fi

if [ -n "$GIT_ALIASES_SCRIPT" ] && [ -f "$GIT_ALIASES_SCRIPT" ] && command -v git >/dev/null 2>&1; then
    if [ "$UPDATED" = true ]; then
        echo ""
        echo "🔧 Updating git aliases and configuration..."
        echo "   (New aliases may be available from updated standards)"
        if bash "$GIT_ALIASES_SCRIPT" 2>/dev/null; then
            echo "✅ Git aliases updated"
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

