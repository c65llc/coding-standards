#!/bin/bash
# Check: scan for hardcoded secrets/keys in source files
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="no-secrets"

# Directories and file patterns to exclude from scanning
EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    ".standards"
    ".standards_tmp"
    "vendor"
    "dist"
    "build"
    ".next"
    "__pycache__"
    ".venv"
    "venv"
)

# Build find exclusion args
EXCLUDE_ARGS=()
for dir in "${EXCLUDE_DIRS[@]}"; do
    EXCLUDE_ARGS+=(-not -path "*/$dir/*")
done

# Exclude common lock files and binary files
EXCLUDE_FILES=(
    "*.lock"
    "package-lock.json"
    "yarn.lock"
    "Cargo.lock"
    "Gemfile.lock"
    "*.min.js"
    "*.min.css"
    "*.map"
    "*.png"
    "*.jpg"
    "*.jpeg"
    "*.gif"
    "*.ico"
    "*.pdf"
    "*.zip"
    "*.tar"
    "*.gz"
)

EXCLUDE_FILE_ARGS=()
for pattern in "${EXCLUDE_FILES[@]}"; do
    EXCLUDE_FILE_ARGS+=(-not -name "$pattern")
done

# Build file list
SOURCE_FILES=$(find "$PROJECT_ROOT" -type f \
    "${EXCLUDE_ARGS[@]}" \
    "${EXCLUDE_FILE_ARGS[@]}" \
    2>/dev/null)

if [ -z "$SOURCE_FILES" ]; then
    echo "WARN $CHECK_NAME No source files found to scan"
    exit 2
fi

# Secret patterns to scan for
MATCHES=""

# AWS access key pattern
aws_matches=$(echo "$SOURCE_FILES" | xargs grep -lE 'AKIA[0-9A-Z]{16}' 2>/dev/null || true)
[ -n "$aws_matches" ] && MATCHES="${MATCHES}AWS keys in: $(echo "$aws_matches" | head -3 | tr '\n' ' '); "

# Private key blocks
pk_matches=$(echo "$SOURCE_FILES" | xargs grep -lE '\-\-\-\-\-BEGIN.*(PRIVATE|RSA|EC|DSA) KEY' 2>/dev/null || true)
[ -n "$pk_matches" ] && MATCHES="${MATCHES}Private keys in: $(echo "$pk_matches" | head -3 | tr '\n' ' '); "

# Hardcoded passwords (not in comments, not test fixtures)
pwd_matches=$(echo "$SOURCE_FILES" | xargs grep -lE 'password\s*=\s*["'"'"'][^"'"'"']{4,}["'"'"']' 2>/dev/null \
    | grep -vE '(test|spec|fixture|example|sample|mock|dummy)' || true)
[ -n "$pwd_matches" ] && MATCHES="${MATCHES}Hardcoded passwords in: $(echo "$pwd_matches" | head -3 | tr '\n' ' '); "

# API keys
api_matches=$(echo "$SOURCE_FILES" | xargs grep -lE 'api_key\s*=\s*["'"'"'][^"'"'"']{8,}["'"'"']' 2>/dev/null \
    | grep -vE '(test|spec|fixture|example|sample|mock|dummy)' || true)
[ -n "$api_matches" ] && MATCHES="${MATCHES}Hardcoded API keys in: $(echo "$api_matches" | head -3 | tr '\n' ' '); "

# Secret tokens
secret_matches=$(echo "$SOURCE_FILES" | xargs grep -lE '(secret|token)\s*=\s*["'"'"'][^"'"'"']{8,}["'"'"']' 2>/dev/null \
    | grep -vE '(test|spec|fixture|example|sample|mock|dummy|placeholder|your[-_])' || true)
[ -n "$secret_matches" ] && MATCHES="${MATCHES}Hardcoded secrets/tokens in: $(echo "$secret_matches" | head -3 | tr '\n' ' '); "

if [ -z "$MATCHES" ]; then
    echo "PASS $CHECK_NAME No hardcoded secrets detected"
    exit 0
else
    # Trim trailing semicolon+space
    MATCHES="${MATCHES%; }"
    echo "FAIL $CHECK_NAME Potential secrets found — $MATCHES"
    exit 1
fi
