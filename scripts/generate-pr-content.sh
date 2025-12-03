#!/bin/bash
# Generate PR content using git information for Cursor AI to enhance
# This script outputs PR information that Cursor AI can use to generate better titles and descriptions

set -e

CURRENT_BRANCH=$(git branch --show-current)
BASE_BRANCH="${1:-main}"

if [ "$CURRENT_BRANCH" = "$BASE_BRANCH" ]; then
    echo "❌ Cannot create PR from $BASE_BRANCH to itself" >&2
    exit 1
fi

# Create temporary file for PR content
PR_CONTENT_FILE=$(mktemp /tmp/pr-content-XXXXXX.txt)
trap "rm -f $PR_CONTENT_FILE" EXIT

# Gather commit information
echo "# PR Information for Cursor AI" > "$PR_CONTENT_FILE"
echo "" >> "$PR_CONTENT_FILE"
echo "## Branch Information" >> "$PR_CONTENT_FILE"
echo "- Current Branch: $CURRENT_BRANCH" >> "$PR_CONTENT_FILE"
echo "- Base Branch: $BASE_BRANCH" >> "$PR_CONTENT_FILE"
echo "" >> "$PR_CONTENT_FILE"

# Get commit messages
echo "## Commits" >> "$PR_CONTENT_FILE"
git log "$BASE_BRANCH..HEAD" --oneline --format="%h %s" >> "$PR_CONTENT_FILE" || echo "No commits found" >> "$PR_CONTENT_FILE"
echo "" >> "$PR_CONTENT_FILE"

# Get changed files summary
echo "## Changed Files" >> "$PR_CONTENT_FILE"
git diff --stat "$BASE_BRANCH..HEAD" >> "$PR_CONTENT_FILE" || echo "No changes found" >> "$PR_CONTENT_FILE"
echo "" >> "$PR_CONTENT_FILE"

# Get file list
echo "## Files Changed" >> "$PR_CONTENT_FILE"
git diff --name-only "$BASE_BRANCH..HEAD" | while read -r file; do
    echo "- $file" >> "$PR_CONTENT_FILE"
done
echo "" >> "$PR_CONTENT_FILE"

# Get diff summary (first 50 lines to avoid too much content)
echo "## Code Changes Summary" >> "$PR_CONTENT_FILE"
git diff "$BASE_BRANCH..HEAD" --stat --shortstat >> "$PR_CONTENT_FILE" || echo "No diff available" >> "$PR_CONTENT_FILE"
echo "" >> "$PR_CONTENT_FILE"

# Output the file path for Cursor to read
echo "$PR_CONTENT_FILE"

