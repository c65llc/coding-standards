# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **coding standards repository** — a collection of reusable development standards and AI agent configurations designed to be installed into other projects (via git submodule or direct clone). It is not an application; it contains Markdown standards documents, bash scripts, and agent config files.

## Key Commands

```bash
make help                    # Show all available targets
make test-scripts            # Validate bash script syntax (setup.sh, sync-standards.sh)
make lint                    # Lint markdown files (requires markdownlint)
make format                  # Format markdown files (requires prettier)
make setup                   # Run setup script to configure standards in a project
make sync-standards          # Sync standards files and re-assemble declared agent configs
make diff-standards          # Preview what sync-standards would change (no files modified)
make setup-agents            # Setup AI agent configurations
make add-copilot-instructions # Create PR to add Copilot instructions
make doctor                  # Run standards health check (audits config, agents, checksums, git hooks, worktrees)
make worktree-gc             # Remove merged, gone and idle agent worktrees; report the rest (ARGS="--dry-run")
make lint-standards          # Run standards compliance linter (common + language-specific checks)
make generate-standards-lists # Regenerate the standards lists inside agent configs from standards/
make check-agent-configs     # Fail if any agent config is stale, cites a missing standard, or omits one
```

Use `--dry-run` with setup or sync to preview changes without modifying files:

```bash
./scripts/setup.sh --dry-run
./scripts/sync-standards.sh --dry-run
./scripts/diff-standards.sh --exit-code   # exit 1 when any assembled agent config would change (CI gate)
```

In a consumer project the scripts live under `.standards/` and must be run from the project root (`./.standards/scripts/sync-standards.sh`). `setup.sh`, `sync-standards.sh` and `diff-standards.sh` refuse to run when the project root resolves to `.standards/` (`scripts/lib/guard.sh`). `sync-standards.sh` gates every side effect (Cursor commands, `.gemini/`, `.claude/`) on the `agents:` list in `.standards.yml`; git aliases are opt-in via `--aliases`.

`setup.sh --help` lists every flag; unknown flags exit 2 before anything is written. An explicit `--agents <list>` installs only those agents' artifacts (no git hooks, git aliases, Cursor commands, `.claude/settings.json` or `.gemini/` unless the owning agent is listed); `--agents detect` (the default) keeps the full install.

The standards-review composite GitHub Action lives at `.github/actions/standards-review/action.yml`. It runs `lint-standards.sh --format json` and posts structured PR comments. A ready-to-use workflow template is at `templates/standards-review.yml.example`. Installing it into a consumer project is **opt-in**: run `.standards/scripts/setup.sh --workflow` (or `./scripts/setup.sh --workflow` from a clone of this repo) to copy it to `.github/workflows/standards-review.yml`. Without `--workflow`, setup only prints how to install it. The action also checks the PR title against Conventional Commits (`pr-title-check: fail|warn|off`, default `fail`) because squash-merge uses the PR title as the mainline commit subject.

Conventional Commits tooling shares one helper, `scripts/lib/conventional-commits.sh` (type list, regex, `commits:` block parser for `.standards.yml`). It backs the `conventional-commits` lint module (`--since <ref>` / `--window <n>`, `commits.window|since|scopes`), `scripts/check-commit-message.sh` (hook + PR-title validator) and the commit-msg hook templates `templates/husky-commit-msg.example` and `templates/lefthook.yml.example`, which `setup.sh` only prints install instructions for (never auto-installs). `doctor.sh` recognises `lefthook.yml` and `.husky/` as hook managers.

CI for this repo follows arch-08 §3: `.github/ci/routing.yml` maps changed paths to lanes, `ci.yml` runs only the affected lanes behind an always-run `CI Gate` job, and every `pull_request` workflow declares `concurrency`, `timeout-minutes`, and path scoping (or a `# ci-hygiene: paths-exempt <reason>` marker). The `Lint Standards (dogfood)` job enforces the `ci-workflow-hygiene` and `headless-ci` checks against our own workflows, and `changelog-tags` against our own `CHANGELOG.md` (its checkout uses `fetch-depth: 0` so the tags are present). Consumer templates for the same pattern: `templates/ci-routing.yml.example` and `templates/ci-gate.yml.example`.

There are no build steps, no test suites, and no application to run. The primary "tests" are `bash -n` syntax checks on shell scripts.

## Architecture

### Standards Documents (`standards/`)

Markdown files organized by category with prefix-based naming:

<!-- BEGIN GENERATED: standards-list -->
<!-- Generated by scripts/generate-standards-lists.sh from the standards/ tree. Do not edit by hand; run `make generate-standards-lists`. -->

**Architecture Standards:**

