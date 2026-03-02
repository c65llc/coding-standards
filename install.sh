#!/bin/bash
# One-line installer for project standards
# 
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/c65llc/coding_standards/main/install.sh | bash
#
# Or with custom repository URL:
#   STANDARDS_REPO_URL="https://github.com/c65llc/coding_standards" \
#     curl -fsSL https://raw.githubusercontent.com/c65llc/coding_standards/main/install.sh | bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration (will be set by user or defaults)
STANDARDS_REPO_URL="${STANDARDS_REPO_URL:-}"
STANDARDS_DIR="${STANDARDS_DIR:-.standards}"

echo -e "${BLUE}🚀 Installing Project Standards${NC}"
echo ""

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Not in a git repository. Initializing...${NC}"
    git init
fi

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
cd "$PROJECT_ROOT"

# Check if standards already exist
if [ -d "$STANDARDS_DIR" ]; then
    echo -e "${YELLOW}⚠️  Standards directory already exists at $STANDARDS_DIR${NC}"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Get repository URL if not provided
if [ -z "$STANDARDS_REPO_URL" ]; then
    STANDARDS_REPO_URL="https://github.com/c65llc/coding_standards"
    echo -e "${BLUE}📋 Using default repository: ${STANDARDS_REPO_URL}${NC}"
    echo -e "${YELLOW}   (Set STANDARDS_REPO_URL env var to use a different repository)${NC}"
fi

# Add as git submodule
echo -e "${BLUE}📥 Adding standards as git submodule...${NC}"
if git submodule add "$STANDARDS_REPO_URL" "$STANDARDS_DIR" 2>/dev/null; then
    echo -e "${GREEN}✅ Standards submodule added${NC}"
else
    # If submodule add fails, try cloning
    echo -e "${YELLOW}⚠️  Submodule add failed, cloning instead...${NC}"
    if [ -d "$STANDARDS_DIR" ]; then
        rm -rf "$STANDARDS_DIR"
    fi
    git clone "$STANDARDS_REPO_URL" "$STANDARDS_DIR"
    echo -e "${GREEN}✅ Standards cloned${NC}"
fi

# Initialize submodule if needed
if [ -f "$STANDARDS_DIR/.gitmodules" ] || [ -f "$PROJECT_ROOT/.gitmodules" ]; then
    git submodule update --init --recursive "$STANDARDS_DIR" 2>/dev/null || true
fi

# Run setup script (includes git aliases setup and multi-agent configuration)
echo -e "${BLUE}🔧 Running setup script...${NC}"
if [ -f "$STANDARDS_DIR/scripts/setup.sh" ]; then
    bash "$STANDARDS_DIR/scripts/setup.sh"
    echo -e "${GREEN}✅ Setup complete${NC}"
    echo -e "${BLUE}📋 AI agent configurations installed:${NC}"
    echo -e "   - Cursor AI: .cursorrules"
    [ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ] && echo -e "   - GitHub Copilot: .github/copilot-instructions.md"
    [ -f "$PROJECT_ROOT/.aiderrc" ] && echo -e "   - Aider (Claude): .aiderrc"
    [ -f "$PROJECT_ROOT/.codexrc" ] && echo -e "   - Codex: .codexrc"
else
    echo -e "${YELLOW}⚠️  Setup script not found, creating .cursorrules manually...${NC}"
    if [ -f "$STANDARDS_DIR/.cursorrules" ]; then
        cp "$STANDARDS_DIR/.cursorrules" "$PROJECT_ROOT/.cursorrules"
        echo -e "${GREEN}✅ .cursorrules created${NC}"
    fi
fi

# Add sync-standards and setup-cursor targets to Makefile
echo -e "${BLUE}📝 Adding standards targets to Makefile...${NC}"
if [ -f "$PROJECT_ROOT/Makefile" ]; then
    # Check if targets already exist
    if grep -q "sync-standards:" "$PROJECT_ROOT/Makefile"; then
        echo -e "${YELLOW}⚠️  sync-standards target already exists in Makefile${NC}"
    else
        # Add sync-standards target (automatically updates cursor rules)
        cat >> "$PROJECT_ROOT/Makefile" << 'MAKEFILE'

.PHONY: sync-standards
sync-standards: ## Sync project standards to latest version
	@if [ -d ".standards" ]; then \
		./.standards/scripts/sync-standards.sh; \
		$(MAKE) setup-cursor; \
	else \
		echo "❌ .standards directory not found. Run install script first."; \
		exit 1; \
	fi
