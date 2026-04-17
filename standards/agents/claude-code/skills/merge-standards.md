---
name: merge-standards
description: Intelligently merge pending standards updates into customized agent configs
---

# Merge Standards Updates

Merge pending standards updates into agent configs that have been customized.

## When to Use

Run this after `sync-standards` reports that agent configs have been customized and pending updates exist in `.standards-pending/`.

## Setup-time behavior

When invoked immediately after `setup.sh`, `.standards-pending/MERGE_PLAN.md` exists and lists the files to reconcile. Read it first; it names each pending file, detected vs requested agents, and any `<!-- TODO(standards): -->` markers that need filling.

For **empty targets** (the project had no existing config and `.standards-pending/` still contains the assembled version because `--agents detect` found it), the merge is a rename: move the pending file into place, update `.standards-checksums`, and delete the pending copy.

For **`<!-- TODO(standards): -->` markers** in CLAUDE.md and friends: ask the user for a one-paragraph project overview and a list of key commands (or infer them from `package.json` scripts / Makefile targets) and replace the markers in place before completing the merge.

## Workflow

1. List files in `.standards-pending/`. If the directory is empty or doesn't exist, report: "All agent configs are up to date — no pending standards updates."

2. For each pending file (e.g., `.standards-pending/CLAUDE.md`):
   a. Read the **current customized file** at its normal location (e.g., `CLAUDE.md`)
   b. Read the **pending assembled version** in `.standards-pending/` (skip the first 3 lines — those are the instruction comment header)
   c. Produce a merged version using the merge strategy below
   d. Show the user a diff of current vs. proposed merged version
   e. On approval: write the merged file, update the checksum, delete the pending file
   f. On rejection: leave both files as-is, move to next file

3. After all files are processed, delete `.standards-pending/` if empty.

## Merge Strategy

Standards sections are identified by `##` headers injected by the assembler: `## Architecture`, `## Testing`, `## Security`, `## Naming Conventions`, `## Git Workflow`, `## Documentation`, `## Language Standards`, `## Project Type`.

**Standards sections:**

- Identical in both files → no change
- Pending version has **new rules** not in current → add them to the current file in the appropriate section
- Pending version **changed a rule** (different wording for same concept) → update to the new version
- Current file has **extra content** within a standards section (user additions like project-specific conventions) → preserve it

**Content outside standards sections** (project overview, key commands, custom sections the user or /claude-md-improver added):

- Always preserve the current version — never replace or remove user-authored sections

**Content below the `<!-- BEGIN PROJECT-SPECIFIC` sentinel:**

- Keep as-is from the current file

**When ambiguous** (a standard rule changed AND the user had a customization of the same rule):

- Include both and add: `<!-- REVIEW: standards updated this rule, but you had a customization. Verify which is correct. -->`

## After Merging Each File

1. Update `.standards-checksums` with the new hash:

   ```bash
   SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
   content=$(sed "/$SENTINEL/,\$d" "$file" | awk 'NF{found=1} found' | awk '{lines[NR]=$0} END{for(i=NR;i>=1;i--){if(lines[i]~/[^ \t]/){last=i;break}} for(i=1;i<=last;i++) print lines[i]}')
   hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')
   ```

   Replace the line matching this file in `.standards-checksums` with: `<hash>  <filename>`

1. Delete the consumed file from `.standards-pending/`.

1. After all files: report a summary — "Merged N files. Added X new rules, updated Y rules, preserved Z customizations, flagged W for review."
