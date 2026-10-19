# Agent Workflow Standards

**Governing principle: One task = one branch = one worktree = one PR.**

Every discrete piece of agent work follows the same end-to-end lifecycle: isolate, implement, verify, deliver via pull request. Work is not considered done until a PR exists.

## 1. End-to-End Agent Workflow

### The Complete Lifecycle

Non-trivial work (a new feature, a change crossing architectural layers, a migration) starts **before step 1** with a design spec and an implementation plan — see [proc-01 §11](./proc-01_documentation_standards.md#11-spec-plan-design-pass-and-verification-documents) and the templates in `templates/docs/`. UI work adds a design pass (§7). Trivial fixes go straight to the worktree.

This standard is agent-neutral: the same lifecycle applies whichever agent runs it (Claude Code, Codex, Cursor, Copilot, Gemini CLI, Aider, Antigravity). `{{WORKTREE_DIR}}` below is the project's worktree root — `worktree_dir:` in `.standards.yml`, default `.claude/worktrees` — and the assembled agent configs carry the resolved value, so every agent in a project names the same directory. Anything that exists only for one agent lives in that agent's appendix under `standards/agents/<agent>/` (see §5).

Every agent task MUST follow these steps in order:

1. **Create worktree + branch** — from the main checkout, never from inside another worktree.

   ```bash
   git worktree add {{WORKTREE_DIR}}/<branch-name> -b <branch-name>
   cd {{WORKTREE_DIR}}/<branch-name>
   ```

2. **Write tests first (TDD).** Red → Green → Refactor. No implementation code before a failing test.
3. **Implement.** Write the minimum code to pass tests. Maintain ≥ 95% coverage in all modified modules. Python code must pass `mypy --strict`.
4. **Run the project's full local gate (`make ci`).** It must pass before proceeding, and it must mirror CI: every check CI runs is in `make ci` and vice versa, so a local pass predicts the CI result. A gate that passes locally and fails in CI (or the reverse) is a bug in the gate — fix the gate rather than route around it.
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
   git worktree remove {{WORKTREE_DIR}}/<branch-name>
   git branch -D <branch-name>
   git push origin --delete <branch-name>
   ```

### Workspace Isolation

* **Requirement:** AI agents MUST work in git worktrees, never the developer's root checkout.
* **Location:** Every agent's worktrees live under the one root `{{WORKTREE_DIR}}/` (`worktree_dir:` in `.standards.yml`, default `.claude/worktrees`) — not a per-agent directory. A project that prefers `.worktrees/` or `.codex/worktrees/` declares it once and every assembled agent config follows.
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

### Worktree Hygiene

The root checkout is the human's volatile workspace — it auto-pulls mainline and
its branch gets switched out from under you. These rules keep agent work from
landing on the wrong branch or failing on phantom errors:

* **Do all multi-commit work in a worktree, never the root checkout.** If you must
  touch the root, run `git branch --show-current` immediately before *every*
  commit — a background pull may have flipped HEAD to `main` or another branch.
* **`gh pr create` infers the head branch from the current directory.** Run it from
  inside the feature worktree, or pass `--head <branch>` explicitly. Running it
  from the root opens a PR for whatever branch the root is on — your title/body on
  the wrong diff, a silent outward-facing mistake. Verify after:
  `gh pr view <n> --json headRefName`. (`gh pr merge <number>` is safe — it takes
  an explicit PR number.)
* **Install from the lockfile in a fresh worktree before running gates.** A new
  worktree shares the repo but not `node_modules`/`target`; a plain install can
  resolve versions that differ from the committed lock and produce *phantom* lint
  or type failures on files you never touched. Use the frozen/locked mode
  (`pnpm install --frozen-lockfile`, `npm ci`, `cargo build --locked`). When a gate
  fails on an untouched file, check the installed toolchain version against the
  lock *before* "fixing" the file.
* **Repair git hooks after switching worktrees.** Hook installers can leave
  `.git/hooks/*` pointing at a deleted worktree's path. If hooks misbehave, run the
  repo's hook-repair target (e.g. `make hooks`) to rewrite them for the current
  checkout.

#### One worktree root per repository

Worktree sprawl is a disk and correctness problem, not a tidiness one: a survey
of four consumer projects found 17 worktrees under one checkout (`.claude/worktrees`
8.8 GB, `.Codex/worktrees` 12 GB), a `.worktrees/` tree of 37 GB, worktrees nested
two deep, a worktree accidentally committed as a submodule, and a linter that timed
out walking them. These rules keep worktrees cheap:

* **Every worktree lives under one gitignored root.** The root is `{{WORKTREE_DIR}}` —
  `worktree_dir:` in `.standards.yml` (default `.claude/worktrees`); `setup.sh` writes the `.gitignore`
  entry and installs a pre-commit guard (`templates/pre-commit-worktree-guard.example`)
  that refuses any commit staging a path under it — a worktree arriving as a gitlink
  (the shape of a submodule) is the failure this prevents. Worktrees found elsewhere
  (`.worktrees/`, `.Codex/worktrees/`, …) are strays: `doctor` reports them and
  `worktree-gc` collects them like any other.
* **Never create a worktree from inside a worktree.** `git worktree add` resolves a
  relative path against the current directory, so running it from inside
  `{{WORKTREE_DIR}}/a` produces `{{WORKTREE_DIR}}/a/{{WORKTREE_DIR}}/b`: a nested
  tree that doubles the disk cost and is skipped by nothing. Create worktrees from
  the main checkout, or pass the absolute path under the root. `doctor` warns on
  nesting.
* **A worktree has a lifetime: its PR.** It is removed when the PR merges (step 7
  above), and a worktree with no commit or checkout activity for **14 days** is
  idle and collected. Uncommitted work in an idle worktree is a **warning, not a
  blocker**: the collector says what it is discarding and removes the worktree;
  pass `--keep-dirty` to opt out. An unmerged branch keeps its ref — only the
  directory goes.
* **Collect with `make worktree-gc`** (`scripts/worktree-gc.sh`). It fetches with
  `--prune`, removes worktrees whose branch is merged into the base (deleting those
  branches) or whose upstream is gone (keeping the branch: "gone" alone does not
  prove the commits landed), removes idle worktrees, prunes registrations whose
  directory vanished, reports every remaining worktree with its idle age and size,
  and never touches the main checkout, the worktree it runs from, a locked
  worktree, or a worktree that still encloses other worktrees. `--dry-run`
  previews. Run it after every merge, and from a weekly reminder on long-lived
  machines.
* **`make doctor` reports worktree count, oldest idle age and total size**, and warns
  on nesting, strays outside the root, a root that is not gitignored, and worktrees
  past the idle limit.

#### Shared caches live outside the worktree

N worktrees must not mean N copies of `target/`, `node_modules/` or
`DerivedData/`. Point every build cache at one location per repository — under
`~/.cache/<repo>/`, or `$TMPDIR` when the checkout is inside a synced folder such as
iCloud Drive or Dropbox — so a fresh worktree builds warm and a removed worktree
frees only source. Set them in one place every tool sees (`.envrc` via direnv, the
`make ci` environment, the runner service's environment):

| Tool | Setting | Example |
|------|---------|---------|
| Cargo | `CARGO_TARGET_DIR` | `~/.cache/<repo>/target` |
| pnpm | `pnpm config set store-dir` (content-addressable; `node_modules/` are hard links into it) | `~/.cache/pnpm-store` |
| npm / yarn | `npm_config_cache` / `YARN_CACHE_FOLDER` | `~/.cache/<repo>/npm` |
| Turborepo | `TURBO_CACHE_DIR` (or `cacheDir` in `turbo.json`) | `~/.cache/<repo>/turbo` |
| SwiftPM / Xcode | `swift build --scratch-path`, `xcodebuild -derivedDataPath` | `~/.cache/<repo>/swiftpm`, `~/.cache/<repo>/DerivedData` |
| Gradle | `GRADLE_USER_HOME`, `org.gradle.caching=true` | `~/.cache/<repo>/gradle` |
| Go | `GOCACHE`, `GOMODCACHE` (already outside the tree by default) | `~/.cache/go-build` |
| Python (uv / pip) | `UV_CACHE_DIR` / `PIP_CACHE_DIR` | `~/.cache/<repo>/uv` |

Caches that cannot be relocated (a tool that insists on `./node_modules`) are
re-created per worktree from the lockfile (see "Install from the lockfile" above);
their size is part of what `worktree-gc` reclaims.

#### Runners: disk-free preflight and post-job cleanup

Self-hosted runners accumulate the same sprawl without anyone looking. Every job on
a persistent runner:

* **Starts with a disk-free preflight** that fails fast below a threshold (20 GB by
  default) rather than dying mid-build with a cryptic `ENOSPC` — see the `apple` lane
  in `templates/ci-gate.yml.example`.
* **Ends with a cleanup step that runs `if: always()`**: `git worktree prune`,
  `git clean -ffdx` in the checkout, and removal of the job's scratch under
  `$RUNNER_TEMP`. Shared caches (above) are deliberately left alone — they are the
  point of a persistent runner.
* Keeps the runner's `_work` directory on a volume with headroom, and runs
  `worktree-gc` from a scheduled job when agents work on the runner host.

See [arch-08 § 6](../architecture/arch-08_ci_cd_pipeline_standards.md#6-self-hosted-runners)
for the rest of the runner rules.

## 2. Project-Level AI Guide

Every project SHOULD have an agent guide at the repository root — `CLAUDE.md`, `AGENTS.md`, `.gemini/GEMINI.md`, or whichever file its agents read; `setup.sh` assembles one per declared agent from the same blocks. The guide is distinct from the behavioural rules in `.cursorrules` or `.github/copilot-instructions.md` — it documents project-specific context that evolves during development.

### Shape: a map plus known traps

An agent guide has two kinds of content, and nothing else:

* **A map.** Where things are and how they fit: the sections in the table below. The map is stable and short — it points at detailed docs rather than inlining them.
* **Known traps.** Project-specific pitfalls that have already cost a debugging session, kept as a table whose rows carry the **issue number** that documented the trap and the **date** it was recorded, so a reader can judge whether it is still live. A trap row without an issue and a date cannot be audited; one consumer carried a wrong trap for months because nobody could tell when it had been true. Add a row whenever a bug's root cause was "the agent did not know this"; delete the row when the trap is engineered away, and say so in the issue.

```markdown
## Known Traps

| Trap | Why it bites | Issue | Date |
|------|--------------|-------|------|
| Run `make ci` from the repo root, not a package directory | Sub-make targets resolve paths from the working directory and silently skip suites | #412 | 2026-03-02 |
```

**Subtree guides add only what is local.** A guide in a subdirectory (`apps/web/CLAUDE.md`, `crates/core/AGENTS.md`) holds the map and traps of that subtree and nothing the root guide already says — no repeated workflow, no repeated conventions, no second copy of the worktree rules. An agent reads the root guide and the subtree guide together; duplication is where they drift apart (a consumer's subtree guide had to be hand-corrected when it carried its own copy of the worktree directory).

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
| Known Traps | The table above: trap, why it bites, issue, date |
| Agent Workflow | Worktree root (`{{WORKTREE_DIR}}`), permission model |

### Guidelines

* Keep it under 300 lines. Link to detailed docs rather than inlining everything.
* Include concrete examples of invariants and how they break.
* Update it as the project evolves — it is a living document, not a one-time artifact.
* Describe the local gate honestly: `make ci` is "the project's full local gate" only when it mirrors CI; if the project has no such target, say which commands CI runs instead of claiming one.
* Make `CHANGELOG.md` guidance conditional: a project with release automation (release-drafter, semantic-release, release-please, Changesets) must not tell agents to hand-edit the changelog.

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
* Codex: `AGENTS.md` (approval mode section)
* Gemini CLI: `.gemini/settings.json`
* Aider: `.aiderrc`

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

## 5. Agent-Specific Appendices

Everything above applies to every agent. Rules that exist only because of how one agent works live beside that agent's base template under `standards/agents/<agent>/`, so the shared standard never carries one agent's vocabulary:

| Agent | Appendix | Covers |
|-------|----------|--------|
| Google Antigravity (via Gemini) | [`standards/agents/gemini/antigravity.md`](../agents/gemini/antigravity.md) | Mission Isolation: one Mission per feature, `.gemini/active_mission.log`, `mission-set.sh` / `mission-clear.sh`, the read protocol other agents follow when a Mission is active |

Skills (`standards/skills/`) are agent-neutral runbooks emitted in each agent's own shape — Claude Code skill files, Cursor commands, Copilot prompt files, a "Skills" section in `AGENTS.md`, `GEMINI.md` and the Aider instructions — by `scripts/assemble-skills.sh` and `scripts/assemble-config.sh`. A skill never names one agent's tooling where another agent would have to translate.

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

### Design pass before code

A new or reshaped surface gets a **design pass** before its first UI commit: copy [`templates/docs/design-pass.md`](https://github.com/c65llc/coding-standards/blob/main/templates/docs/design-pass.md) to `docs/design/YYYY-MM-DD-<surface>.md` and fill the identity prompts, hard constraints, deliverables table and state inventory (empty / loading / error / streaming / sync paused / runner unavailable / pending write). The reference designs in `assets/designs/` are a deliverable of that pass; the validation below compares the build against them. No design pass means no reference, which means the PR needs human visual sign-off (see "UI PRs are not auto-mergeable" below). See [proc-01 §11](./proc-01_documentation_standards.md#11-spec-plan-design-pass-and-verification-documents).

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

### UI PRs are not auto-mergeable without sign-off

When a UI change has **no reference design** for the surface (a brand-new view, an
exploratory layout), the agent MUST open the PR, attach the rendered screenshots,
and **wait for human visual sign-off** — even when CI is green. Do not auto-merge.
This is an explicit exception to the otherwise-autonomous merge loop in
[proc-03_code_review_expectations.md](./proc-03_code_review_expectations.md) §1.
State it in the PR body (e.g. "UI — needs visual sign-off, do not auto-merge").

### Visual baselines are environment-specific

Visual-regression baselines must be regenerated **on the CI runner**, not locally.
Even a matching local container renders fractionally differently (font hinting,
anti-aliasing) from the CI host, so locally-generated baselines fail the CI visual
gate. Regenerate via the pipeline's own mechanism (e.g. a `workflow_dispatch` with
an `update_snapshots` input), and have that job finish the fix: push the
regenerated baselines to the PR branch as a bot commit, or upload them together
with a `git diff --binary` patch and print the one-line apply command. A dispatch
that only uploads baselines for the agent to download and commit by hand does not
meet the auto-fix rule in
[arch-06_monorepo_workspace_standards.md](../architecture/arch-06_monorepo_workspace_standards.md)
§6. Visual changes remain human-gated.

### Cross-platform UI scope

For products that ship the same UX on multiple platforms, a UI change is assumed
to apply to **every** platform unless scoped otherwise. Scope the issue/PR to cover
web *and* each native shell, and keep shared data/logic single-sourced in the core.
See [arch-07_cross_platform_shared_core_standards.md](../architecture/arch-07_cross_platform_shared_core_standards.md)
§4.

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
