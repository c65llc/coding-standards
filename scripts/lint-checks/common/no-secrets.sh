#!/bin/bash
# Check: scan for hardcoded secrets/keys in source files
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# File enumeration (tracked via git ls-files, untracked-not-ignored, pruned
# find fallback) lives in scripts/lib/lint-files.sh. This check uses --strict:
# every tracked file is scanned — the built-in directory exclusions and
# `.standards.yml` lint.exclude are NOT applied to tracked content, so a
# contributor cannot hide a committed secret by editing the config or placing
# the file under vendor/. Built-in exclusions still drop untracked worktrees
# and caches, which never reach CI.

PROJECT_ROOT="${1:-.}"

CHECK_NAME="no-secrets"

LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../lib/lint-files.sh
source "$LINT_LIB"

# Lock files, minified bundles, source maps and binary assets are never
# meaningful secret carriers; drop them by extension (case-insensitive).
# grep -I (in lint_grep_files) skips any remaining binaries.
EXCLUDE_FILES_ERE='(\.lock|\.min\.js|\.min\.css|\.map|\.png|\.jpe?g|\.gif|\.ico|\.pdf|\.zip|\.tar|\.gz|(^|/)(package-lock\.json|yarn\.lock|Cargo\.lock|Gemfile\.lock))$'

SOURCE_FILES=$(lint_list_files --strict "$PROJECT_ROOT" | grep -viE "$EXCLUDE_FILES_ERE" || true)

# Filenames containing a newline cannot be carried by the file list; report
# them rather than skipping them silently.
UNSCANNABLE=$(lint_unscannable_files --strict "$PROJECT_ROOT" | grep -viE "$EXCLUDE_FILES_ERE" || true)

if [ -z "$SOURCE_FILES" ] && [ -z "$UNSCANNABLE" ]; then
    if lint_scope_is_changed; then
        echo "PASS $CHECK_NAME No changed source files to scan"
        exit 0
    fi
    echo "WARN $CHECK_NAME No source files found to scan"
    exit 2
fi

# Secret patterns to scan for
MATCHES=""

# Helper: list files matching a pattern (batched grep, paths made relative)
grep_source_files() {
    lint_grep_files "$SOURCE_FILES" -lE "$1" | lint_strip_root "$PROJECT_ROOT"
}

# AWS access key pattern
aws_matches=$(grep_source_files 'AKIA[0-9A-Z]{16}' || true)
[ -n "$aws_matches" ] && MATCHES="${MATCHES}AWS keys in: $(echo "$aws_matches" | head -3 | tr '\n' ' '); "

# Private key blocks
pk_matches=$(grep_source_files '\-\-\-\-\-BEGIN.*(PRIVATE|RSA|EC|DSA) KEY' || true)
[ -n "$pk_matches" ] && MATCHES="${MATCHES}Private keys in: $(echo "$pk_matches" | head -3 | tr '\n' ' '); "

# Hardcoded passwords (not in comments, not test fixtures)
pwd_matches=$(grep_source_files 'password\s*=\s*["'"'"'][^"'"'"']{4,}["'"'"']' \
    | grep -vE '(test|spec|fixture|example|sample|mock|dummy)' || true)
[ -n "$pwd_matches" ] && MATCHES="${MATCHES}Hardcoded passwords in: $(echo "$pwd_matches" | head -3 | tr '\n' ' '); "

# API keys
api_matches=$(grep_source_files 'api_key\s*=\s*["'"'"'][^"'"'"']{8,}["'"'"']' \
    | grep -vE '(test|spec|fixture|example|sample|mock|dummy)' || true)
[ -n "$api_matches" ] && MATCHES="${MATCHES}Hardcoded API keys in: $(echo "$api_matches" | head -3 | tr '\n' ' '); "

# Secret tokens
secret_matches=$(grep_source_files '(secret|token)\s*=\s*["'"'"'][^"'"'"']{8,}["'"'"']' \
    | grep -vE '(test|spec|fixture|example|sample|mock|dummy|placeholder|your[-_])' || true)
[ -n "$secret_matches" ] && MATCHES="${MATCHES}Hardcoded secrets/tokens in: $(echo "$secret_matches" | head -3 | tr '\n' ' '); "

if [ -n "$UNSCANNABLE" ]; then
    n=$(echo "$UNSCANNABLE" | wc -l | tr -d ' ')
    MATCHES="${MATCHES}${n} file(s) not scanned (newline in filename): $(echo "$UNSCANNABLE" | head -3 | tr '\n' ' '); "
fi

if [ -z "$MATCHES" ]; then
    echo "PASS $CHECK_NAME No hardcoded secrets detected"
    exit 0
else
    # Trim trailing semicolon+space
    MATCHES="${MATCHES%; }"
    echo "FAIL $CHECK_NAME Potential secrets found — $MATCHES"
    exit 1
fi
