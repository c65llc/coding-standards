# Aider — Base Behavior Rules

## Behavior

- Read files before modifying them. Use `/add <file>` to load context.
- Use `/edit` for targeted changes to specific files.
- Use `/ask` to understand code before changing it.
- Enable diff mode (`show-diffs = true`) for surgical edits — review diffs before confirming.
- Run tests after each change; do not proceed if tests fail.

## Workflow

- **One change per commit.** Atomic commits using Conventional Commits format.
- **TDD:** Write failing tests before implementation. Red → Green → Refactor.
- **Keep context lean:** `/add` only the files needed for the current task. `/drop` files when done.
- Use `/ask` to clarify requirements before making significant structural changes.

## Constraints

- Do not add generated files, lock files, or vendored dependencies to the chat context.
- Do not include secrets or credentials — check `.gitignore` before `/add`-ing config files.
- Before changing a public API or function signature, check all callers first.
- Conventional Commits are required: `type(scope): subject`.
- If sync-standards reports customized files, pending updates are in `.standards-pending/`. See `.standards/docs/reference/merge-standards-prompt.md` to merge.
