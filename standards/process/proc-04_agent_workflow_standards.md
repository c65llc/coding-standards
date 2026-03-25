# Agent Workflow Standards

**Governing principle: One task = one branch = one worktree = one PR.**

Every discrete piece of agent work follows the same end-to-end lifecycle: isolate, implement, verify, deliver via pull request. Work is not considered done until a PR exists.

## 1. End-to-End Agent Workflow

### The Complete Lifecycle

Every agent task MUST follow these steps in order:

1. **Create worktree + branch.**

   ```bash
   git worktree add .claude/worktrees/<branch-name> -b <branch-name>
   cd .claude/worktrees/<branch-name>
   ```

2. **Write tests first (TDD).** Red → Green → Refactor. No implementation code before a failing test.
3. **Implement.** Write the minimum code to pass tests. Maintain ≥ 95% coverage in all modified modules. Python code must pass `mypy --strict`.
4. **Run `make ci`.** The full pipeline must pass before proceeding.
5. **Push the branch.**

   ```bash
   git push -u origin <branch-name>
   ```

6. **Create a pull request.** Link to the relevant issue. Include `🤖 Generated with [Agent Name]` in the PR body.

   ```bash
   gh pr create --title "type(scope): description" --body "..."
   ```

7. **Clean up after merge.** Remove worktree, delete local branch, delete remote branch:

   ```bash
   git worktree remove .claude/worktrees/<branch-name>
   git branch -D <branch-name>
   git push origin --delete <branch-name>
   ```

### Workspace Isolation

* **Requirement:** AI agents MUST work in git worktrees, never the developer's root checkout.
* **Location:** Worktrees live in `.claude/worktrees/` (Claude Code), `.cursor/worktrees/` (Cursor), or equivalent per-agent directory.
* **Rationale:** The root checkout is the developer's active workspace. Agent modifications cause conflicts with IDE state (unsaved buffers, debug configurations, terminal sessions). Worktrees provide full isolation at near-zero cost.
* Never modify files in the root checkout from an automated agent session.
* Create a new worktree at the start of each feature/fix branch.

### Branch Naming

Agent branches MUST use the same `type/description` convention as human branches. Opaque IDs or numeric suffixes alone are not acceptable:

```text
feat/preview-scroll-optimization    ✓ descriptive
fix/sidebar-drag-crash              ✓ descriptive
worktree-agent-a0939472             ✗ opaque, impossible to triage
copilot/sub-pr-7                    ✗ meaningless without the PR
```

### Pre-Work Hygiene

Before starting new work, verify no stale agent worktrees or branches remain:

```bash
git worktree list            # should only show root checkout + active work
git branch --no-merged main  # audit for abandoned branches
```

## 2. Project-Level AI Guide

Every project SHOULD have a `CLAUDE.md` (or equivalent agent guide) at the repository root. This file is distinct from `.cursorrules` or `.github/copilot-instructions.md` — it documents project-specific context that evolves during development.

### Required Sections

| Section | Purpose |
|---------|---------|
| Project Summary | One paragraph describing what the project does |
| Key Commands | `make check`, `make lint`, `make test`, `make ci`, `make fmt`, `make ls` |
| Workspace Layout | Directory tree with purpose annotations |
| Architecture Rules | Dependency direction, critical invariants, "never do X" items |
| Error Handling | Library vs. app error patterns |
| Testing | Structure, coverage baselines, per-package commands |
| Key Source Files | Table mapping files to responsibilities |
| Commit Message Format | Conventional Commits reference with project-specific scopes |
| What NOT To Do | Explicit anti-patterns discovered during development |
| Agent Workflow | Worktree requirement, permission model |

### Guidelines

* Keep it under 300 lines. Link to detailed docs rather than inlining everything.
* Include concrete examples of invariants and how they break.
* Update it as the project evolves — it is a living document, not a one-time artifact.

## 3. Agent Permission Models

Define what agents can do autonomously vs. what requires human confirmation.

### Default Permission Tiers

| Action | Permission |
|--------|-----------|
| Read files, search code | Autonomous |
| Edit/create source files | Autonomous |
| Run tests (`make test`, `cargo test`) | Autonomous |
| Run linters/formatters (`make lint`, `make fmt`) | Autonomous |
| Run full CI (`make ci`) | Autonomous |
| Git commit (in worktree) | Autonomous |
| Git push | Requires confirmation |
| Git force push, reset --hard | Requires explicit approval |
| Delete files/branches | Requires confirmation |
| Modify CI/CD pipelines | Requires explicit approval |
| Send messages (PR comments, emails) | Requires confirmation |

### Configuration

Permission models should be defined in agent-specific configuration files:

* Claude Code: `.claude/settings.json`
* Cursor: `.cursorrules`
* Copilot: `.github/copilot-instructions.md`

## 4. Devloop Pattern (UI Projects)

For projects with a graphical interface, expose an HTTP API that enables agents to build, inspect, and iterate on the UI autonomously.

### Required Endpoints

| Endpoint | Purpose |
|----------|---------|
| `POST /rebuild` | Trigger a build, block until complete, return build status |
| `GET /snapshot` | Return screenshot (PNG base64) + widget/component tree (JSON) |
| `GET /snapshot?diff=true` | Same as above, plus diff from previous snapshot |

### Widget Tree JSON

The snapshot response should include a structured representation of the UI hierarchy:

* Element ID, type/kind, bounding rectangle, visibility
* Style properties (background color, font size, etc.)
* Interactive state (focused, hovered, selected)

This enables agents to reason about UI changes semantically rather than relying solely on pixel-level screenshot comparison.

### Make Targets

```makefile
setup-devloop: ## Install devloop dependencies
devloop:       ## Start devloop HTTP server for agent-driven UI iteration
```

## 5. Agent-Generated Artifacts

### Commit Conventions

Agent-authored commits MUST include a `Co-Authored-By` trailer identifying the agent:

```text
feat(core): add validation for email addresses

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

### Pull Request Conventions

**Agents MUST open a pull request for every discrete piece of completed work.** Work is not considered done until a PR exists.

Agent-created PRs MUST:

* Include `🤖 Generated with [Agent Name]` in the PR description.
* Follow the same title/body format as human-authored PRs.
* Link to the relevant issue or design document (`Closes #N`, `Fixes #N`, or `Part of #N`).

### Work Tracking

Agents MUST create GitHub Issues (or the project's configured tracker) when they:

* Discover bugs or failing edge cases during implementation.
* Identify tech debt or shortcuts taken to meet scope.
* Encounter out-of-scope work that should be addressed later.
* Add `TODO` or `FIXME` comments to the codebase — every such comment MUST reference an issue number.

**Agents must NOT silently defer work.** If something needs to be done, it needs to be tracked. Check `CLAUDE.md`, `README.md`, or `.github/CONTRIBUTING.md` for the project's configured tracking tool. Default is GitHub Issues.

## Context Handling Across Layers

When agent work spans multiple architectural layers:

- Reference specific file paths when discussing code (e.g., `packages/domain/user.py`).
- Summarize changes in the current layer's context before moving to the next layer.
- Keep conversation context focused: avoid loading full files when only a section is relevant.
