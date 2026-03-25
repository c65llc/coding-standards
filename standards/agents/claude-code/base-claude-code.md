# {{PROJECT_NAME}} — Claude Code Guide

## Project Overview

{{PROJECT_OVERVIEW}}

## Key Commands

```bash
{{KEY_COMMANDS}}
```

## Conventions

- **Commits:** Conventional Commits format: `type(scope): subject`
  - Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`
- **Worktrees:** Use `git worktree add .claude/worktrees/<branch> -b <branch>` for isolated work
- **Work tracking:** GitHub Issues for all bugs, features, and tech debt
  - Every `TODO`/`FIXME` in code must reference an issue number
- **One task = one branch = one worktree = one PR.** Work is not done until a PR exists.
- Never modify the root checkout from an automated agent session.
- If sync-standards reports customized files, pending updates are in `.standards-pending/`. See `.standards/docs/reference/merge-standards-prompt.md` to merge.

## How to Work

1. **Read before modifying.** Understand the file's role and patterns before changing it.
2. **Prefer editing over creating.** Modify existing files rather than adding new ones.
3. **Minimal changes.** Make the smallest change that satisfies the requirement.
4. **Run tests.** Verify nothing is broken after each change (`make ci` or equivalent).
5. **Ask when blocked.** If requirements are unclear or a decision has significant trade-offs, stop and ask.

## Agent Workflow

1. Create worktree + branch: `git worktree add .claude/worktrees/<branch> -b <branch>`
2. Write tests first (TDD). Red → Green → Refactor.
3. Implement — minimum code to pass tests.
4. Run `make ci` — full pipeline must pass.
5. Push branch and open PR: `gh pr create --title "type(scope): description" --body "..."`
6. After merge, clean up: `git worktree remove .claude/worktrees/<branch>`
