---
title: "Merge Standards Updates"
---

# Merge Standards Updates

When `sync-standards` detects that your agent configs have been customized, it stages pending updates in `.standards-pending/` instead of overwriting your files. This document explains how to merge those updates.

**Claude Code users:** Run `/merge-standards` instead of following this guide — the skill automates the entire process.

## What Happened

1. You (or a tool like `/claude-md-improver`) customized an agent config file (e.g., `CLAUDE.md`)
2. `sync-standards` pulled updated standards blocks
3. The sync detected your customizations via checksum comparison
4. Instead of overwriting, it wrote the updated version to `.standards-pending/<filename>`

## How to Merge

For each file in `.standards-pending/`:

### 1. Read Both Files

- **Current file:** The customized version at its normal location (e.g., `CLAUDE.md`)
- **Pending update:** The file in `.standards-pending/` (skip the first 3 lines — instruction comment)

### 2. Merge Section by Section

Standards sections are marked by `##` headers: Architecture, Testing, Security, Naming Conventions, Git Workflow, Documentation, Language Standards, Project Type.

For each standards section:

- **Identical content** → no change needed
- **New rules in pending version** → add them to your file
- **Changed rules in pending version** → update to the new wording
- **Your additions within the section** → keep them

For content outside standards sections (project overview, key commands, custom sections you added):

- **Always keep your version**

For content below `<!-- BEGIN PROJECT-SPECIFIC`:

- **Keep as-is**

### 3. Update the Checksum

After merging, update `.standards-checksums` so the next sync knows this file is current:

```bash
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
file="CLAUDE.md"  # replace with the actual filename

if grep -qF "$SENTINEL" "$file"; then
    content=$(sed "/$SENTINEL/,\$d" "$file")
else
    content=$(cat "$file")
fi
# Strip trailing blank lines and compute hash
hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')

echo "$hash  $(basename "$file")"
# Replace the matching line in .standards-checksums with this output
```

### 4. Clean Up

Delete the consumed file from `.standards-pending/`. If the directory is now empty, remove it.

## Regenerating Pending Files

If `.standards-pending/` was lost (branch switch, `git clean`), re-run `sync-standards` to regenerate pending files.
