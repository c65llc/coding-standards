# [Project Name] — Claude Code Guide

## Project Summary

[One paragraph describing what this project does, its primary use case, and key technologies.]

---

## Key Commands

```bash
make check          # Compile/type-check all targets
make lint           # Run linters (warnings are errors)
make test           # Unit + integration tests
make ci             # Full pipeline: check → fmt → lint → test
make fmt            # Auto-format code
make ls             # List all make targets with descriptions
```

Package-scoped testing (if applicable):
```bash
# cargo test -p my-package     (Rust)
# pnpm --filter my-package test (Node)
```

---

## Workspace Layout

```
apps/                # Deployable applications
packages/            # Shared libraries (dependency direction: inward only)
tools/               # Build scripts, generators, dev tools
docs/                # Architecture docs, ADRs, development guides
  adr/               # Architecture Decision Records
```

---

## Architecture Rules

### Dependency Direction
- Inner layers have zero knowledge of outer layers.
- Apps depend on packages. Packages never depend on apps.
- **Never add an inward→outward dependency.**

### [Project-Specific Invariants]
- [Document critical invariants here, e.g., "All offsets are char-based, not byte-based"]
- [Include concrete examples of how invariants break]

---

## Error Handling

- **Libraries:** Typed error enums. Use `Result<T, E>` for all fallible operations.
- **Apps:** Contextual error wrappers for debugging.
- **UI event handlers:** Log and continue. Never panic on expected errors.

---

## Testing

- **Structure:** Inline test modules within source files. Integration tests in `tests/` directory.
- **Coverage baselines:**

| Layer | Min Coverage |
|-------|-------------|
| Core / Domain | 100% |
| Application / Shell | 95% |
| Infrastructure | 95% |

---

## Key Source Files

| File | Purpose |
|------|---------|
| [path/to/main/module] | [Brief description] |
| [path/to/core/types] | [Brief description] |

---

## Commit Message Format

Follow Conventional Commits: `type(scope): subject`

**Types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`
**Scope:** module name or area

---

## What NOT To Do

- [Anti-pattern 1: describe what to avoid and why]
- [Anti-pattern 2: describe what to avoid and why]
- Do not modify the root checkout from an automated agent session — use a git worktree.

---

## Agent Workflow — Worktree Requirement

**All agent-based development work MUST be completed in a git worktree.**

```bash
git worktree add .claude/worktrees/<branch-name> -b <branch-name>
cd .claude/worktrees/<branch-name>
# Work here. Run make ci before considering work complete.
```

Never modify files in the root checkout from an automated agent session.