MAKEFILE
        echo -e "${GREEN}✅ Added sync-standards target to Makefile${NC}"
    fi
    
    if grep -q "setup-cursor:" "$PROJECT_ROOT/Makefile"; then
        echo -e "${YELLOW}⚠️  setup-cursor target already exists in Makefile${NC}"
    else
        # Add setup-cursor target
        cat >> "$PROJECT_ROOT/Makefile" << 'MAKEFILE'

.PHONY: setup-cursor
setup-cursor: ## Install or update Cursor AI rules configuration
	@if [ -d ".standards" ] && [ -f ".standards/.cursorrules" ]; then \
		cp .standards/.cursorrules .cursorrules && \
		echo "✅ .cursorrules updated from .standards"; \
	elif [ -f ".standards/.cursorrules" ]; then \
		cp .standards/.cursorrules .cursorrules && \
		echo "✅ .cursorrules installed"; \
	else \
		echo "⚠️  Standards directory not found. Run setup script first."; \
		exit 1; \
	fi
MAKEFILE
        echo -e "${GREEN}✅ Added setup-cursor target to Makefile${NC}"
    fi
else
    # Create new Makefile with sync-standards and setup-cursor targets
    cat > "$PROJECT_ROOT/Makefile" << 'MAKEFILE'
.PHONY: help sync-standards setup-cursor

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

sync-standards: ## Sync project standards to latest version
	@if [ -d ".standards" ]; then \
		./.standards/scripts/sync-standards.sh; \
		$(MAKE) setup-cursor; \
	else \
		echo "❌ .standards directory not found. Run install script first."; \
		exit 1; \
	fi

setup-cursor: ## Install or update Cursor AI rules configuration
	@if [ -d ".standards" ] && [ -f ".standards/.cursorrules" ]; then \
		cp .standards/.cursorrules .cursorrules && \
		echo "✅ .cursorrules updated from .standards"; \
	elif [ -f ".standards/.cursorrules" ]; then \
		cp .standards/.cursorrules .cursorrules && \
		echo "✅ .cursorrules installed"; \
	else \
		echo "⚠️  Standards directory not found. Run setup script first."; \
		exit 1; \
	fi
MAKEFILE
    echo -e "${GREEN}✅ Created Makefile with standards targets${NC}"
fi

# Add .standards_tmp/ and coverage/ to .gitignore if needed
echo -e "${BLUE}📝 Updating .gitignore...${NC}"
if [ -f "$PROJECT_ROOT/.gitignore" ]; then
    if ! grep -q ".standards_tmp" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Standards temporary files"
            echo ".standards_tmp/"
        } >> "$PROJECT_ROOT/.gitignore"
        echo -e "${GREEN}✅ Added .standards_tmp/ to .gitignore${NC}"
    else
        echo -e "${YELLOW}⚠️  .standards_tmp/ already in .gitignore${NC}"
    fi
    if ! grep -q "coverage/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        {
            echo ""
            echo "# Test coverage output"
            echo "coverage/"
        } >> "$PROJECT_ROOT/.gitignore"
        echo -e "${GREEN}✅ Added coverage/ to .gitignore${NC}"
    else
        echo -e "${YELLOW}⚠️  coverage/ already in .gitignore${NC}"
    fi
else
    # Create .gitignore with .standards_tmp/ and coverage/
    cat > "$PROJECT_ROOT/.gitignore" << 'GITIGNORE'
# Test coverage output
coverage/

# Standards temporary files
.standards_tmp/
GITIGNORE
    echo -e "${GREEN}✅ Created .gitignore with .standards_tmp/ and coverage/${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}✅ Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart Cursor to load .cursorrules"
echo "  2. Review standards in: $STANDARDS_DIR"
echo "  3. Sync standards later: make sync-standards"
echo "  4. Update cursor rules: make setup-cursor"
echo ""
echo -e "${BLUE}🔧 GitHub Project Lifecycle Automation:${NC}"
echo "  - Symlink gh-task: ln -s $STANDARDS_DIR/bin/gh-task bin/gh-task"
echo "  - Configure: See $STANDARDS_DIR/docs/GH_TASK_GUIDE.md"
echo "  - AI Agent guide: $STANDARDS_DIR/docs/TOOLING.md"
echo ""
echo -e "${BLUE}📚 Documentation:${NC}"
echo "  - Quick Start: $STANDARDS_DIR/docs/QUICK_START.md"
echo "  - Setup Guide: $STANDARDS_DIR/docs/SETUP_GUIDE.md"

