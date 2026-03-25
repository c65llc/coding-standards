# Smart Sync & Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent sync-standards from overwriting customized agent configs by adding checksum-based detection, a Claude Code `/merge-standards` skill, and an agent-agnostic merge prompt doc.

**Architecture:** Checksum logic wraps `assemble-config.sh` calls in setup.sh and sync-standards.sh (assembler stays pure). Customized files are skipped and pending updates staged to `.standards-pending/`. A Claude Code skill and prompt doc enable AI-powered merge for all agents.

**Tech Stack:** Bash (scripts), Markdown (skill, prompt doc), `shasum -a 256` (checksums)

**Spec:** `docs/superpowers/specs/2026-03-25-smart-sync-merge-design.md`

---

## Task Group A: Checksum Infrastructure (Sequential)

### Task 1: Add `compute_hash` and checksum helpers to a shared library

**Files:**

- Create: `scripts/lib/checksums.sh`

This is a sourceable library of functions used by both setup.sh and sync-standards.sh. Keeps the checksum logic DRY.

- [ ] **Step 1: Create the library file**

```bash
#!/bin/bash
# Shared checksum functions for standards assembly scripts.
# Source this file — do not execute directly.

CHECKSUMS_FILE=".standards-checksums"
PENDING_DIR=".standards-pending"
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
ASSEMBLY_HEADER="Assembled by coding-standards"

# Compute SHA256 of assembler-controlled content (above sentinel, whitespace-normalized)
compute_hash() {
    local file="$1"
    local content
    if grep -qF "$SENTINEL" "$file" 2>/dev/null; then
        content=$(sed "/$SENTINEL/,\$d" "$file" | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
    else
        content=$(cat "$file" | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
    fi
    printf '%s' "$content" | shasum -a 256 | awk '{print $1}'
}

# Read stored hash for a given file path from the checksums file
read_stored_hash() {
    local checksums_path="$1"
    local file_key="$2"
    if [ -f "$checksums_path" ]; then
        grep "  ${file_key}$" "$checksums_path" 2>/dev/null | awk '{print $1}'
    fi
}

# Update or add a hash entry in the accumulated checksums (in-memory variable)
# Usage: NEW_CHECKSUMS=$(update_checksum_entry "$NEW_CHECKSUMS" "$hash" "$file_key")
update_checksum_entry() {
    local current="$1"
    local hash="$2"
    local file_key="$3"
    # Remove existing entry for this file, add new one
    local filtered
    filtered=$(echo "$current" | grep -v "  ${file_key}$" 2>/dev/null || true)
    if [ -n "$filtered" ]; then
        printf '%s\n%s  %s' "$filtered" "$hash" "$file_key"
    else
        printf '%s  %s' "$hash" "$file_key"
    fi
}

# Check if a file has the assembly header comment
has_assembly_header() {
    local file="$1"
    grep -qF "$ASSEMBLY_HEADER" "$file" 2>/dev/null
}

# Write pending update to .standards-pending/
write_pending() {
    local project_root="$1"
    local filename="$2"
    local assembled_content_file="$3"
    local pending_dir="$project_root/$PENDING_DIR"
    mkdir -p "$pending_dir"
    {
        echo "<!-- Standards update pending — your current file has customizations that would be lost."
        echo "     Claude Code: run /merge-standards to intelligently merge."
        echo "     Other agents: see .standards/docs/reference/merge-standards-prompt.md -->"
        echo ""
        cat "$assembled_content_file"
    } > "$pending_dir/$filename"
}

# Determine if assembly should proceed for a given output file.
# Returns: 0 = assemble normally, 1 = skip (customized), 2 = skip (manual, backed up)
# Sets OUTPUT_REDIRECT to the actual path to write to (output file or temp for pending)
should_assemble() {
    local project_root="$1"
    local output_path="$2"
    local checksums_path="$3"
    local file_key
    file_key=$(basename "$output_path")

    # File doesn't exist — assemble normally
    if [ ! -f "$output_path" ]; then
        return 0
    fi

    local stored_hash
    stored_hash=$(read_stored_hash "$checksums_path" "$file_key")

    if [ -z "$stored_hash" ]; then
        # No stored hash — file predates checksum system
        if has_assembly_header "$output_path"; then
            # Has assembly header — safe to overwrite
            return 0
        else
            # Manually created — back up and skip
            local backup="${output_path}.pre-standards-setup"
            cp "$output_path" "$backup"
            echo "⚠️  Backed up manually-created $file_key to ${file_key}.pre-standards-setup" >&2
            return 2
        fi
    fi

    local current_hash
    current_hash=$(compute_hash "$output_path")

    if [ "$current_hash" = "$stored_hash" ]; then
        # Unchanged — safe to overwrite
        return 0
    else
        # Customized — skip
        return 1
    fi
}
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n scripts/lib/checksums.sh`
Expected: No output (valid syntax)

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/checksums.sh
git commit -m "feat(scripts): add shared checksum library for assembly protection

