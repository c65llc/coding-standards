#!/bin/bash
# Fetch unresolved PR comments for the current branch
# Outputs JSON file with all unresolved comments for Cursor AI to process

set -e

# Check for GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) not found. Install from: https://cli.github.com" >&2
    exit 1
fi

# Check if authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo "❌ Not authenticated with GitHub. Run: gh auth login" >&2
    exit 1
fi

# Get PR number (from argument or current branch)
PR_NUMBER="${1:-}"

if [ -z "$PR_NUMBER" ]; then
    # Try to get PR number from current branch
    PR_NUMBER=$(gh pr view --json number --jq '.number' 2>/dev/null || echo "")
    
    if [ -z "$PR_NUMBER" ]; then
        echo "❌ No PR found for current branch. Specify PR number as argument or ensure branch has an associated PR." >&2
        echo "Usage: $0 [PR_NUMBER]" >&2
        exit 1
    fi
fi

# Determine project root
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Create .standards_tmp directory if it doesn't exist
STANDARDS_TMP_DIR="$PROJECT_ROOT/.standards_tmp"
mkdir -p "$STANDARDS_TMP_DIR"

# Create temporary file for PR comments
# Note: File is kept for Cursor AI to read, cleanup is handled by .gitignore
COMMENTS_FILE="$STANDARDS_TMP_DIR/pr-comments-$(date +%s)-$$.json"

# Fetch PR details
echo "🔍 Fetching PR #$PR_NUMBER comments..." >&2

# Fetch all PR data in one call for efficiency
PR_DATA=$(gh pr view "$PR_NUMBER" --json number,url,title,state,author,reviewThreads,comments 2>/dev/null)

if [ -z "$PR_DATA" ] || [ "$PR_DATA" = "null" ]; then
    echo "❌ Failed to fetch PR #$PR_NUMBER. Check if PR exists and you have access." >&2
    exit 1
fi

# Extract unresolved review threads
REVIEW_THREADS=$(echo "$PR_DATA" | jq -c '.reviewThreads[] | select(.isResolved == false)' 2>/dev/null | jq -s '.' || echo "[]")

# Extract unresolved general comments
GENERAL_COMMENTS=$(echo "$PR_DATA" | jq -c '.comments[] | select(.isMinimized == false)' 2>/dev/null | jq -s '.' || echo "[]")

# Get PR basic info (without threads/comments)
PR_INFO=$(echo "$PR_DATA" | jq '{number, url, title, state, author}' 2>/dev/null || echo "{}")

# Combine into structured JSON
jq -n \
  --argjson pr "$PR_INFO" \
  --argjson threads "$REVIEW_THREADS" \
  --argjson comments "$GENERAL_COMMENTS" \
  '{
    pr: $pr,
    reviewThreads: $threads,
    generalComments: $comments,
    summary: {
      totalUnresolvedThreads: ($threads | length),
      totalUnresolvedComments: ($comments | length)
    }
  }' > "$COMMENTS_FILE" 2>/dev/null || {
  # Fallback if jq fails
  cat > "$COMMENTS_FILE" <<EOF
{
  "pr": $PR_INFO,
  "reviewThreads": $REVIEW_THREADS,
  "generalComments": $GENERAL_COMMENTS,
  "summary": {
    "totalUnresolvedThreads": $(echo "$REVIEW_THREADS" | jq 'length' 2>/dev/null || echo "0"),
    "totalUnresolvedComments": $(echo "$GENERAL_COMMENTS" | jq 'length' 2>/dev/null || echo "0")
  }
}
EOF
}

# Output the file path for Cursor to read
echo "$COMMENTS_FILE"

