#!/bin/bash
# Check: CI steps must pass on a locked, headless, interchangeable runner
#        (arch-08 §6). Flags workflow steps that need an unlocked desktop or
#        the runner's login keychain: `notarytool store-credentials`,
#        `security unlock-keychain` on the login keychain, `osascript`,
#        and `open -a`.
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="headless-ci"

# Collect workflow and composite-action files. Both run on the runner; a
# composite action can smuggle a GUI dependency into every caller.
WORKFLOW_FILES=""
for dir in "$PROJECT_ROOT/.github/workflows" "$PROJECT_ROOT/.github/actions"; do
    [ -d "$dir" ] || continue
    found=$(find "$dir" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)
    if [ -n "$found" ]; then
        WORKFLOW_FILES="${WORKFLOW_FILES}${WORKFLOW_FILES:+
}${found}"
    fi
done

if [ -z "$WORKFLOW_FILES" ]; then
    echo "PASS $CHECK_NAME No GitHub Actions workflows found (nothing to check)"
    exit 0
fi

# Parallel arrays: PATTERNS[i] is the ERE to grep for, LABELS[i] is what the
# finding reports. `open -a` must not match e.g. a `--open -a` flag or
# `xdg-open -a`, so it is anchored on a preceding non-word character; an
# optional `<dir>/` prefix still catches `/usr/bin/open -a`.
PATTERNS=(
    'store-credentials'
    'unlock-keychain[^#]*login'
    'osascript'
    '(^|[^[:alnum:]_./-])([[:alnum:]_./-]*/)?open[[:space:]]+-a([[:space:]]|$)'
)
LABELS=(
    'store-credentials'
    'unlock-keychain on login keychain'
    'osascript'
    'open -a'
)

FINDINGS=""
FILE_COUNT=0

while IFS= read -r file; do
    [ -n "$file" ] || continue
    FILE_COUNT=$((FILE_COUNT + 1))

    # Drop comment-only lines (YAML or shell) so a "never do X" note does not
    # trip the check; only executable text counts.
    content=$(grep -vE '^[[:space:]]*#' "$file" 2>/dev/null || true)
    [ -n "$content" ] || continue

    file_hits=""
    i=0
    while [ "$i" -lt "${#PATTERNS[@]}" ]; do
        if printf '%s\n' "$content" | grep -qE "${PATTERNS[$i]}" 2>/dev/null; then
            file_hits="${file_hits}${file_hits:+, }${LABELS[$i]}"
        fi
        i=$((i + 1))
    done

    if [ -n "$file_hits" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        FINDINGS="${FINDINGS}${FINDINGS:+; }${rel}: ${file_hits}"
    fi
done <<EOF
$WORKFLOW_FILES
EOF

if [ -z "$FINDINGS" ]; then
    echo "PASS $CHECK_NAME No GUI or login-keychain dependencies in $FILE_COUNT workflow file(s)"
    exit 0
fi

echo "WARN $CHECK_NAME Steps need an unlocked desktop or login keychain (arch-08 §6: pass secrets to the command or use a job-scoped keychain) — $FINDINGS"
exit 2
