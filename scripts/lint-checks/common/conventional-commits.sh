#!/bin/bash
# Check: conventional commits on recent commits
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="conventional-commits"

# Ensure we're in a git repo
if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "WARN $CHECK_NAME Not a git repository — skipping commit check"
    exit 2
fi

# Count commits that don't match conventional commits pattern
bad_commits=$(git -C "$PROJECT_ROOT" log --oneline -10 --format="%s" 2>/dev/null \
    | grep -cvE '^(feat|fix|refactor|test|docs|chore|perf|ci|build|style|revert)(\(.+\))?(\!)?:' \
    || true)

total=$(git -C "$PROJECT_ROOT" log --oneline -10 --format="%s" 2>/dev/null | wc -l | tr -d ' ')

if [ "$total" -eq 0 ]; then
    echo "WARN $CHECK_NAME No commits found to check"
    exit 2
fi

if [ "$bad_commits" -eq 0 ]; then
    echo "PASS $CHECK_NAME All recent commits follow Conventional Commits format"
    exit 0
elif [ "$bad_commits" -le 3 ]; then
    echo "WARN $CHECK_NAME $bad_commits of last $total commits don't follow Conventional Commits"
    exit 2
else
    echo "FAIL $CHECK_NAME $bad_commits of last $total commits don't follow Conventional Commits"
    exit 1
fi
