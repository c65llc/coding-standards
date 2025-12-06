#!/bin/bash
# Create a PR to add GitHub Copilot custom instructions for code review
# This script creates a branch, adds .github/copilot-instructions.md, and opens a PR

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Check for GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) not found. Install from: https://cli.github.com"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not in a git repository"
    exit 1
fi

# Determine source of copilot-instructions.md
STANDARDS_DIR="$PROJECT_ROOT/.standards"
COPILOT_INSTRUCTIONS_SOURCE=""

if [ -f "$STANDARDS_DIR/standards/agents/copilot/.github/copilot-instructions.md" ]; then
    COPILOT_INSTRUCTIONS_SOURCE="$STANDARDS_DIR/standards/agents/copilot/.github/copilot-instructions.md"
elif [ -f "$SCRIPT_DIR/../standards/agents/copilot/.github/copilot-instructions.md" ]; then
    COPILOT_INSTRUCTIONS_SOURCE="$SCRIPT_DIR/../standards/agents/copilot/.github/copilot-instructions.md"
else
    echo "❌ Could not find copilot-instructions.md source file"
    exit 1
fi

# Check if file already exists
if [ -f "$PROJECT_ROOT/.github/copilot-instructions.md" ]; then
    echo "ℹ️  .github/copilot-instructions.md already exists"
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting..."
        exit 0
    fi
    BRANCH_NAME="update-copilot-instructions"
else
    BRANCH_NAME="add-copilot-instructions"
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH="${1:-main}"

# Check if we're already on a feature branch
if [ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]; then
    echo "⚠️  Currently on branch '$CURRENT_BRANCH', not '$BASE_BRANCH'"
    read -p "Do you want to create the PR from this branch? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Checking out $BASE_BRANCH..."
        git checkout "$BASE_BRANCH"
        git pull origin "$BASE_BRANCH" 2>/dev/null || true
    else
        BASE_BRANCH="$CURRENT_BRANCH"
    fi
fi

# Create or switch to feature branch
if git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
    echo "⚠️  Branch '$BRANCH_NAME' already exists"
    read -p "Do you want to switch to it and update? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git checkout "$BRANCH_NAME"
    else
        echo "Exiting..."
        exit 0
    fi
else
    git checkout -b "$BRANCH_NAME" "$BASE_BRANCH"
fi

# Ensure .github directory exists
mkdir -p "$PROJECT_ROOT/.github"

# Copy copilot-instructions.md
echo "📝 Copying copilot-instructions.md..."
cp "$COPILOT_INSTRUCTIONS_SOURCE" "$PROJECT_ROOT/.github/copilot-instructions.md"

# Stage the file
git add .github/copilot-instructions.md

# Check if there are changes to commit
if git diff --cached --quiet; then
    echo "ℹ️  No changes to commit (file is already up to date)"
    git checkout "$CURRENT_BRANCH" 2>/dev/null || true
    exit 0
fi

# Commit the changes
COMMIT_MSG="feat(copilot): add custom instructions for code review

Add .github/copilot-instructions.md to enable GitHub Copilot code review
to follow project standards. This file references all standards documents
and ensures Copilot reviews align with project architecture and coding
conventions.

After merging this PR:
1. Enable Copilot code review in repository settings (Settings > Copilot > Code review)
2. Toggle 'Use custom instructions when reviewing pull requests' to on

Reference: https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions"

git commit -m "$COMMIT_MSG"

# Push branch
echo "📤 Pushing branch '$BRANCH_NAME'..."
git push -u origin "$BRANCH_NAME" 2>/dev/null || git push 2>/dev/null

# Create PR
PR_TITLE="feat(copilot): add custom instructions for code review"
PR_BODY="## Summary

This PR adds \`.github/copilot-instructions.md\` to enable GitHub Copilot code review to follow project standards. This file references all standards documents and ensures Copilot reviews align with project architecture and coding conventions.

## Changes

- Added \`.github/copilot-instructions.md\` with comprehensive project standards
- References architecture, language-specific, and process standards
- Configures Copilot to follow project conventions automatically

## After Merging

1. **Enable Copilot Code Review** (if not already enabled):
   - Navigate to repository Settings > Copilot > Code review
   - Enable \"Use custom instructions when reviewing pull requests\"

2. **Restart IDE** (if using Copilot in IDE):
   - Fully quit and restart VS Code, JetBrains IDE, or Visual Studio
   - Copilot will automatically load the custom instructions

## Benefits

- ✅ Copilot code reviews will follow project standards
- ✅ Consistent code review feedback across all PRs
- ✅ Automatic validation of architecture, naming, and conventions
- ✅ Alignment with project's coding standards and best practices

## Documentation

- [GitHub Docs: Add repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions)
- [GitHub Docs: Configure code review](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions#enabling-or-disabling-custom-instructions-for-copilot-code-review)

## Verification

After merging and enabling:
- Create a test PR and verify Copilot code review uses custom instructions
- Check that review comments reference project standards
- Confirm architecture and convention violations are caught"

echo "🚀 Creating Pull Request..."
gh pr create --base "$BASE_BRANCH" --head "$BRANCH_NAME" --title "$PR_TITLE" --body "$PR_BODY"

echo ""
echo "✅ PR created successfully!"
echo "📝 Don't forget to enable Copilot code review in repository settings after merging:"
echo "   Settings > Copilot > Code review > 'Use custom instructions when reviewing pull requests'"





