# Smart Sync & Merge — Design Spec

**Date:** 2026-03-25
**Status:** Draft
**Goal:** Prevent `sync-standards` from overwriting customized agent configs. Provide an AI-powered merge path via Claude Code skill and agent-agnostic prompt doc.

---

## Problem Statement

After the block assembly system is in place, `sync-standards.sh` re-assembles agent configs from updated blocks. If a user has customized a config (e.g., via `/claude-md-improver` or manual edits), the re-assembly overwrites everything above the `<!-- BEGIN PROJECT-SPECIFIC -->` sentinel — project overview, key commands, refined conventions, and other improvements are lost.

The sentinel only protects content below the marker. Content above it — which is the majority of what `/claude-md-improver` enriches — has no protection.

## Design Decisions

- **Checksum-based detection** in `assemble-config.sh` for all agents — agent-agnostic, deterministic, no git dependency.
- **Skip-and-stage pattern** — customized files are never overwritten. Pending updates go to `.standards-pending/`.
- **Claude Code skill** (`/merge-standards`) for AI-powered merge with diff approval.
- **Agent prompt doc** (`docs/reference/merge-standards-prompt.md`) so Gemini, Codex, Cursor, and Aider users can perform the same merge when prompted.

---

## 1. Checksum Detection in `assemble-config.sh`

### Mechanism

After assembling a config file, the script computes a SHA256 hash of the content **above** the sentinel marker and stores it in `.standards-checksums`.

On subsequent assembly runs:

```text
1. Does the output file exist?
   ├─ No  → assemble normally, record checksum
   └─ Yes → compute hash of current content above sentinel
            ├─ Matches stored hash → unchanged since last assembly → overwrite, update checksum
            └─ Differs from stored hash → customized →
                 a) Skip overwriting
                 b) Write would-be assembled version to .standards-pending/<filename>
                 c) Warn user
                 d) Leave current file untouched
```

### `.standards-checksums` Format

One line per file, `sha256sum`-compatible:

```text
a1b2c3d4e5f6...  CLAUDE.md
f7g8h9i0j1k2...  .cursorrules
l3m4n5o6p7q8...  .github/copilot-instructions.md
r9s0t1u2v3w4...  .gemini/GEMINI.md
x5y6z7a8b9c0...  AGENTS.md
d1e2f3g4h5i6...  .aider-instructions.md
```

This file is committed to git so the team shares the same baseline.

### `.standards-pending/` Directory

Each pending file includes a header comment:

```text
<!-- Standards update pending — your current file has customizations that would be lost.
     Claude Code: run /merge-standards to intelligently merge.
     Other agents: see .standards/docs/reference/merge-standards-prompt.md -->
```

The directory is added to `.gitignore` (transient — consumed by the merge process).

### Hash Computation

Extract content above the sentinel, pipe to `sha256sum`:

```bash
# Extract content above sentinel (or entire file if no sentinel)
if grep -qF "$SENTINEL" "$file" 2>/dev/null; then
    content=$(sed "/$SENTINEL/,\$d" "$file")
else
    content=$(cat "$file")
fi
echo "$content" | sha256sum | awk '{print $1}'
```

### Warning Output

When a customized file is detected:

```text
⚠️  CLAUDE.md has been customized since last assembly. Skipping overwrite.
   Pending update written to .standards-pending/CLAUDE.md
   Claude Code: run /merge-standards to merge. Others: see .standards/docs/reference/merge-standards-prompt.md
```

---

## 2. Claude Code Skill — `/merge-standards`

### Location

- Source: `standards/agents/claude-code/skills/merge-standards.md`
- Deployed to: `$PROJECT_ROOT/.claude/skills/merge-standards.md`

### Trigger

User invokes `/merge-standards` in Claude Code.

### Behavior

1. Check `.standards-pending/` for pending update files.
2. If empty: report "All agent configs are up to date — no pending standards updates."
3. For each pending file:
   a. Read the **current customized file** (e.g., `CLAUDE.md`)
   b. Read the **pending assembled version** (e.g., `.standards-pending/CLAUDE.md`)
   c. Produce a **merged version** following the merge strategy (below)
   d. Show the diff to the user for approval
   e. On approval: write merged file, update `.standards-checksums`, delete pending file
   f. On rejection: leave both files as-is, user can manually edit
4. When all pending files are processed, remove `.standards-pending/` if empty.

### Merge Strategy

