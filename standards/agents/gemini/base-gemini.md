# Gemini CLI — Base Behavior Rules

## Workflow: A-P-E Cycle

### Analyze

Read relevant files to understand the current state. Do not assume — verify.

- Read the file(s) you plan to modify before touching them.
- Check existing patterns and naming conventions.
- Identify all files affected by the planned change.

### Plan

State your intent before executing. Wait for confirmation on non-trivial changes.

- Output a "Proposed Logic Plan" listing every file to be modified.
- Identify breaking changes or dependency impacts.
- For multi-file refactors, get explicit approval before proceeding.

### Execute

Implement, test, verify — in that order.

- Prefer `gemini edit` (diff mode) over blind overwrites.
- Run tests after each logical change.
- Commit atomically with Conventional Commits messages.

## Checkpointing

Maintain `.gemini/active_mission.log` (gitignored) with timestamped steps for any task spanning multiple files or sessions.

## Safety Constraints

- Never modify: `.git/`, `node_modules/`, `.standards_tmp/`, files ending in `.secret` or `.tfstate`.
- Preserve existing standards file numbering (e.g., `arch-01_`, `lang-01_`).
- Run tests before committing; do not commit broken code.
- Ask when uncertain about scope or approach — do not guess on destructive operations.
- Create a new branch for any non-trivial change; never commit directly to `main`.
- If sync-standards reports customized files, pending updates are in `.standards-pending/`. See `.standards/docs/reference/merge-standards-prompt.md` to merge.

## Tool Usage

- Read before modifying — always.
- Run `git diff` before committing to verify the change matches intent.
- Commits must be atomic (one logical change per commit) and follow Conventional Commits format.
- Reference specific file paths in all responses and explanations.

## Known Traps

Project-specific pitfalls that have already cost a debugging session. Each row carries the issue that documented it and the date it was recorded, so a reader can judge whether it is still live. Add a row whenever a bug's root cause was "the agent did not know this"; delete the row when the trap is engineered away and say so in the issue.

| Trap | Why it bites | Issue | Date |
|------|--------------|-------|------|
| Example: run `make ci` from the repo root, not from a package directory | Sub-make targets resolve paths from the working directory and silently skip suites | #000 | YYYY-MM-DD |
