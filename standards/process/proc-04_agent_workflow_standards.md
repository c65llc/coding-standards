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

## 5. Mission Isolation (Antigravity)

When an agent (typically [Google Antigravity](https://antigravity.google.com)) starts work on a major feature, it sets the active Mission URL in `.gemini/active_mission.log`. Other agents (Claude Code, Cursor, Aider, Codex, Gemini CLI) read this file and stay aligned with the Mission's scope.

### Feature Bracketing

* **One Mission per major feature.** Don't lump multiple features into one Mission — the cost is review confusion and Mission scope drift.
* **Cross-reference issue/PR.** The Mission URL should resolve to a Mission that links the work back to a GitHub Issue or PR.
* **Don't run two Missions in the same project simultaneously** — they will overwrite each other's `active_mission.log`.

### Lifecycle

```bash
./scripts/mission-set.sh https://antigravity.google.com/missions/<id>   # at start
./scripts/mission-clear.sh                                              # on completion
```

| Phase | Action |
|-------|--------|
| **Set** | Before the first agent action on the feature. Validates HTTPS-only, writes URL + UTC timestamp atomically. |
| **Active** | Other agents reading `.gemini/active_mission.log` will see the URL on first line; treat as authoritative scope. |
| **Clear** | Immediately on completion — PR merge, Mission close, or abandonment. Do not leave stale entries. |
| **Stale** | A non-empty `active_mission.log` whose timestamp is more than ~7 days old. Treat as forgotten clear; verify with the Mission owner before assuming it's still valid. |

### Read Protocol

Before starting work in a project, agents SHOULD check the file:

```bash
[ -s .gemini/active_mission.log ] && head -1 .gemini/active_mission.log
```

If a Mission URL is present, agents SHOULD reference it in commit messages and PR descriptions. Scope creep beyond the Mission's stated goals SHOULD trigger a new issue rather than expanded edits.

## 6. Agent-Generated Artifacts

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

## 7. UI Change Validation

For projects with a graphical interface, agents that modify UI files MUST validate the rendered output against a reference design before claiming the change is complete. This complements the [Devloop Pattern](#4-devloop-pattern-ui-projects) — devloop enables agents to *iterate*; UI Change Validation enforces that the iteration converges on design intent.

### When the protocol triggers

Agents SHOULD apply this protocol when modifying files matching any of the following patterns:

| Stack | Patterns (globs) |
|---|---|
| Web | `**/*.tsx`, `**/*.jsx`, `**/*.vue`, `**/*.svelte`, `**/*.html`, `**/*.css`, `**/*.scss` |
| Mobile / desktop | `**/*.dart`, `**/*.swift`, `**/*.kt` (Compose), `**/*.xaml` |
| Style tokens / theme | `**/tokens.json`, `**/theme.*`, `**/design-tokens/**`, `**/*.tokens.{json,yml,yaml}` |

Patterns are globs evaluated against repo-relative file paths. For changes that don't trip a pattern (e.g., copy edits in a Markdown-driven CMS that affect rendered UI), the PR author MAY opt in by writing `ui-validation: required` in the PR body.

### The three-step workflow

1. **Render.** Spin up the dev server (or use the project's `/rebuild` devloop endpoint).
2. **Capture.** Take a screenshot of the changed surface using the agent's browser tool — see "Cross-agent invocation" below.
3. **Compare.** Diff the screenshot against the reference design in `assets/designs/<route-or-component>/<state>.png`.

### Comparison criteria

**The agent surfaces the diff; a human approves whether intent is met.** Pixel-diff alone is not gating: font rendering, anti-aliasing, sub-pixel layout, and OS-level smoothing produce noise that swamps real design changes. Use one of:

- **Side-by-side**: reference and rendered output adjacent. Best for layout-driven changes.
- **Overlay**: rendered output 50% opacity over reference. Best for spacing and alignment.
- **Per-region delta**: cropped diffs for changed components only. Best for token / theme changes that touch many pages.

The agent's output is a **diff artifact + a summary of what changed**. Approval is human-gated unless the project explicitly opts into pixel-diff gating (rare; document the threshold in `assets/designs/NOTES.md`).

### Cross-agent invocation

| Agent | Browser tool |
|---|---|
| Google Antigravity | Built-in Browser Agent |
| Claude Code | Playwright MCP server (`@modelcontextprotocol/server-playwright`) |
| Cursor | Built-in browser tool |
| Aider, Codex | No native browser — projects exposing the [Devloop](#4-devloop-pattern-ui-projects) `GET /snapshot` endpoint normalize this across all agents |

### `assets/designs/` directory convention

Reference designs live in `assets/designs/<route-or-component>/<state>.{png,svg}`. Each project SHOULD include a copy of the [`templates/assets-designs-README.md.example`](https://github.com/c65llc/coding-standards/blob/main/templates/assets-designs-README.md.example) template at `assets/designs/README.md` to document its specific naming conventions and breakpoint coverage.

The directory is **opt-in per project** — `setup.sh` does not auto-create it. Add it manually when the project takes on UI work.

### Updating the reference

When design intent changes (designer ships a new mock, accessibility audit changes spacing, etc.):

1. Update the reference in the same PR as the UI change.
2. Note the intentional reference change in the PR body so reviewers know the diff is expected.
3. Update `assets/designs/NOTES.md` if the change requires explanation (e.g., "Reduced primary CTA size to meet WCAG 2.5.5 target-size requirements").

## Context Handling Across Layers

When agent work spans multiple architectural layers:

- Reference specific file paths when discussing code (e.g., `packages/domain/user.py`).
- Summarize changes in the current layer's context before moving to the next layer.
- Keep conversation context focused: avoid loading full files when only a section is relevant.
