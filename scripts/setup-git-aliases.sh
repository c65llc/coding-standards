#!/bin/bash
# Setup script for git aliases based on project standards
#
# This script configures git aliases for common operations following
# the conventions in standards/process/13_git_version_control_standards.md

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}⚙️  Setting up git aliases and configuration...${NC}"

# Function to set git config if not already set
set_config() {
    local config_key=$1
    local config_value=$2
    
    if git config --global --get "$config_key" >/dev/null 2>&1; then
        local existing=$(git config --global --get "$config_key")
        if [ "$existing" != "$config_value" ]; then
            echo -e "${YELLOW}⚠️  Config '$config_key' already exists with different value:${NC}"
            echo -e "   Current: $existing"
            echo -e "   Would set: $config_value"
            read -p "   Overwrite? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "   Skipping '$config_key'"
                return
            fi
        else
            echo -e "   ✓ '$config_key' already configured correctly"
            return
        fi
    fi
    
    git config --global "$config_key" "$config_value"
    echo -e "${GREEN}   ✓ Configured '$config_key' = '$config_value'${NC}"
}

# Configure git settings
echo ""
echo "Setting up git configuration..."
set_config "push.autoSetupRemote" "true"
set_config "push.default" "simple"
set_config "init.defaultBranch" "main"

# Function to set alias if not already set
set_alias() {
    local alias_name=$1
    local alias_command=$2
    
    if git config --global --get "alias.$alias_name" >/dev/null 2>&1; then
        local existing=$(git config --global --get "alias.$alias_name")
        if [ "$existing" != "$alias_command" ]; then
            echo -e "${YELLOW}⚠️  Alias '$alias_name' already exists with different value:${NC}"
            echo -e "   Current: $existing"
            echo -e "   Would set: $alias_command"
            read -p "   Overwrite? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "   Skipping '$alias_name'"
                return
            fi
        else
            echo -e "   ✓ '$alias_name' already configured correctly"
            return
        fi
    fi
    
    git config --global "alias.$alias_name" "$alias_command"
    echo -e "${GREEN}   ✓ Configured 'git $alias_name'${NC}"
}

# Core aliases (requested by user)
echo ""
echo "Setting up core aliases..."
set_alias "co" "checkout"
set_alias "cob" "checkout -b"
set_alias "kick" "commit --allow-empty -m"
set_alias "up" "!git fetch origin && git rebase origin/main"
set_alias "refresh-main" "!f() { \
    CURRENT_BRANCH=\$(git rev-parse --abbrev-ref HEAD 2>/dev/null); \
    if [ \"\$CURRENT_BRANCH\" = \"main\" ]; then \
        echo 'On main branch, creating temporary branch...'; \
        git checkout -b __tmp_refresh_main__ 2>/dev/null || { \
            echo 'Error: Could not create temporary branch (uncommitted changes?)'; \
            exit 1; \
        }; \
    fi; \
    echo 'Fetching from origin...'; \
    git fetch origin || { echo 'Error: Could not fetch from origin'; exit 1; }; \
    echo 'Deleting local main branch...'; \
    git branch -D main 2>/dev/null || true; \
    echo 'Checking out origin/main as new main...'; \
    git checkout origin/main -b main || { \
        echo 'Error: Could not checkout origin/main'; \
        if git rev-parse --verify __tmp_refresh_main__ >/dev/null 2>&1; then \
            echo 'Restoring temporary branch...'; \
            git checkout __tmp_refresh_main__; \
        fi; \
        exit 1; \
    }; \
    if git rev-parse --verify __tmp_refresh_main__ >/dev/null 2>&1; then \
        echo 'Deleting temporary branch...'; \
        git branch -D __tmp_refresh_main__ 2>/dev/null || true; \
    fi; \
    echo '✅ Local main refreshed from origin/main'; \
}; f"

# Common workflow aliases
echo ""
echo "Setting up workflow aliases..."
set_alias "st" "status"
set_alias "br" "branch"
set_alias "cm" "commit -m"
set_alias "ca" "commit --amend"
set_alias "cane" "commit --amend --no-edit"
set_alias "unstage" "reset HEAD --"
set_alias "undo" "reset --soft HEAD^"

# Log and history aliases
echo ""
echo "Setting up log aliases..."
set_alias "last" "log -1 HEAD"
set_alias "lg" "log --oneline --decorate --graph --all"
set_alias "ll" "log --oneline --decorate -10"
set_alias "recent" "reflog"

# Diff aliases
echo ""
echo "Setting up diff aliases..."
set_alias "diffc" "diff --cached"
set_alias "diffst" "diff --staged"
set_alias "who" "blame"

# Branch management aliases
echo ""
echo "Setting up branch aliases..."
set_alias "branches" "branch -a"
set_alias "brm" "!git fetch -p && git branch -vv | grep ': gone]' | awk '{print \$1}' | xargs -r git branch -D"
set_alias "cleanup" "!git fetch -p && git branch -vv | grep ': gone]' | awk '{print \$1}' | xargs -r git branch -D"

# Pull/Push aliases
echo ""
echo "Setting up pull/push aliases..."
set_alias "pullr" "pull --rebase"
set_alias "pushf" "push --force-with-lease"
set_alias "pushu" "push -u origin HEAD"

# Feature branch helpers
echo ""
echo "Setting up feature branch helpers..."
set_alias "feat" "!f() { git checkout -b feature/\$1; }; f"
set_alias "fix" "!f() { git checkout -b fix/\$1; }; f"
set_alias "hotfix" "!f() { git checkout -b hotfix/\$1; }; f"

# Stash aliases
echo ""
echo "Setting up stash aliases..."
set_alias "stashlist" "stash list"
set_alias "stashpop" "stash pop"
set_alias "stashapply" "stash apply"

# Convenience aliases
echo ""
echo "Setting up convenience aliases..."
set_alias "aliases" "!git config --global --get-regexp alias | sed 's/alias\\.//' | sed 's/ / = /'"
set_alias "amend" "commit --amend --no-edit"
set_alias "save" "!git add -A && git commit -m 'WIP'"
set_alias "wip" "!git add -A && git commit -m 'WIP'"

echo ""
echo -e "${GREEN}✅ Git configuration and aliases set up successfully!${NC}"
echo ""
echo "Configuration applied:"
echo "  ✓ push.autoSetupRemote = true (automatically set upstream when pushing new branches)"
echo "  ✓ push.default = simple"
echo "  ✓ init.defaultBranch = main"
echo ""
echo "You can now use shortcuts like:"
echo "  git co <branch>          - Checkout a branch"
echo "  git cob <branch>         - Create and checkout new branch"
echo "  git kick \"message\"       - Create empty commit"
echo "  git up                   - Fetch and rebase against origin/main"
echo "  git refresh-main         - Reset local main to match origin/main"
echo "  git st                   - Status"
echo "  git lg                   - Pretty log graph"
echo "  git aliases              - List all configured aliases"
echo ""
echo "Note: New branches will automatically set upstream when you push them."
echo "For a complete list of aliases, run: git aliases"

