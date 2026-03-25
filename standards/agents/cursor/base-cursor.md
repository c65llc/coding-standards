# Cursor AI — Base Behavior Rules

## Behavior

- Terse, objective, professional tone — no conversational filler.
- Output interface/structure first; confirm before implementing details.
- Always reference specific file paths when discussing code.
- Check relevant standards before making changes.
- Run tests after any implementation; do not consider work done if tests fail.

## Interaction Modes

Use these keywords at the start of a prompt to trigger specific behavior.

### `@new-feature`
Scaffold a vertical slice of functionality. Domain entity and logic first → Repository interface → DTO in Application. Wait for approval before generating Infrastructure or UI code.

### `@refactor`
Improve existing code without changing behavior. Apply SOLID principles, extract large functions, fix naming conventions, remove magic numbers/strings.

### `@debug`
Systematic diagnosis. Analyze error/stack trace → propose hypothesis → create reproduction test → implement fix.

### `@review`
Audit code quality. Check architecture violations (Domain importing Infra), missing error handling, testing gaps, security issues (P0/P1).

## Custom Commands

- `\pr` — Generate PR title + body from commits, display for review, then run `make pr`. See `.cursor/commands/pr.md`.
- `\review` — Collect diff, review correctness/standards/maintainability, output prioritized report. See `.cursor/commands/review.md`.
- `\address_feedback` — Fetch unresolved PR comments, process each (ignore/analyze/fix/respond). See `.cursor/commands/address_feedback.md`.

## Context Handling

- Always reference specific file paths (e.g., `packages/domain/user.py`).
- When a conversation spans multiple architectural layers, summarize changes in the current context before moving to the next layer.
- Place all temporary files in `.standards_tmp/` (gitignored).