Portable SHA256 functions for detecting customized agent configs.
Used by setup.sh and sync-standards.sh to wrap assembly calls."
```

### Task 2: Integrate checksums into `sync-standards.sh`

**Files:**

- Modify: `scripts/sync-standards.sh`

This is the critical script — it runs on every sync and must detect customized files.

- [ ] **Step 1: Source the checksum library**

Add near the top of the file, after `SCRIPT_DIR` and `PROJECT_ROOT` declarations:

```bash
# Source checksum helpers
CHECKSUMS_LIB=""
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    CHECKSUMS_LIB="$SCRIPT_DIR/lib/checksums.sh"
elif [ -n "$STANDARDS_DIR" ] && [ -f "$STANDARDS_DIR/scripts/lib/checksums.sh" ]; then
    CHECKSUMS_LIB="$STANDARDS_DIR/scripts/lib/checksums.sh"
fi
if [ -n "$CHECKSUMS_LIB" ]; then
    # shellcheck source=lib/checksums.sh
    source "$CHECKSUMS_LIB"
fi
```

- [ ] **Step 2: Add checksum accumulator and wrap the assembly loop**

In the `sync_ai_agents` function, before the `for agent in $AGENTS_LIST` loop:

```bash
    local CHECKSUMS_PATH="$PROJECT_ROOT/$CHECKSUMS_FILE"
    local NEW_CHECKSUMS=""
    # Load existing checksums as starting point
    if [ -f "$CHECKSUMS_PATH" ]; then
        NEW_CHECKSUMS=$(cat "$CHECKSUMS_PATH")
    fi
```

- [ ] **Step 3: Replace the direct assembly call with checksum-guarded logic**

Replace the current assembly block (lines 148-153) with:

```bash
        # Check if file has been customized
        local file_key
        file_key=$(basename "$OUTPUT_PATH")

        if [ -n "$CHECKSUMS_LIB" ]; then
            should_assemble "$PROJECT_ROOT" "$OUTPUT_PATH" "$CHECKSUMS_PATH"
            local assemble_result=$?

            if [ $assemble_result -eq 1 ]; then
                # Customized — assemble to temp, stage as pending
                local TEMP_FILE
                TEMP_FILE=$(mktemp)
                if "$ASSEMBLE_SCRIPT" "$agent" "$BLOCKS_DIR" "$BASE_TEMPLATE" "$TEMP_FILE" ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"}; then
                    write_pending "$PROJECT_ROOT" "$file_key" "$TEMP_FILE"
                    echo "⚠️  $file_key has been customized since last assembly. Skipping overwrite."
                    echo "   Pending update written to .standards-pending/$file_key"
                    echo "   Claude Code: run /merge-standards to merge. Others: see .standards/docs/reference/merge-standards-prompt.md"
                fi
                rm -f "$TEMP_FILE"
                continue
            elif [ $assemble_result -eq 2 ]; then
                # Manually created, already backed up — skip
                continue
            fi
        fi

        # Safe to assemble (unchanged or new file)
        echo "📝 Re-assembling $agent config..."
        if "$ASSEMBLE_SCRIPT" "$agent" "$BLOCKS_DIR" "$BASE_TEMPLATE" "$OUTPUT_PATH" ${BLOCK_ARGS[@]+"${BLOCK_ARGS[@]}"}; then
            echo "✅ $agent config synced"
            # Record checksum of assembled file
            if [ -n "$CHECKSUMS_LIB" ]; then
                local new_hash
                new_hash=$(compute_hash "$OUTPUT_PATH")
                NEW_CHECKSUMS=$(update_checksum_entry "$NEW_CHECKSUMS" "$new_hash" "$file_key")
            fi
        else
            echo "⚠️  Failed to sync $agent config (non-fatal, continuing...)"
        fi
