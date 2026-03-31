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

2. For each declared agent, determine the paths:

   | Agent | Base Template | Output File |
   |-------|--------------|-------------|
   | `claude-code` | `.standards/standards/agents/claude-code/base-claude-code.md` | `CLAUDE.md` |
   | `cursor` | `.standards/standards/agents/cursor/base-cursor.md` | `.cursorrules` |
   | `copilot` | `.standards/standards/agents/copilot/base-copilot.md` | `.github/copilot-instructions.md` |
   | `gemini` | `.standards/standards/agents/gemini/base-gemini.md` | `.gemini/GEMINI.md` |
   | `aider` | `.standards/standards/agents/aider/base-aider.md` | `.aider-instructions.md` |
   | `codex` | `.standards/standards/agents/codex/base-codex.md` | `AGENTS.md` |

3. Run the assembly script for each agent:

   ```bash
   .standards/scripts/assemble-config.sh \
     <agent> \
     .standards/standards/shared/blocks/ \
     <base-template> \
     <output-file> \
     lang-<language1>.md lang-<language2>.md role-<role>.md
   ```

   The script automatically includes the common blocks in order:
   1. `architecture-core.md`
   2. `testing-policy.md`
   3. `security-summary.md`
   4. `naming-conventions.md`
   5. `git-workflow.md`
   6. `documentation-policy.md`

   Then appends the language and role blocks you specify.

4. The assembler respects the `<!-- BEGIN PROJECT-SPECIFIC` sentinel — any content below it in an existing output file is preserved across re-assembly.

5. If the output file has been customized (checksum mismatch), the assembler writes to `.standards-pending/` instead of overwriting. Use the `merge-standards` skill to resolve these.

## Checksum System

Generated configs are tracked in `.standards-checksums`. The assembler:

- Computes SHA256 of the generated (non-custom) portion of the file
- Compares against the stored hash
- If hashes match → safe to overwrite (no customization)
- If hashes differ → file was customized → write to `.standards-pending/` instead

## After Assembly

Report: "Assembled configs for N agents. M files written, K pending (customized files — run merge-standards to resolve)."
