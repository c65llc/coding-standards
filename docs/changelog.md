---
title: "Changelog"
description: "All notable changes to the coding standards project."
---

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- **Ruby standards** (`lang-10_ruby_standards.md`)
- **Ruby on Rails standards** (`lang-11_ruby_on_rails_standards.md`)

### Changed

- Restructured language file numbering to accommodate new languages

## [0.2.0] - 2026-03-02

### Added

- `CLAUDE.md` for Claude Code project instructions
- Gemini CLI and Antigravity support with `.gemini/` configuration
- Marketing website with Starlight documentation site
- Comprehensive documentation: getting started, guides, reference

### Changed

- Updated setup/sync scripts with Gemini CLI detection
- Public launch improvements: collaboration docs, CI workflows

## [0.1.0] - 2025-12-22

### Added

- **GitHub Project Lifecycle Automation Suite**
  - `bin/gh-task` — CLI tool for GitHub Projects V2 integration
  - Commands: `create`, `start`, `status`, `update`, `submit`
- **Reusable GitHub Actions Workflows**
- **PR Templates** and configuration templates
- **Comprehensive Documentation** (gh-task guide, quick start, tooling)
- **Testing Infrastructure** (`scripts/test-gh-task.sh`)
- Multi-agent support: Cursor, Copilot, Claude Code/Aider, Codex
- Standards documents: architecture (3), languages (9), process (4), shared
- Setup and sync scripts for standards distribution via git submodule
- One-line installer (`install.sh`)