```

- [ ] **Step 4: Add Aider `.aiderrc` checksum protection**

Replace the current Aider `cmp -s` block with checksum-guarded logic:

```bash
        # Aider special handling: sync aiderrc.template to .aiderrc (with checksum protection)
        if [ "$agent" = "aider" ] && [ -f "$AGENTS_DIR/aider/aiderrc.template" ]; then
            local aiderrc_path="$PROJECT_ROOT/.aiderrc"
            local aiderrc_key=".aiderrc"
            if [ -n "$CHECKSUMS_LIB" ] && [ -f "$aiderrc_path" ]; then
                local aiderrc_stored
                aiderrc_stored=$(read_stored_hash "$CHECKSUMS_PATH" "$aiderrc_key")
                if [ -n "$aiderrc_stored" ]; then
                    local aiderrc_current
                    aiderrc_current=$(shasum -a 256 "$aiderrc_path" | awk '{print $1}')
                    if [ "$aiderrc_current" != "$aiderrc_stored" ]; then
                        echo "⚠️  .aiderrc has been customized. Skipping overwrite."
                        echo "   Template available at: .standards/standards/agents/aider/aiderrc.template"
                        continue
                    fi
                fi
            fi
            if cp "$AGENTS_DIR/aider/aiderrc.template" "$aiderrc_path" 2>/dev/null; then
                echo "   ✅ Aider .aiderrc synced"
                if [ -n "$CHECKSUMS_LIB" ]; then
                    local rc_hash
                    rc_hash=$(shasum -a 256 "$aiderrc_path" | awk '{print $1}')
                    NEW_CHECKSUMS=$(update_checksum_entry "$NEW_CHECKSUMS" "$rc_hash" "$aiderrc_key")
                fi
            fi
        fi
```

- [ ] **Step 5: Write checksums atomically at end of function**

After the agent loop ends, before the function returns:

```bash
    # Write checksums atomically
    if [ -n "$CHECKSUMS_LIB" ] && [ -n "$NEW_CHECKSUMS" ]; then
        echo "$NEW_CHECKSUMS" > "$CHECKSUMS_PATH"
    fi
```

- [ ] **Step 6: Add skill file sync and .gitignore update**

After the checksum write:

```bash
    # Sync merge-standards skill
    local SKILL_SOURCE=""
    if [ -n "$STANDARDS_DIR" ] && [ -f "$STANDARDS_DIR/standards/agents/claude-code/skills/merge-standards.md" ]; then
        SKILL_SOURCE="$STANDARDS_DIR/standards/agents/claude-code/skills/merge-standards.md"
    fi
    if [ -n "$SKILL_SOURCE" ]; then
        mkdir -p "$PROJECT_ROOT/.claude/skills"
        if ! cmp -s "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md" 2>/dev/null; then
            cp "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md"
            echo "✅ /merge-standards skill updated"
        fi
    fi

    # Ensure .standards-pending/ is gitignored
    if [ -f "$PROJECT_ROOT/.gitignore" ]; then
        if ! grep -q ".standards-pending" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
            echo ".standards-pending/" >> "$PROJECT_ROOT/.gitignore"
        fi
    fi
```

- [ ] **Step 7: Verify syntax**

Run: `bash -n scripts/sync-standards.sh`
Expected: No output

- [ ] **Step 8: Commit**

```bash
git add scripts/sync-standards.sh
git commit -m "feat(sync): add checksum-based protection for customized agent configs

sync-standards.sh now detects customized files via SHA256 checksums.
Customized files are skipped and pending updates staged to .standards-pending/.
Checksums written atomically at end of sync run."
```

### Task 3: Integrate checksums into `setup.sh`

**Files:**

- Modify: `scripts/setup.sh`

Setup.sh is simpler — it runs on first install, so it mainly needs to record checksums after assembly.

- [ ] **Step 1: Source the checksum library**

Add after the argument parsing block, before `setup_ai_agents`:

```bash
# Source checksum helpers
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck source=lib/checksums.sh
    source "$SCRIPT_DIR/lib/checksums.sh"