Standards sections are identified by the `##` headers injected by the assembler: `## Architecture`, `## Testing`, `## Security`, `## Naming Conventions`, `## Git Workflow`, `## Documentation`, `## Language Standards`, `## Project Type`.

**For each standards section:**

- If the section is identical in both files → no action needed
- If the pending version has **new rules** not in the current file → add them
- If the pending version **changed a rule** → update to the new version
- If the current file has **extra content** within the section (user additions) → preserve it

**For content outside standards sections** (project overview, key commands, custom sections added by the user or `/claude-md-improver`):

- Always preserve the current version

**For the project-specific section** (below the sentinel):

- Keep as-is from the current file

**When ambiguous:**

- Include both versions and add a `<!-- REVIEW: standards updated this rule, but you had a customization. Verify which is correct. -->` comment

### Skill File Content (approximate)

The skill file is a markdown instruction document that Claude Code loads when `/merge-standards` is invoked. It contains:

- Description of the merge workflow
- Instructions to read `.standards-pending/` files
- The merge strategy rules above
- Instructions to show diffs and get approval
- Instructions to update `.standards-checksums` after merge
- Cleanup steps

---

## 3. Agent Prompt Doc — `merge-standards-prompt.md`

### Location

`docs/reference/merge-standards-prompt.md`

Accessible in consumer projects via the `.standards/` submodule at `.standards/docs/reference/merge-standards-prompt.md`.

### Content

A standalone document any AI agent can follow. Contains:

1. **Context:** What happened (sync detected customizations, pending updates staged)
2. **Files to read:** Current config at its normal path + pending version in `.standards-pending/`
3. **Merge rules:** Same strategy as the Claude Code skill (section-by-section merge, preserve user additions, update standards content)
4. **Checksum update:** How to compute and write the new hash to `.standards-checksums`
5. **Cleanup:** Delete consumed files from `.standards-pending/`

### Discovery

Agents find this doc via:

- The header comment in `.standards-pending/` files
- The warning message from `sync-standards.sh`
- A one-line note in each agent base template's conventions section

---

## 4. Setup & Distribution

### `setup.sh` Changes

- Create `$PROJECT_ROOT/.claude/skills/` directory if it doesn't exist
- Copy `standards/agents/claude-code/skills/merge-standards.md` to `$PROJECT_ROOT/.claude/skills/merge-standards.md`
- Add `.standards-pending/` to `.gitignore`

### `sync-standards.sh` Changes

- Update the skill file if it has changed (simple copy — skill is not customizable)
- Add `.standards-pending/` to `.gitignore` if not already present

### Agent Base Template Changes

Add one line to each base template's conventions/constraints section:

```text
If sync-standards warns about customized files, pending updates are in .standards-pending/. See .standards/docs/reference/merge-standards-prompt.md to merge.
```

### `.standards-checksums` Lifecycle

| Event | Action |
|---|---|
| First `setup.sh` run | Created with hashes of all assembled files |
| Subsequent `assemble-config.sh` | Compared against, updated on successful overwrite |
| `/merge-standards` or manual merge | Updated with hash of merged file |
| Committed to git | Yes — team shares the baseline |

---

## 5. File Changes Summary

| File | Change |
|---|---|
| `scripts/assemble-config.sh` | Add checksum read/compare/write, `.standards-pending/` staging, skip-and-warn logic |
| `scripts/setup.sh` | Copy skill to `.claude/skills/`, add `.standards-pending/` to `.gitignore` |
| `scripts/sync-standards.sh` | Update skill file on sync, add `.standards-pending/` to `.gitignore` |
| `standards/agents/claude-code/skills/merge-standards.md` | **New** — Claude Code skill for AI-powered merge |
| `docs/reference/merge-standards-prompt.md` | **New** — agent-agnostic merge instructions |
| `standards/agents/*/base-*.md` | Add one-line merge workflow note to conventions |

---

## 6. Success Criteria

1. **No data loss:** Customized configs are never overwritten. Pending updates go to `.standards-pending/`.
2. **Clean pass-through:** Unmodified configs are updated in place — no behavior change for untouched files.
3. **Claude Code path:** `/merge-standards` reads pending files, shows diffs, merges on approval, updates checksums, cleans up.
4. **Other agent path:** `merge-standards-prompt.md` provides equivalent instructions any agent can follow.
5. **Checksum reliable:** SHA256 of content above sentinel correctly detects any modification.
6. **Idempotent:** Running sync twice with no changes produces no pending updates and no warnings.
7. **Existing tests pass:** `make test-scripts` validates all modified scripts.
