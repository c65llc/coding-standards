# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