fi
```

- [ ] **Step 2: Add checksum recording after assembly in the agent loop**

After the successful assembly line (`echo "✅ $agent config assembled"`), add:

```bash
            # Record checksum of assembled file
            if type compute_hash &>/dev/null; then
                local new_hash
                new_hash=$(compute_hash "$OUTPUT_PATH")
                NEW_CHECKSUMS=$(update_checksum_entry "$NEW_CHECKSUMS" "$new_hash" "$(basename "$OUTPUT_PATH")")
            fi
```

- [ ] **Step 3: Add checksum recording for Aider .aiderrc**

After the Aider `.aiderrc` copy block, add:

```bash
            if type compute_hash &>/dev/null; then
                local rc_hash
                rc_hash=$(shasum -a 256 "$PROJECT_ROOT/.aiderrc" | awk '{print $1}')
                NEW_CHECKSUMS=$(update_checksum_entry "$NEW_CHECKSUMS" "$rc_hash" ".aiderrc")
            fi
```

- [ ] **Step 4: Initialize accumulator and write checksums at end of function**

Add `local NEW_CHECKSUMS=""` at the top of `setup_ai_agents`, and at the end:

```bash
    # Write initial checksums file
    if type compute_hash &>/dev/null && [ -n "$NEW_CHECKSUMS" ]; then
        echo "$NEW_CHECKSUMS" > "$PROJECT_ROOT/$CHECKSUMS_FILE"
        echo "✅ .standards-checksums created"
    fi
```

- [ ] **Step 5: Copy the merge-standards skill**

Add after the checksums write:

```bash
    # Install merge-standards skill
    local SKILL_SOURCE="$AGENTS_DIR/claude-code/skills/merge-standards.md"
    if [ -f "$SKILL_SOURCE" ]; then
        mkdir -p "$PROJECT_ROOT/.claude/skills"
        cp "$SKILL_SOURCE" "$PROJECT_ROOT/.claude/skills/merge-standards.md"
        echo "✅ /merge-standards skill installed"
    fi
```

- [ ] **Step 6: Add `.standards-pending/` to .gitignore additions**

In the `.gitignore` section, add:

```bash
    if ! grep -q ".standards-pending" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        echo ".standards-pending/" >> "$PROJECT_ROOT/.gitignore"
    fi
```

- [ ] **Step 7: Verify syntax**

Run: `bash -n scripts/setup.sh`
Expected: No output

- [ ] **Step 8: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat(setup): record checksums after assembly, install merge skill

setup.sh now writes .standards-checksums after first assembly and
copies /merge-standards skill to .claude/skills/."
```

---

## Task Group B: Skill & Prompt Doc (Independent of Group A)

### Task 4: Create the `/merge-standards` Claude Code skill

**Files:**

- Create: `standards/agents/claude-code/skills/merge-standards.md`

- [ ] **Step 1: Write the skill file**

This is a markdown instruction document that Claude Code loads when `/merge-standards` is invoked.

```markdown
---
name: merge-standards
description: Intelligently merge pending standards updates into customized agent configs
---

# Merge Standards Updates

Merge pending standards updates into agent configs that have been customized.

## When to Use

Run this after `sync-standards` reports that agent configs have been customized and pending updates exist in `.standards-pending/`.

## Workflow

1. List files in `.standards-pending/`. If empty, report: "All agent configs are up to date — no pending standards updates."

2. For each pending file (e.g., `.standards-pending/CLAUDE.md`):
   a. Read the **current customized file** at its normal location (e.g., `CLAUDE.md`)
   b. Read the **pending assembled version** in `.standards-pending/`
   c. Produce a merged version using the merge strategy below
   d. Show the user a diff of the proposed merge
   e. On approval: write the merged file, update the checksum, delete the pending file
   f. On rejection: leave both files as-is

3. After all files are processed, delete `.standards-pending/` if empty.

## Merge Strategy

Standards sections are identified by `##` headers: `## Architecture`, `## Testing`, `## Security`, `## Naming Conventions`, `## Git Workflow`, `## Documentation`, `## Language Standards`, `## Project Type`.

**Standards sections:**

- Identical in both files → no change
- Pending version has **new rules** → add them to the current file
- Pending version **changed a rule** → update to the new version
- Current file has **extra content** within the section (user additions) → preserve it

