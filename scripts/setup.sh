#!/bin/bash
# Setup script for integrating standards into a new project

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Parse arguments
ROLE="service"
AGENTS_OVERRIDE=""
LANGUAGES_OVERRIDE=""
DRY_RUN=false
INSTALL_WORKFLOW=false

while [ $# -gt 0 ]; do
    case "$1" in
        --role)
            ROLE="$2"
            shift 2
            ;;
        --agents)
            AGENTS_OVERRIDE="$2"
            shift 2
            ;;
        --languages)
            LANGUAGES_OVERRIDE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --workflow)
            INSTALL_WORKFLOW=true
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
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
fi
if [ -f "$SCRIPT_DIR/lib/assembly.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/assembly.sh"
fi

# Map detected languages to block filenames
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

    # Detect project languages
    local DETECTED_LANGS=""
    if [ -n "$LANGUAGES_OVERRIDE" ]; then
        DETECTED_LANGS=$(echo "$LANGUAGES_OVERRIDE" | tr ',' ' ')
    else
        local DETECT_SCRIPT="$SCRIPT_DIR/detect-languages.sh"
        if [ -x "$DETECT_SCRIPT" ]; then
            DETECTED_LANGS=$("$DETECT_SCRIPT" "$PROJECT_ROOT")
        fi
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
    if [ -n "$AGENTS_OVERRIDE" ] && [ "$AGENTS_OVERRIDE" != "detect" ]; then
        if [ "$AGENTS_OVERRIDE" = "all" ]; then
            AGENTS_LIST="claude-code cursor copilot gemini codex aider"
        else
            AGENTS_LIST=$(echo "$AGENTS_OVERRIDE" | tr ',' ' ')
        fi
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
                ;;
            2)
                echo "⚠️  $agent config was manually created — backup in $PENDING_DIR/"
                PENDING_LIST="${PENDING_LIST:+$PENDING_LIST }$(basename "$OUTPUT_PATH")"
                ;;
            3)
                echo "⚠️  Failed to assemble $agent config (non-fatal, continuing...)"
                continue
                ;;
        esac

        # Aider special handling: also copy aiderrc.template to .aiderrc
        if [ "$agent" = "aider" ] && [ -f "$AGENTS_DIR/aider/aiderrc.template" ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "  [dry-run] Would copy: $AGENTS_DIR/aider/aiderrc.template → $PROJECT_ROOT/.aiderrc"
            elif cp "$AGENTS_DIR/aider/aiderrc.template" "$PROJECT_ROOT/.aiderrc" 2>/dev/null; then
                echo "   ✅ Aider .aiderrc installed"
                if type compute_hash &>/dev/null; then
                    local rc_hash
                    rc_hash=$(shasum -a 256 "$PROJECT_ROOT/.aiderrc" | awk '{print $1}')
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

    # Claude Code settings.json and permissions (unchanged from original)
    if [ ! -f "$PROJECT_ROOT/.claude/settings.json" ] || [ "$DRY_RUN" = true ]; then
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

    # Gemini settings.json (separate from GEMINI.md which is now assembled)
    local GEMINI_SOURCE=""
    if [ -n "$STANDARDS_DIR" ] && [ -d "$STANDARDS_DIR/.gemini" ]; then
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

    # Write .standards.yml
    {
        echo "# .standards.yml — Project standards configuration"
        echo "# Generated by coding-standards setup.sh"
        echo "version: 1"
        if [ -n "$DETECTED_LANGS" ]; then
            echo "languages:"
            for lang in $DETECTED_LANGS; do echo "  - $lang"; done
        else
            echo "languages: []"
        fi
        if [ -n "$ASSEMBLED_AGENTS_LIST" ]; then
            echo "agents:"
            for agent in $(echo "$ASSEMBLED_AGENTS_LIST" | tr ',' ' '); do echo "  - $agent"; done
        else
            echo "agents: []"
        fi
        echo "role: $ROLE"
        echo "coverage:"
        echo "  minimum: 95"
        echo "  domain: 100"
        echo "architecture: clean"
        echo "security: strict"
    } | dry_run_write "$PROJECT_ROOT/.standards.yml"
    if [ "$DRY_RUN" = false ]; then
        echo "✅ .standards.yml created"
    fi

    # Write initial checksums
    if [ "$DRY_RUN" = false ] && type compute_hash &>/dev/null && [ -n "$NEW_CHECKSUMS" ]; then
        echo "$NEW_CHECKSUMS" > "$PROJECT_ROOT/$CHECKSUMS_FILE"
        echo "✅ .standards-checksums created"
    elif [ "$DRY_RUN" = true ] && [ -n "$NEW_CHECKSUMS" ]; then
        echo "  [dry-run] Would write: $PROJECT_ROOT/$CHECKSUMS_FILE"
    fi

    # Install merge-standards skill
    local SKILL_SOURCE="$AGENTS_DIR/claude-code/skills/merge-standards.md"
    if [ -f "$SKILL_SOURCE" ]; then
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

    # Detect agents early — before .cursor/commands install modifies the filesystem.
    # This snapshot is used by setup_ai_agents() when --agents detect (default).
    if [ -z "$AGENTS_OVERRIDE" ] || [ "$AGENTS_OVERRIDE" = "detect" ]; then
        if [ -f "$SCRIPT_DIR/lib/detect-agents.sh" ]; then
            # shellcheck disable=SC1091
            source "$SCRIPT_DIR/lib/detect-agents.sh"
            PRE_DETECTED_AGENTS=$(detect_installed_agents "$PROJECT_ROOT")
        fi
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

    # Emit MERGE_PLAN.md if setup staged any pending updates.
    if [ -f "$SCRIPT_DIR/lib/merge-plan.sh" ] && [ -n "${PENDING_LIST:-}" ]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/lib/merge-plan.sh"
        write_merge_plan "$PROJECT_ROOT" "$PENDING_LIST" "${DETECTED_AGENTS:-}" "${ASSEMBLED_AGENTS_LIST:-}"
        echo ""
        echo "📋 Pending updates staged. See .standards-pending/MERGE_PLAN.md or run:"
        echo "   Claude Code: /merge-standards"
        echo "   Cursor:      /merge-standards"
        echo "   CLI:         make merge-standards"
    fi
fi

# Set up git hooks
echo "🪝 Setting up git hooks..."

GIT_HOOKS_DIR="$PROJECT_ROOT/.git/hooks"

if [ ! -d "$GIT_HOOKS_DIR" ]; then
    echo "⚠️  Not a git repository. Skipping git hooks setup."
elif [ "$DRY_RUN" = true ]; then
    echo "  [dry-run] Would write: $GIT_HOOKS_DIR/post-merge"
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
echo "8. To sync standards later, run: ./sync-standards.sh (or cd .standards && git pull)"
echo "   Note: After syncing, fully restart your IDE again to load updated configurations"
