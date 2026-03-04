#!/bin/bash
# Build a merged .claude/settings.json from a base template and language-specific permissions.
#
# Usage: ./build-claude-settings.sh <base_template> <permissions_dir> [lang1 lang2 ...]
#
# Example:
#   ./build-claude-settings.sh settings.json.example permissions/ python rust
#
# If no languages are provided, reads them from stdin (one per line).
# Outputs valid JSON to stdout.

set -e

BASE_TEMPLATE="${1:?Usage: build-claude-settings.sh <base_template> <permissions_dir> [lang1 lang2 ...]}"
PERMISSIONS_DIR="${2:?Usage: build-claude-settings.sh <base_template> <permissions_dir> [lang1 lang2 ...]}"

shift 2

# Collect language keys from args or stdin
LANGUAGES=()
if [ $# -gt 0 ]; then
    LANGUAGES=("$@")
else
    while IFS= read -r lang; do
        [ -n "$lang" ] && LANGUAGES+=("$lang")
    done
fi

# If no languages detected, just output the base template
if [ ${#LANGUAGES[@]} -eq 0 ]; then
    cat "$BASE_TEMPLATE"
    exit 0
fi

# Collect all extra permission lines from detected languages into a temp file
TMPFILE="$(mktemp "${TMPDIR:-/tmp}/claude-settings.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT

for lang in "${LANGUAGES[@]}"; do
    PERM_FILE="$PERMISSIONS_DIR/${lang}.txt"
    if [ -f "$PERM_FILE" ]; then
        while IFS= read -r line; do
            # Strip leading/trailing whitespace
            line="$(echo "$line" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
            [ -z "$line" ] && continue
            case "$line" in \#*) continue ;; esac
            echo "$line" >> "$TMPFILE"
        done < "$PERM_FILE"
    fi
done

# If no extra permissions found, output base template as-is
if [ ! -s "$TMPFILE" ]; then
    cat "$BASE_TEMPLATE"
    exit 0
fi

# Use awk to insert extra entries before the closing ] of the "allow" array.
# Strategy: store all lines, find the allow array's closing ], insert before it.
awk -v extras_file="$TMPFILE" '
BEGIN {
    # Read extra permissions
    n = 0
    while ((getline line < extras_file) > 0) {
        extras[n++] = line
    }
    close(extras_file)
}
{
    lines[NR] = $0
}
END {
    # Find "allow" array boundaries
    in_allow = 0
    allow_close = 0
    for (i = 1; i <= NR; i++) {
        if (lines[i] ~ /"allow"/) in_allow = 1
        if (in_allow && lines[i] ~ /^[[:space:]]*\]/) {
            allow_close = i
            break
        }
    }

    if (allow_close == 0 || n == 0) {
        # No allow array found or no extras — output as-is
        for (i = 1; i <= NR; i++) print lines[i]
    } else {
        # Find last real entry before closing ] to determine indent
        entry_indent = "      "
        last_entry = 0
        for (i = allow_close - 1; i >= 1; i--) {
            if (lines[i] ~ /^[[:space:]]*"/) {
                match(lines[i], /^[[:space:]]*/)
                entry_indent = substr(lines[i], 1, RLENGTH)
                last_entry = i
                break
            }
        }

        for (i = 1; i <= NR; i++) {
            if (i == last_entry) {
                # Ensure trailing comma on last existing entry
                line = lines[i]
                gsub(/[[:space:]]+$/, "", line)
                if (line !~ /,$/) line = line ","
                print line
            } else if (i == allow_close) {
                # Insert extras before closing ]
                for (j = 0; j < n; j++) {
                    if (j < n - 1) {
                        printf "%s\"%s\",\n", entry_indent, extras[j]
                    } else {
                        printf "%s\"%s\"\n", entry_indent, extras[j]
                    }
                }
                print lines[i]
            } else {
                print lines[i]
            }
        }
    }
}
' "$BASE_TEMPLATE"