**Content outside standards sections** (project overview, key commands, custom sections added by the user):

- Always preserve the current version

**Content below `<!-- BEGIN PROJECT-SPECIFIC`:**

- Keep as-is from the current file

**When ambiguous** (a standards rule was changed AND the user had a customization of the same rule):

- Include both and add: `<!-- REVIEW: standards updated this rule, but you had a customization. Verify which is correct. -->`

## After Merging

For each successfully merged file:

1. Update `.standards-checksums` with the new hash. Compute it by running:

   ```bash
   # Extract content above sentinel, strip trailing blank lines, hash
   SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
   content=$(sed "/$SENTINEL/,\$d" "$file" | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
   hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')
   ```

   Replace the line for this file in `.standards-checksums` with the new hash.

1. Delete the consumed file from `.standards-pending/`.

1. Report a summary: "Merged N files. Added X new rules, updated Y rules, preserved Z customizations, flagged W for review."

- [ ] **Step 2: Commit**

```bash
git add standards/agents/claude-code/skills/merge-standards.md
git commit -m "feat(skill): add /merge-standards Claude Code skill

AI-powered merge for pending standards updates. Reads .standards-pending/,
merges section-by-section preserving customizations, updates checksums."
```

### Task 5: Create the agent-agnostic merge prompt doc

**Files:**

- Create: `docs/reference/merge-standards-prompt.md`

- [ ] **Step 1: Write the prompt doc**

```markdown
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
- **Pending update:** The file in `.standards-pending/` (e.g., `.standards-pending/CLAUDE.md`)

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
# Compute hash of content above the sentinel marker
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
file="CLAUDE.md"  # replace with the actual filename

if grep -qF "$SENTINEL" "$file"; then
    content=$(sed "/$SENTINEL/,\$d" "$file" | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
else
    content=$(cat "$file" | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
fi
hash=$(printf '%s' "$content" | shasum -a 256 | awk '{print $1}')

echo "$hash  $(basename "$file")"
# Replace the matching line in .standards-checksums with this output
```

### 4. Clean Up

Delete the consumed file from `.standards-pending/`. If the directory is now empty, delete it too.

## Regenerating Pending Files

If `.standards-pending/` was lost (branch switch, `git clean`), re-run `sync-standards` to regenerate the pending files.

- [ ] **Step 2: Commit**

```bash
git add docs/reference/merge-standards-prompt.md
git commit -m "docs: add agent-agnostic merge-standards prompt doc

Instructions any AI agent can follow to merge pending standards updates
while preserving customizations. Referenced by .standards-pending/ files."
```

---

## Task Group C: Base Template Updates & Makefile (Independent)

### Task 6: Add merge workflow note to all agent base templates

**Files:**

- Modify: `standards/agents/claude-code/base-claude-code.md`
- Modify: `standards/agents/cursor/base-cursor.md`
- Modify: `standards/agents/copilot/base-copilot.md`
- Modify: `standards/agents/gemini/base-gemini.md`
- Modify: `standards/agents/aider/base-aider.md`
- Modify: `standards/agents/codex/base-codex.md`

- [ ] **Step 1: Add one line to each template's conventions/constraints section**

Add this line to each base template in the appropriate section (Conventions for Claude Code, Constraints for Gemini, Behavior for others):

```text
If sync-standards reports customized files, pending updates are in .standards-pending/. See .standards/docs/reference/merge-standards-prompt.md to merge.
```

Read each file first to find the right section to add it to.

- [ ] **Step 2: Commit**

```bash
git add standards/agents/*/base-*.md
git commit -m "docs(agents): add merge workflow note to all base templates

Each agent template now mentions .standards-pending/ and points to
the merge prompt doc for resolving pending standards updates."
```

### Task 7: Update Makefile test target

**Files:**

- Modify: `Makefile`

- [ ] **Step 1: Add checksums library to test-scripts**

Add after the existing `assemble-config.sh` test line:

```makefile
	@echo "Testing lib/checksums.sh..."
	@bash -n scripts/lib/checksums.sh && echo "✅ lib/checksums.sh syntax valid"
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "chore(makefile): add checksums.sh to test-scripts target"
```

---

## Task Group D: Validation (Depends on A, B, C)

### Task 8: Run full test suite and manual validation

**Files:**

