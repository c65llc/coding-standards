# Agent Workflow Standards

## 1. Workspace Isolation

* **Requirement:** AI agents MUST work in git worktrees, never the developer's root checkout.
* **Location:** Worktrees live in `.claude/worktrees/` (Claude Code), `.cursor/worktrees/` (Cursor), or equivalent per-agent directory.
* **Rationale:** The root checkout is the developer's active workspace. Agent modifications cause conflicts with IDE state (unsaved buffers, debug configurations, terminal sessions). Worktrees provide full isolation at near-zero cost.

### Setup

```bash
git worktree add .claude/worktrees/<branch-name> -b <branch-name>
cd .claude/worktrees/<branch-name>
```

### Rules

* Never modify files in the root checkout from an automated agent session.
* Create a new worktree at the start of each feature/fix branch.
* **Follow TDD:** Write failing tests before implementation code. This applies to agents as well as humans.
* **Maintain ≥ 95% test coverage** in all modified modules. Run coverage checks before considering work complete.
* **Python code must be strongly typed:** All functions, methods, and variables must have type annotations. `mypy --strict` must pass with zero errors.
* Run `make ci` within the worktree before considering work complete.
* **Clean up immediately after merge.** Remove worktree, delete local branch, delete remote branch:
  ```bash
  git worktree remove .claude/worktrees/<branch-name>
  git branch -D <branch-name>
  git push origin --delete <branch-name>  # if pushed to remote
  ```

### Branch Naming

Agent branches MUST use the same `type/description` convention as human branches. Opaque IDs or numeric suffixes alone are not acceptable:

```
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

```
feat(core): add validation for email addresses

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

### Pull Request Conventions

Agent-created PRs should:
* Include `🤖 Generated with [Agent Name]` in the PR description.
* Follow the same title/body format as human-authored PRs.
* Link to the relevant issue or design document.
