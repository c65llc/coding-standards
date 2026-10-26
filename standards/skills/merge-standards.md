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

For **`<!-- TODO(standards): -->` markers** in CLAUDE.md and friends: ask the user for a one-paragraph project overview and a list of key commands (or infer them from `package.json` scripts / Makefile targets). **Write them to `.standards.yml`, not only into the file:**

```yaml
project_overview: |
  One paragraph: what this project is and how its pieces fit together.
key_commands: |
  make test        # run the test suite
  make lint        # lint and format checks
```

Then re-run `./.standards/scripts/sync-standards.sh` (or replace the markers in place with the same text). The assembler reads these keys into `{{PROJECT_OVERVIEW}}` / `{{KEY_COMMANDS}}`, so the file stays byte-identical to its assembly and its checksum keeps matching; text edited only in the file is flagged as customized on every later sync.

For **sections already filled in by hand** (setup or sync printed `💡 ... has a filled-in Project Overview / Key Commands that .standards.yml does not persist` followed by the YAML to add): append exactly that YAML to `.standards.yml`, then re-run the sync — it records the file as current instead of staging a pending copy.

For **a config the user wants to keep hand-curated end to end** (repo-specific guidance that a regenerate would flatten): declare it in `.standards.yml` and leave it alone:

```yaml
managed:
  CLAUDE.md: false
```

Sync and setup then never regenerate or stage it, `doctor` reports it as curated, and `diff-standards.sh` keeps showing upstream template changes for manual review. Offer this only when `project_overview` / `key_commands` and the PROJECT-SPECIFIC section cannot hold the customisation — a curated file stops receiving standards updates.

If `doctor` fails on `post-merge hook not installed` and the project manages its own hooks (`make hooks`, lefthook, husky), declare `hooks: custom` (or `lefthook` / `husky`) in `.standards.yml`.

## After `setup.sh --migrate` (pre-1.2 install)

When `MERGE_PLAN.md` has a **Migration** section, the pending files are the project's old hand-rolled configs (dead standards references already rewritten in place; originals kept as `<file>.pre-standards-setup`) staged beside the freshly assembled versions. Treat the assembled version as the base and carry over only genuinely project-specific text into its PROJECT-SPECIFIC section — the old files are mostly a stale copy of the standards themselves. Also:

- `AGENTS.md` converted from `.codexrc` (or `.standards-pending/AGENTS.md.from-codexrc` when an `AGENTS.md` already existed): keep any project notes, adopt the assembled `AGENTS.md`, delete `.codexrc` if it is still there.
- *Still cites a removed standard*: for each `file:line`, delete the sentence or point it at the replacement named in the Notes column of `.standards/docs/reference/renamed-files.md`.
- The recorded checksum of a staged file is the **staged assembled version**, so adopting it as-is needs no checksum update; a merged file needs the recomputed hash as usual.

## Workflow

1. List files in `.standards-pending/`, recursively: a staged skill file keeps its project-relative path (`.standards-pending/.claude/skills/security-gate/SKILL.md` belongs to `.claude/skills/security-gate/SKILL.md`), and `MERGE_PLAN.md` is the briefing, not a pending file. If the directory is empty or doesn't exist, report: "All agent configs are up to date — no pending standards updates."

2. For each pending file (e.g., `.standards-pending/CLAUDE.md`):
   a. Read the **current customized file** at its normal location (e.g., `CLAUDE.md`)
   b. Read the **pending assembled version** in `.standards-pending/` (for an assembled config, skip the first 3 lines — the instruction comment header; a staged skill file has no header and is the complete new version)
   c. Produce a merged version using the merge strategy below
   d. Show the user a diff of current vs. proposed merged version
   e. On approval: write the merged file, update the checksum, delete the pending file
   f. On rejection: leave both files as-is, move to next file

3. For a **staged skill file**, the project's file was kept because the standards never installed it, or it was edited since they did. Show the diff between the project's file and the staged version. On approval, replace the file with the staged version and record its hash under its project-relative path; on rejection, delete the staged copy — the next sync stages it again only while the two still differ, and says so.

4. For a **staged containerized kit file** (`MERGE_PLAN.md` has a *Containerized agent-dev kit* section; paths such as `Dockerfile.dev`, `scripts/init-workspace.sh`, `proxy/tinyproxy.conf`), the section-based strategy below does not apply: these are shell scripts, Dockerfiles and proxy configs, not assembled Markdown. Show a plain diff of the project's file against the staged copy. On approval write the merged result (normally the project's adaptations carried onto the kit's changes), keep the execute bit on anything with a shebang (`chmod +x`), and do **not** add it to `.standards-checksums` — kit files are templates to adapt and are never checksum-tracked. Delete the staged copy either way; re-running `setup.sh --containerized` stages it again only while the two still differ.

5. After all files are processed, delete `.standards-pending/` if empty.

## Merge Strategy

Standards sections are identified by `##` headers injected by the assembler: `## Architecture`, `## Testing`, `## Security`, `## Naming Conventions`, `## Git Workflow`, `## Documentation`, `## Language Standards`, `## Project Type`, `## Profiles`.

**Standards sections:**

- Identical in both files → no change
- Pending version has **new rules** not in current → add them to the current file in the appropriate section
- Pending version **changed a rule** (different wording for same concept) → update to the new version
- Current file has **extra content** within a standards section (user additions like project-specific conventions) → preserve it

**Content outside standards sections** (project overview, key commands, custom sections the user or a guide-improver tool added):

- Always preserve the current version — never replace or remove user-authored sections
- Project overview and key commands: persist the current text as `project_overview:` / `key_commands:` in `.standards.yml` when they are not there yet, so the merged file matches its next assembly

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

   Replace the line matching this file in `.standards-checksums` with: `<filename> <hash>` — the key is the basename for an assembled config (`CLAUDE.md`) and the project-relative path for a skill file (`.claude/skills/<name>/SKILL.md`). A skill file is hashed whole (`shasum -a 256 <file>`), not with the snippet above: that stops at the first sentinel mention, and some runbooks mention the sentinel in their text.

1. Delete the consumed file from `.standards-pending/`.

1. After all files: report a summary — "Merged N files. Added X new rules, updated Y rules, preserved Z customizations, flagged W for review."
