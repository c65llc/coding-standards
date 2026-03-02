#!/bin/bash
# Syncs documentation and standards into Starlight content directory
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WEBSITE_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$WEBSITE_DIR")"
CONTENT_DIR="$WEBSITE_DIR/src/content/docs"

echo "Syncing content from repo to Starlight..."

# Clean previous synced content (but keep index.mdx and any manually created pages)
rm -rf "$CONTENT_DIR/getting-started" "$CONTENT_DIR/guides" "$CONTENT_DIR/reference" "$CONTENT_DIR/standards"
rm -f "$CONTENT_DIR/changelog.md"

# Copy docs
cp -r "$REPO_ROOT/docs/getting-started" "$CONTENT_DIR/getting-started"
cp -r "$REPO_ROOT/docs/guides" "$CONTENT_DIR/guides"
cp -r "$REPO_ROOT/docs/reference" "$CONTENT_DIR/reference"
cp "$REPO_ROOT/docs/changelog.md" "$CONTENT_DIR/changelog.md"

# Copy standards (need to add frontmatter)
mkdir -p "$CONTENT_DIR/standards/architecture"
mkdir -p "$CONTENT_DIR/standards/languages"
mkdir -p "$CONTENT_DIR/standards/process"

add_frontmatter() {
    local file="$1"
    local dest="$2"

    # Extract title from first H1 heading, or use filename
    local title
    title=$(grep -m1 '^# ' "$file" | sed 's/^# //' || basename "$file" .md)

    # Check if file already has frontmatter
    if head -1 "$file" | grep -q '^---$'; then
        cp "$file" "$dest"
    else
        {
            echo "---"
            echo "title: \"$title\""
            echo "---"
            echo ""
            cat "$file"
        } > "$dest"
    fi
}

# Copy architecture standards
for f in "$REPO_ROOT"/standards/architecture/*.md; do
    [ -f "$f" ] || continue
    add_frontmatter "$f" "$CONTENT_DIR/standards/architecture/$(basename "$f")"
done

# Copy language standards
for f in "$REPO_ROOT"/standards/languages/*.md; do
    [ -f "$f" ] || continue
    add_frontmatter "$f" "$CONTENT_DIR/standards/languages/$(basename "$f")"
done

# Copy process standards
for f in "$REPO_ROOT"/standards/process/*.md; do
    [ -f "$f" ] || continue
    add_frontmatter "$f" "$CONTENT_DIR/standards/process/$(basename "$f")"
done

# Copy shared standards if exists
if [ -d "$REPO_ROOT/standards/shared" ]; then
    mkdir -p "$CONTENT_DIR/standards/shared"
    for f in "$REPO_ROOT"/standards/shared/*.md; do
        [ -f "$f" ] || continue
        add_frontmatter "$f" "$CONTENT_DIR/standards/shared/$(basename "$f")"
    done
fi

echo "Content sync complete."
