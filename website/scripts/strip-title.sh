#!/bin/bash
# strip-title.sh <file> — delete a Markdown file's leading "# " heading.
# Starlight renders the frontmatter title as the page h1, so a copied document
# that also opens with its own heading shows the title twice. Only the first
# non-blank line after any frontmatter is considered.
set -e

file="$1"
tmp="$(mktemp)"
awk '
    NR == 1 && $0 == "---" { front = 1; print; next }
    front { print; if ($0 == "---") front = 0; next }
    !seen && NF { seen = 1; if ($0 ~ /^# /) next }
    { print }
' "$file" > "$tmp"
cat "$tmp" > "$file"
rm -f "$tmp"