- `standards/architecture/arch-01_project_standards_and_architecture.md` — Core architecture, SOLID principles, naming conventions
- `standards/architecture/arch-02_automation_standards.md` — Makefile targets and automation requirements
- `standards/architecture/arch-04_data_versioning_and_migration_standards.md` — Data versioning and migration
- `standards/architecture/arch-05_resilient_architecture_patterns.md` — Resilient architecture patterns
- `standards/architecture/arch-06_monorepo_workspace_standards.md` — Monorepo/workspace structure
- `standards/architecture/arch-07_cross_platform_shared_core_standards.md` — Cross-platform shared-core
- `standards/architecture/arch-08_ci_cd_pipeline_standards.md` — CI/CD pipeline
- `standards/architecture/arch-10_agent_tools_and_mcp_server_standards.md` — Agent tools and MCP servers (schemas, write gating, untrusted-data fencing)

**Language Standards:**

- `standards/languages/lang-01_python_standards.md` — Python (uv, ruff, mypy, pytest)
- `standards/languages/lang-02_java_standards.md` — Java (Gradle/Maven, Java 17+, JUnit 5)
- `standards/languages/lang-03_kotlin_standards.md` — Kotlin (Gradle, ktlint, detekt, MockK)
- `standards/languages/lang-04_swift_standards.md` — Swift (SwiftPM, Swift 6 strict concurrency, swift-format, XCTest/Swift Testing)
- `standards/languages/lang-05_dart_standards.md` — Dart (pub, dart format, test package)
- `standards/languages/lang-06_typescript_standards.md` — TypeScript (pnpm, prettier, eslint, vitest, strict mode)
- `standards/languages/lang-07_javascript_standards.md` — JavaScript (pnpm, prettier, eslint, vitest)
- `standards/languages/lang-08_rust_standards.md` — Rust (cargo, rustfmt, clippy -D warnings in CI, cargo-deny, Result<T, E>)
- `standards/languages/lang-09_zig_standards.md` — Zig (zig build, zig fmt, manual memory management)
- `standards/languages/lang-10_ruby_standards.md` — Ruby (bundler, rubocop, sorbet, rspec)
- `standards/languages/lang-11_ruby_on_rails_standards.md` — Ruby on Rails (Rails 7.2+, rubocop-rails)
- `standards/languages/lang-12_go_standards.md` — Go (go modules, gofmt, go vet, golangci-lint, table-driven tests)
- `standards/languages/lang-13_elixir_standards.md` — Elixir (mix, mix format, credo, ExUnit)
- `standards/languages/lang-14_cpp_standards.md` — C++ (C++20 baseline, CMake presets, clang-format/clang-tidy, warnings-as-errors in CI, sanitizer lanes, C ABI ownership rules)

**Process Standards:**

- `standards/process/proc-01_documentation_standards.md` — ADR (bullet metadata), spec/plan/design-pass/verification docs, changelog, user docs
- `standards/process/proc-02_git_version_control_standards.md` — Git workflow, commits, branching
- `standards/process/proc-03_code_review_expectations.md` — Code review process and expectations
- `standards/process/proc-04_agent_workflow_standards.md` — Agent worktree/PR workflow
- `standards/process/proc-05_test_governance.md` — Test governance: quarantine registry, flake report, fast/slow tiers, routing table, scoped coverage, gates, PR evidence

**Security Standards:**

- `standards/security/sec-01_security_standards.md` — Security guidelines with P0-P2 severity model

**Shared Standards:**

- `standards/shared/core-standards.md` — Canonical cross-cutting standards (Clean Architecture, SOLID, naming, testing coverage targets) referenced by all agent configs

<!-- END GENERATED: standards-list -->

### Agent Configurations (`standards/agents/`)

Template configs deployed to consumer projects during setup:

- `claude-code/base-claude-code.md` — Claude Code (assembled to `CLAUDE.md`)
- `cursor/` — Cursor AI (assembled to `.cursorrules`)
- `copilot/.github/copilot-instructions.md` — GitHub Copilot
- `aider/.aiderrc` — Aider
- OpenAI Codex reads `AGENTS.md` at the project root (the legacy `codex/.codexrc` is deprecated)
- Gemini CLI config lives at `.gemini/` (root level, per Gemini convention)

### Scripts (`scripts/`)

All bash. Key scripts:

