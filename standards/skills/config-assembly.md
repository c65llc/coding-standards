---
name: config-assembly
description: Assemble agent configurations from content blocks and .standards.yml
---

# Config Assembly

Generate agent configuration files by composing content blocks based on the project's `.standards.yml`.

## When to Use

- After modifying `.standards.yml` (adding languages, changing role, etc.)
- When setting up a new agent in an existing standards-managed project
- When content blocks have been updated upstream and configs need regenerating
- When a user asks to "rebuild" or "reassemble" agent configs

## Workflow

1. Read `.standards.yml` at the project root. Extract:
   - `languages` — list of language keys (e.g., `[python, typescript]`)
   - `agents` — list of agent keys (e.g., `[claude-code, cursor, copilot]`)
   - `role` — project role (e.g., `service`, `library`, `app`, `data-pipeline`)
   - `worktree_dir` — the agent worktree root (default `.claude/worktrees`); the assembler resolves `{{WORKTREE_DIR}}` in every template to it

2. For each declared agent, determine the paths:

   | Agent | Base Template | Output File |
   |-------|--------------|-------------|
   | `claude-code` | `.standards/standards/agents/claude-code/base-claude-code.md` | `CLAUDE.md` |
   | `cursor` | `.standards/standards/agents/cursor/base-cursor.md` | `.cursorrules` |
   | `copilot` | `.standards/standards/agents/copilot/base-copilot.md` | `.github/copilot-instructions.md` |
   | `gemini` | `.standards/standards/agents/gemini/base-gemini.md` | `.gemini/GEMINI.md` |
   | `aider` | `.standards/standards/agents/aider/base-aider.md` | `.aider-instructions.md` |
   | `codex` | `.standards/standards/agents/codex/base-codex.md` | `AGENTS.md` |

3. Re-assemble through the checksum guard — never by running the pure assembler on a live config:

   ```bash
   .standards/scripts/sync-standards.sh --dry-run   # preview (or: .standards/scripts/diff-standards.sh)
   .standards/scripts/sync-standards.sh             # assemble every declared agent, guarded
   ```

   `sync-standards.sh` reads the declared agents, languages and role and runs `assemble-config.sh` once per agent through `assemble_agent_config_guarded` (`scripts/lib/assembly.sh`). To add an agent, declare it under `agents:` first — the sync assembles only what is declared. The guard is what makes steps 5–6 true: `assemble-config.sh` on its own reads neither `.standards-checksums` nor `managed:` and overwrites everything above the project-specific sentinel, so call it directly only with a scratch `<output-file>` (to inspect one assembly), never on `CLAUDE.md`, `AGENTS.md` or another installed config.

   Each assembly includes the common blocks in order:
   1. `architecture-core.md`
   2. `testing-policy.md`
   3. `security-summary.md`
   4. `naming-conventions.md`
   5. `git-workflow.md`
   6. `documentation-policy.md`

   then the language and role blocks for the declared `languages:` and `role:`, then one `profile-<name>.md` block per declared profile under `## Profiles` (#227). For `codex`, `gemini` and `aider` it also appends a `## Skills` index of `standards/skills/` (name, description, triggers, runbook path), since those agents read a single file.

4. The same sync emits the skills for the file-based agents (`assemble-skills.sh`, under the same guard): `claude-code` → `.claude/skills/<name>/SKILL.md`, `cursor` → `.cursor/commands/<name>.md`, `copilot` → `.github/prompts/<name>.prompt.md`. A file is rewritten only when its content changed; one the standards did not install, or that was edited since, is kept and the new version is staged to `.standards-pending/<path>`.

5. The assembler respects the `<!-- BEGIN PROJECT-SPECIFIC` sentinel — any content below it in an existing output file is preserved across re-assembly.

6. If the output file has been customized (checksum mismatch), the guarded sync stages the new assembly to `.standards-pending/` instead of overwriting. Use the `merge-standards` skill to resolve these. A file declared `managed: { <file>: false }` in `.standards.yml` is left alone entirely.

## Checksum System

Generated configs are tracked in `.standards-checksums`. The guard (`sync-standards.sh` and `setup.sh`, via `scripts/lib/assembly.sh`):

- Computes SHA256 of the generated (non-custom) portion of the file
- Compares against the stored hash
- If hashes match → safe to overwrite (no customization)
- If hashes differ → file was customized → write to `.standards-pending/` instead

## After Assembly

Report: "Assembled configs for N agents. M files written, K pending (customized files — run merge-standards to resolve)."
