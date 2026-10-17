# AGENTS.md

Instructions for OpenAI Codex CLI.

## Environment

- Runs in a sandboxed container with an isolated filesystem.
- Network access may be restricted — do not assume external services are reachable.
- No interactive commands; all operations must be non-interactive and scriptable.

## Behavior

- Read project structure first (`ls`, read key files) before making any changes.
- Apply language-specific conventions by detecting file extensions.
- Run tests after implementation; do not mark a task complete if tests fail.
- Follow TDD for bug fixes and new features: write the failing test first.

## Approval Mode

**Suggest mode (default):** Explain the planned change before editing any file. Wait for confirmation.

**Auto mode:** Make changes directly with atomic commits and Conventional Commits messages (`type(scope): subject`). Each commit must represent one logical change.

## Constraints

- Do not modify generated files, lock files, or CI configuration unless explicitly requested.
- Do not add new dependencies without explaining why and listing alternatives considered.
- Make minimal changes — touch only the files required to satisfy the task.
- No secrets or credentials in any file; check before committing config files.
- If sync-standards reports customized files, pending updates are in `.standards-pending/`. See `.standards/docs/reference/merge-standards-prompt.md` to merge.

## Known Traps

Project-specific pitfalls that have already cost a debugging session. Each row carries the issue that documented it and the date it was recorded, so a reader can judge whether it is still live. Add a row whenever a bug's root cause was "the agent did not know this"; delete the row when the trap is engineered away and say so in the issue.

| Trap | Why it bites | Issue | Date |
|------|--------------|-------|------|
| Example: run `make ci` from the repo root, not from a package directory | Sub-make targets resolve paths from the working directory and silently skip suites | #000 | YYYY-MM-DD |