- `setup.sh` — Installs standards into a target project, detects and configures AI agents; copies the standards-review workflow template only when run with `--workflow`
- `sync-standards.sh` — Pulls latest standards and updates agent configs in consumer projects (honours `agents:`; `--aliases` opt-in)
- `diff-standards.sh` — Previews what sync would change; `--exit-code` makes it a CI gate
- `lint-standards.sh` — Standards compliance linter; outputs text, JSON, or SARIF. `--since <ref>`/`--changed` scope file scans to a PR's changed files; `--timeout <secs>` guards each check (`--fail-on-timeout` turns a timed-out check into a FAIL; security checks always FAIL on timeout). File-scanning checks enumerate via `git ls-files` through `scripts/lib/lint-files.sh`; `banned-functions` honour `lint.exclude` in `.standards.yml`, `no-secrets` never does (see `scripts/lint-checks/README.md`) Check modules live in `scripts/lint-checks/` (common: ci-workflow-hygiene, conventional-commits, coverage-config, doc-lint, headless-ci, no-secrets, quarantine-policy, test-directory-structure). Monorepos: the runner iterates the root plus every member (`members:` in `.standards.yml`, else auto-discovered `*/.standards.yml`, resolved by `scripts/lib/members.sh`) — repo-wide checks once at the root, project/language checks per member — and every JSON/SARIF result carries a `member` field
- `detect-languages.sh` — Manifest-based language detection for the root and the conventional sub-roots (`apps/*`, `packages/*`, `crates/*`, `core`, `server`, `web`, `shells/*`); `--skip <dir>` / `--root-only`
- `doctor.sh` — Health check; reports members, and per member compares detected vs declared languages and flags declared keys that have no standards document
- `add-copilot-instructions-pr.sh` — Creates a PR to add Copilot instructions to a repo
- `setup-git-aliases.sh` — Configures git aliases

### Document Templates (`templates/docs/`)

Copy-and-fill templates for the documents proc-01 asks for: `adr.md` (bullet metadata + Context/Decision/Consequences), `spec.md`, `plan.md`, `design-pass.md`, `verification.md`. `doc-lint` enforces the ADR fields and relative-link validity.

### Installation Flow

`install.sh` (root) is the one-line curl installer. It adds this repo as a `.standards/` submodule in the target project, runs `setup.sh` to configure agents, and adds a `make sync-standards` target.

## Conventions

- **Standards numbering**: Files use category-based prefixes (arch-XX, lang-XX, proc-XX). Preserve this naming scheme when adding new standards.
- **Conventional Commits**: `type(scope): subject` — types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
- **Temporary files**: Go in `.standards_tmp/` (gitignored).
- **Agent config consistency**: When modifying shared standards in `core-standards.md`, check that agent configs (`CLAUDE.md`, `.cursorrules`, copilot-instructions.md, `.aiderrc`, `AGENTS.md`, `GEMINI.md`) stay aligned.
- **Generated standards lists**: The standards file lists and language-detection maps in `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `CLAUDE.md`, and `standards/README.md` live between `<!-- BEGIN GENERATED: ... -->` / `<!-- END GENERATED: ... -->` sentinels and are rendered from the `standards/` tree by `scripts/generate-standards-lists.sh`. Never edit inside the sentinels. After adding, renaming, or removing a standards file: add or fix its row in `standards/catalog.tsv` (description + language triggers), run `make generate-standards-lists`, and commit. CI's `Agent Config Drift` job fails on any diff, on a reference to a missing file, or on an omitted one.
- **Shell scripts**: Must pass `bash -n` syntax validation.
- **Safety**: Never modify `.standards_tmp/`, `.secret`, or `.tfstate` files. Always preserve standards file numbering.
- **Worktree hygiene (proc-04)**: one gitignored worktree root per repo (`worktree_dir:` in `.standards.yml`, default `.claude/worktrees`), created from the main checkout only — never from inside another worktree. `setup.sh` gitignores the root and installs `templates/pre-commit-worktree-guard.example`; `make doctor` reports count/age/size; `make worktree-gc` collects merged, gone and idle worktrees. Tests: `scripts/test-worktree-gc.sh`.
- **Safe setup (1.2+)**: `setup.sh` never clobbers existing agent configs. Customized files are staged to `.standards-pending/` with a `MERGE_PLAN.md` describing how to reconcile them. The merge skill (`/merge-standards` in Claude Code / Cursor, `make merge-standards` via CLI) drives the agent-agnostic handoff.
- **Curated configs (#183)**: `project_overview:` / `key_commands:` in `.standards.yml` are the source for `{{PROJECT_OVERVIEW}}` / `{{KEY_COMMANDS}}` (filled-in text stays checksum-stable); `managed: { CLAUDE.md: false }` marks a config hand-curated (sync/setup leave it, doctor reports curated, diff-standards still previews upstream changes); `hooks: custom|lefthook|husky|standards` tells doctor and setup who owns the git hooks. Readers live in `scripts/lib/checksums.sh` (`yaml_block_scalar`, `yaml_map_value`, `file_managed`) and `scripts/lib/project-sections.sh` (capture hint).