- Reference: `Makefile`

- [ ] **Step 1: Run `make test-scripts`**

Run: `make test-scripts`
Expected: All scripts pass `bash -n` syntax validation, including new `scripts/lib/checksums.sh`.

- [ ] **Step 2: Test the full flow — first assembly (no checksums yet)**

```bash
# Assemble a test config
./scripts/assemble-config.sh claude-code standards/shared/blocks standards/agents/claude-code/base-claude-code.md /tmp/test-merge-flow.md lang-python.md role-service.md

# Manually create a checksums file as setup.sh would
source scripts/lib/checksums.sh
hash=$(compute_hash /tmp/test-merge-flow.md)
echo "$hash  CLAUDE.md" > /tmp/test-checksums
echo "Initial hash: $hash"
```

- [ ] **Step 3: Test customization detection**

```bash
# Simulate user customization
echo "## My Custom Convention" >> /tmp/test-merge-flow.md
echo "Always use descriptive variable names in this project." >> /tmp/test-merge-flow.md

# Verify hash changed
new_hash=$(compute_hash /tmp/test-merge-flow.md)
echo "After customization: $new_hash"
[ "$hash" != "$new_hash" ] && echo "DETECTED: hashes differ" || echo "BUG: hashes match"
```

- [ ] **Step 4: Test `should_assemble` detection**

```bash
# Copy test file to simulate project structure
mkdir -p /tmp/test-project
cp /tmp/test-merge-flow.md /tmp/test-project/CLAUDE.md
cp /tmp/test-checksums /tmp/test-project/.standards-checksums

should_assemble "/tmp/test-project" "/tmp/test-project/CLAUDE.md" "/tmp/test-project/.standards-checksums"
result=$?
echo "should_assemble returned: $result"
[ $result -eq 1 ] && echo "CORRECT: detected as customized" || echo "BUG: should be 1 (customized)"
```

- [ ] **Step 5: Test pending file write**

```bash
# Write a pending update
./scripts/assemble-config.sh claude-code standards/shared/blocks standards/agents/claude-code/base-claude-code.md /tmp/test-pending.md lang-python.md role-service.md
write_pending "/tmp/test-project" "CLAUDE.md" /tmp/test-pending.md

# Verify pending file exists with header
head -3 /tmp/test-project/.standards-pending/CLAUDE.md
```

- [ ] **Step 6: Test idempotency — unmodified file passes through**

```bash
# Create a fresh file and matching checksum
./scripts/assemble-config.sh claude-code standards/shared/blocks standards/agents/claude-code/base-claude-code.md /tmp/test-project/CLEAN.md lang-python.md role-service.md
clean_hash=$(compute_hash /tmp/test-project/CLEAN.md)
echo "$clean_hash  CLEAN.md" >> /tmp/test-project/.standards-checksums

should_assemble "/tmp/test-project" "/tmp/test-project/CLEAN.md" "/tmp/test-project/.standards-checksums"
result=$?
echo "should_assemble returned: $result"
[ $result -eq 0 ] && echo "CORRECT: unchanged, safe to overwrite" || echo "BUG: should be 0"
```

- [ ] **Step 7: Test missing checksums recovery**

```bash
# Remove checksums file, test file with assembly header
rm /tmp/test-project/.standards-checksums
should_assemble "/tmp/test-project" "/tmp/test-project/CLEAN.md" "/tmp/test-project/.standards-checksums"
result=$?
echo "No checksums, has header: $result"
[ $result -eq 0 ] && echo "CORRECT: has assembly header, safe to overwrite" || echo "BUG"
```

- [ ] **Step 8: Clean up test artifacts**

```bash
rm -rf /tmp/test-project /tmp/test-merge-flow.md /tmp/test-pending.md /tmp/test-checksums
```

---

## Execution Order Summary

| Group | Tasks | Dependencies | Can Parallelize? |
|---|---|---|---|
| A (Checksum infra) | 1, 2, 3 | Sequential (1→2→3) | No |
| B (Skill & doc) | 4, 5 | None | Yes — both independent |
| C (Templates & Makefile) | 6, 7 | None | Yes — both independent |
| D (Validation) | 8 | A + B + C complete | No |

**Maximum parallelism:** Groups B and C can run simultaneously with Group A. Group D runs last.
