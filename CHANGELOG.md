# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

<!-- Add entries under the standard Keep a Changelog headings as work lands:
### Added / ### Changed / ### Deprecated / ### Removed / ### Fixed / ### Security -->

### Added

- **Containerized agent-dev environment (#10):** new standard
  `arch-09_containerized_agent_dev_standards.md` codifying a sandboxed,
  reproducible Docker environment for autonomous AI agents — separate dev/prod
  images, a non-root sudo dev user, workspace-as-volume, a dual-layer egress
  allow-list, secret injection without baking, sandbox-earned "YOLO" permissions
  with git checkpointing, and scripted IDE integration. Ships an installable
  starter kit at `templates/containerized-dev/` (Dockerfiles, compose,
  `init-workspace.sh`/`setup-proxy.sh`, IDE bootstrap scripts, whitelists,
  devcontainer) with a Definition-of-Done validation checklist.

## [1.5.0] - 2026-07-05

A full-repo audit turned up ~30 issues across shell scripts, CI, docs, and the
standards themselves. This release lands the fixes in reviewable batches, plus a
round of standards enrichment from real cross-platform development.

### Added

- **Release automation (#141):** a `release-drafter` config and workflow keep a
  categorized draft release continuously up to date from merged PRs and
  auto-label PRs from their Conventional Commit title.
- **TruffleHog secret scanning (#58):** ship `templates/.trufflehog-ignore` (a
  documented `--exclude-paths` allowlist) and `templates/trufflehog.yml.example`
  (merge-blocking, verification-off, SHA-pinned). `setup.sh` installs the
  allowlist by default and the workflow with `--workflow`; `sec-01 §3` now
  recommends TruffleHog and documents the suppression mechanisms.
- **Linter dogfooding + docs (#127, #145):** a CI job runs `lint-standards.sh`
  against this repo and asserts text/JSON/SARIF run without crashing; a new
  `scripts/lint-checks/README.md` documents the enforced set (Python,
  TypeScript, Go, Elixir + common) vs. the nine standards-only languages, with a
  roadmap.
- **Functional test coverage (#144):** `scripts/test-lint-standards.sh` covers
  the linter's output formats and check modules; the safe-setup suite gains
  TruffleHog install tests.
- **Standards enrichment** from a real TS/Rust/Swift local-first monorepo:
  leader-protocol versioning + self-healing (`arch-05`, #119); alias ordering
  and bundler/test config parity (`arch-06`, #115); cold-rebuild drift gate and
  release-version fan-out across platforms (`arch-07`, #114/#118); self-hosted
  runner isolation and a post-promote production smoke check (`arch-08`/`proc-02`,
  #116/#117); an auditable per-release manual-QA checklist (`core-standards`,
  #121); regenerate visual baselines in CI, never locally (`testing-policy`/
  `lang-06`, #120); JS/TS lockfile + package-manager hygiene with
  `.prettierignore`/`.npmrc` templates (`#86`).
- **Dependabot ergonomics (#139):** grouped npm and github-actions updates with
  auto-merge for patch/minor bumps (majors stay manual).
- Shared script libraries `scripts/lib/languages.sh` and `scripts/lib/dry-run.sh`
  (#142).

### Changed

- **CI hardening (#128, #108):** added concurrency groups; expanded ShellCheck to
  the whole shell tree (with a documented `.shellcheckrc`); run
  `test-setup-safe.sh` in CI; `make test-scripts` now globs every shell script;
  markdownlint covers root markdown; all GitHub Actions pinned to exact commit
  SHAs.
- **Definition of Done (#134):** default Node `18 → 22`, advisory checks labeled
  honestly (so non-enforcing steps aren't mistaken for gates), and the summary
  comment is edited in place instead of stacked each run.
- **Lifecycle sync (#135):** project-item lookup paginates all items (was capped
  at 100 and failing open) and surfaces a warning when the issue isn't found.
- **Publish (#141):** `live` is advanced with `--force-with-lease` so an
  out-of-band commit isn't clobbered.
- **Website deps (#122–#126):** Astro `6 → 7`, Starlight, `starlight-blog`,
  `@astrojs/rss`, and `sharp` upgraded together (build re-verified).
- **Docs alignment:** `proc-02` distinguishes branch prefixes from Conventional
  Commit types (#138); `--workflow` install is documented as opt-in with the
  correct path (#143); agent configs and docs are re-synced to the standards
  tree — the deleted `arch-03` removed, Go/Elixir (`lang-12`/`lang-13`) added,
  Codex pointed at `AGENTS.md` (#136).

### Fixed

- `lint-standards.sh --format json/sarif` no longer crashes on zero findings
  under bash 3.2 — the exact path the standards-review action runs (#132).
- `gh-task`: parse `.gh-task-state` as data instead of `source`-ing it (arbitrary
  code execution), honor the documented repo config keys, handle a repo with no
  commits, abort instead of opening an empty-title PR (#133), and use portable
  `grep -Eo` instead of macOS-unsupported `grep -oP` (#129).
- `generate-pr-content.sh` no longer deletes the output file (via an EXIT trap)
  before any consumer can read the path it printed (#131).
- `install.sh` reads its prompt from `/dev/tty` (with a `STANDARDS_ASSUME_YES`
  opt-in) so it works under `curl | bash`, and hardens shell options (#130).

### Removed

- Orphaned `landing-page.png` (~250KB) and the stale `REVIEW.md` improvement-plan
  doc (its items are now tracked as issues) (#140).

### Security

- TruffleHog secret-scanning config and `sec-01 §3` guidance (#58) — see Added.

## [1.4.0] - 2026-06-18

### Changed

- **Hosting:** migrated the documentation site from GitHub Pages to **Cloudflare Pages** via Cloudflare's **GitHub integration** (no API tokens/secrets in the repo). Cloudflare's production branch is `live`; a secret-free `publish.yml` (using `GITHUB_TOKEN`) fast-forwards `live` only on a **release cut** or a **new/edited blog post**, so the site republishes on exactly those events — not on every docs/standards merge. Drops the GitHub Pages `CNAME` marker and adds CF Pages `_headers`. Fixes the cross-provider TLS failure (GitHub ACME `bad_authz` behind the Cloudflare proxy → HTTP 526). Dashboard setup is documented in `docs/deploy.md`. (#104)
- **CI:** the website CI build installs with `npm ci` (frozen lockfile) instead of `rm -rf node_modules package-lock.json && npm install`, and the committed `website/package-lock.json` was regenerated so it builds cleanly — reproducible builds (per the frozen-install standard in `arch-02`/`core-standards`), and Cloudflare's build uses the same lockfile. (#104)

## [1.3.1] - 2026-06-18

### Fixed

- **Release hygiene:** backfilled the `v1.2.0` git tag and GitHub release (CHANGELOG `[1.2.0]`, PR #77, commit `298d64e`) that were finalized in the changelog but never published — restoring a contiguous tag/release history (previously jumped `v1.1.0` → `v1.3.0`).

## [1.3.0] - 2026-06-18

### Changed

- **Documentation / releases (`proc-01 §4`, `shared/blocks/documentation-policy.md`):** projects with release automation (semantic-release, release-please, Changesets) must NOT hand-maintain a shared `## [Unreleased]` changelog block per PR — rely on generated notes or per-PR changeset fragments (avoids predictable merge conflicts under parallel work). (#88)
- **Automation (`arch-02 §2`):** added `make test-e2e` (scoped to projects with a browser/integration surface) and a `make verify` pre-merge gate that includes build + e2e; e2e runners that serve a prebuilt artifact must rebuild first (no stale-artifact false greens). (#89)
- **TypeScript (`lang-06 §1`):** Node **runtime** pinning must be ENFORCED (engine-strict / preinstall guard), not just declared, so a wrong runtime fails fast instead of a cryptic native-build error; pin the **package manager** separately via `packageManager`/Corepack. (#90)
- **TypeScript testing (`lang-06 §7`):** added anti-brittleness rules — no asserting on raw source text, no test-only markup, deterministic (locale-pinned) formatted-output assertions, and container-scoped queries. (#91)

### Added

- **`arch-06_monorepo_workspace_standards.md`** (new): multi-toolchain workspaces kept separate, per-member pipeline ownership ("own your scope, not your style"), running the build (not just typecheck), complete path/alias resolution across all resolvers, generated-artifact drift gates (clean-rebuild to reproduce), and workspace dependency hygiene.
- **`arch-07_cross_platform_shared_core_standards.md`** (new): shared pure core + thin per-platform shells, conformance/golden-vector testing as the parity gate, FFI boundary coverage (export smoke / golden parity / edge cases), UI-changes-are-cross-platform-by-default scoping, and testing to the platform edges.
- **`arch-08_ci_cd_pipeline_standards.md`** (new): local gate mirrors CI, consolidate the required gate + build once, don't-run-everything-per-PR (concurrency cancel, path filters, tiered heavy suites), caching (pinned actions, keyed/evicted caches), artifact retention, self-hosted runner caveats, and deploy channels & promotion.
- `proc-03_code_review_expectations.md`: a **PR Definition of Done / merge loop** (full local gate → open → wait for automated review → address all feedback → all-green → squash-merge), automated/AI review treated as a first-class gate with an author self-review checklist of common findings, and a UI-PRs-need-sign-off case.
- `proc-02_git_version_control_standards.md` § 5/§ 11: release-version vs build-version model, deploy channels & promotion, the scripted reviewable release cut, and a Stacked & Dependent PRs section (base-deletion trap, conflicting-PR-runs-no-checks, one `Closes #X` per line, `gh pr create` cwd inference).
- `proc-04_agent_workflow_standards.md`: Worktree Hygiene (volatile root checkout, `gh pr create` cwd, frozen-lockfile install in fresh worktrees, hook repair) and UI sign-off / environment-specific visual baselines / cross-platform UI scope.
- `arch-02_automation_standards.md`: `make hooks` target and stronger `make dev` provisioning (all toolchains + hooks, frozen-lockfile installs).
- `arch-05_resilient_architecture_patterns.md` §§ 7–9: best-effort/isolated secondary subsystems, liveness & takeover for coordination singletons, and "don't swallow the root cause."
- `core-standards.md`: an Untestable Boundaries policy under Testing Standards (no dead-branch coverage gaming; keep boundaries thin; flag manual verification) and references to the new `arch-06`/`arch-07`/`arch-08` standards.
- Shared blocks updated to propagate into assembled agent configs: `git-workflow` (merge loop, small/stacked PRs, `gh pr create` cwd, stacked-PR retarget), `testing-policy` (untestable boundaries, run the build), `architecture-core` (best-effort secondary subsystems, preserve the cause).
- `lang-04_swift_standards.md § 14`: Build & Project Generation (Apple platforms) — XcodeGen/Tuist as project source of truth, code-signing rules (set `DEVELOPMENT_TEAM`, never disable signing at `base`), CI override pattern, a diagnostic checklist for "code is unsigned" device-install failures, and a note (§14.5) on latent target-config gaps that surface when re-enabling signing (e.g. test targets requiring `GENERATE_INFOPLIST_FILE: YES`).

## [1.2.0] - 2026-04-16

### Changed — Safe setup (breaking for setup.sh defaults)

- **`setup.sh` no longer clobbers existing agent configs.** Every assembly now routes through `should_assemble()`; customized files are staged as `.standards-pending/<file>` instead of overwritten. Applies to `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `.aider-instructions.md`.
- **`--agents` defaults to `detect`** (was: install all six). Setup now probes for existing config files (`CLAUDE.md`, `.cursorrules`, etc.) and installs only for agents already in use. Escape hatches: `--agents all`, `--agents claude-code,cursor`, or explicit comma-separated list.
- **`--workflow` gates the `standards-review.yml` install.** Previously copied unconditionally when missing; now opt-in. When skipped, setup prints the hint: `To install: ./setup.sh --workflow`.
- **Template variables in `CLAUDE.md` are now resolved.** `{{PROJECT_NAME}}` is filled from `package.json` / `Cargo.toml` / `pyproject.toml` / directory name. `{{PROJECT_OVERVIEW}}` and `{{KEY_COMMANDS}}` are rewritten to `<!-- TODO(standards): -->` markers the merge skill fills in — never shipped as literal `{{...}}`.

### Added

- **`scripts/lib/assembly.sh`** — shared `assemble_agent_config_guarded()` used by both `setup.sh` and `sync-standards.sh`. First-run and re-sync now behave identically.
- **`scripts/lib/detect-agents.sh`** — `detect_installed_agents()` probe used by `--agents detect`.
- **`scripts/lib/template-vars.sh`** — `resolve_project_name`, `resolve_template_vars`.
- **`scripts/lib/merge-plan.sh`** — `write_merge_plan()` emits `.standards-pending/MERGE_PLAN.md`.
- **`.cursor/commands/merge-standards.md`** — Cursor-facing twin of the Claude Code skill.
- **`make merge-standards`** — prints `MERGE_PLAN.md` for manual or agent-agnostic workflows.
- **`scripts/test-setup-safe.sh`** — 17 functional tests for pending-mode writes, agent detection, template-var resolution, workflow gate, MERGE_PLAN emission. Wired into `make test`.

### Fixed

- Re-running `setup.sh` on a project that already has customized `AGENTS.md` / `CLAUDE.md` no longer discards the user's work.
- Assembled `CLAUDE.md` never ships with literal `{{PROJECT_NAME}}`, `{{PROJECT_OVERVIEW}}`, or `{{KEY_COMMANDS}}` tokens.

## [1.1.0] - 2026-04-15

### Added

- **Project governance & infrastructure**
  - `.github/CODEOWNERS` — default code ownership (proc-03 compliance)
  - `.github/dependabot.yml` — automated dependency updates for npm and GitHub Actions (sec-01 compliance)
  - Security checklist (P0/P1/P2) in PR template (sec-01 compliance)
- **Architecture & navigability docs**
  - `docs/adr/0001-unified-standards-repository.md` — foundational architecture decision record (proc-01 compliance)
  - `standards/README.md` — directory structure and naming convention overview (proc-01 compliance)
  - `bin/README.md` — gh-task CLI overview with documentation links (proc-01 compliance)
- **Website**
  - "How It Works" page with architecture and sync pipeline details
  - Security section in website sidebar
  - Security standards sync in website build pipeline
  - Blog posts covering project release history
- **Drift detection**: `make doctor` gains `check_aiderrc_template_sync` — surfaces drift between root `.aiderrc` and the canonical `standards/agents/aider/aiderrc.template` (#34, #69)
- **Antigravity Mission isolation** (#67, #72)
  - `scripts/mission-set.sh <url>` / `scripts/mission-clear.sh` — atomic write/truncate of `.gemini/active_mission.log` with HTTPS-only validation
  - `proc-04 § 5: Mission Isolation` — feature bracketing rules, lifecycle table (set/active/clear/stale), read protocol; renumbers prior § 5 to § 6
  - `GEMINI.md > Active Mission Tracking` — read protocol all agents (Claude Code, Cursor, Aider, Codex, Gemini) follow before starting work
- **Postgres MCP integration** (#67, #72)
  - `.gemini/settings.json` ships a `postgres` MCP entry, opt-in via `POSTGRES_MCP_DATABASE_URL` env var; gracefully fails to start when env var unset
  - `make doctor` gains `check_postgres_mcp` — warns when entry is present but env var is missing
- **UI Change Validation protocol** (#68, #73)
  - `proc-04 § 7: UI Change Validation` — file-extension trigger heuristic; render → screenshot → diff three-step workflow; human-gated comparison criteria (pixel-diff is too noisy to gate on); cross-agent invocation table
  - `templates/assets-designs-README.md.example` — reference template projects copy when opting into the `assets/designs/` convention
  - `standards/shared/blocks/role-app.md` — UI-validation requirement injected into every assembled `role: app` agent config via the existing block-assembly system

### Changed

- `.aiderrc` re-synced with canonical `aiderrc.template`; drops 97 lines of stale inline P0/P1 security list now sourced via the block assembly system (#34, #69)
- Default Aider model bumped to `claude-sonnet-4-6` (current Sonnet 4.6 family alias) (#70)
- Restructured `CHANGELOG.md` with versioned release sections

### Fixed

- `standards-review` composite GitHub Action failed to load in consumer repos with `could not find expected ':'` YAML parse error. A Python heredoc inside a `run: |` block was indented at column 0, terminating the YAML literal block scalar so the parser interpreted Python as YAML. The formatter is now a sibling `format-results.py` invoked via `${{ github.action_path }}` (#64, #66)

## [0.5.0] - 2026-03-03

### Added

- **Language-aware bootstrap** for Claude Code settings (#24)
  - Automatic language detection from project files
  - Dynamic `settings.json` generation with language-specific tool configs
  - CI test infrastructure for bootstrap validation

### Fixed

- Corrected invalid Claude Code `settings.json` template (#23)

## [0.4.0] - 2026-03-03

### Added

- **Security Standards Framework** (`standards/security/sec-01_security_standards.md`) (#22)
  - P0-P2 severity model (P0/P1 block merge, P2 flagged as warning)
  - 8 security categories: injection, auth, secrets, dangerous functions, dependencies, config, data protection, SAST tooling
  - Per-language SAST and dependency scanning tooling reference
- Security violation detection rules added to all agent configs
- Security sections added to all 10 language standards
- Expanded security section in `core-standards.md`
- Security checklist in `proc-03_code_review_expectations.md`

## [0.3.0] - 2026-03-03

### Added

- **Ruby standards** (`lang-10_ruby_standards.md`) (#21)
- **Ruby on Rails standards** (`lang-11_ruby_on_rails_standards.md`) (#21)

### Changed

- Restructured language file numbering to accommodate new languages (#21)

## [0.2.0] - 2026-03-02

### Added

- `CLAUDE.md` for Claude Code project instructions (#20)
- Gemini CLI and Antigravity support with `.gemini/` configuration (#20)
- Marketing website with Starlight documentation site (#19)
- Comprehensive documentation: getting started, guides, reference
- `docs/changelog.md` for website changelog rendering

### Changed

- Updated setup/sync scripts with Gemini CLI detection (#20)
- Public launch improvements: collaboration docs, CI workflows (#19)

## [0.1.0] - 2025-12-22

### Added

- **GitHub Project Lifecycle Automation Suite**
  - `bin/gh-task` — CLI tool for GitHub Projects V2 integration
  - Commands: `create`, `start`, `status`, `update`, `submit`
  - Automatic project status updates (Todo → In Progress → In Review → Done)
  - Branch management with `task/<id>-<title>` naming convention
- **Reusable GitHub Actions Workflows**
  - `.github/workflows/lifecycle-sync.yml` — auto-sync project status on PR events
  - `.github/workflows/definition-of-done.yml` — quality checks for PRs
- **PR Templates** (`.github/PULL_REQUEST_TEMPLATE/default.md`)
- **Configuration Templates** for GitHub Projects V2
- **Comprehensive Documentation**
  - `docs/GH_TASK_GUIDE.md` — complete gh-task CLI reference
  - `docs/GH_TASK_QUICKSTART.md` — 5-minute quick start guide
  - `docs/TOOLING.md` — architecture and AI agent instructions
- **Testing Infrastructure** (`scripts/test-gh-task.sh`)
- Multi-agent support: Cursor, Copilot, Claude Code/Aider, Codex
- `standards/shared/core-standards.md` — canonical cross-cutting standards
- Standards documents: architecture (3), languages (9), process (4)
- Setup and sync scripts for standards distribution via git submodule
- One-line installer (`install.sh`)
