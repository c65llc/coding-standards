# Repository Intelligence & Standards

## 🎯 Project Mission

This repository provides comprehensive development standards and guidelines for software projects, designed to work seamlessly with AI coding assistants including Cursor AI, GitHub Copilot, Claude Code (Aider), OpenAI Codex, Gemini CLI, and Google Antigravity.

The standards cover architecture patterns, language-specific conventions, process workflows, and automation requirements to ensure consistent, maintainable code across teams and projects.

## 🛠 Tech Stack & Constraints

- **Runtime:** Shell scripts (bash), Makefile automation
- **Documentation:** Markdown-based standards and guides
- **Version Control:** Git with Conventional Commits
- **AI Agent Integration:** Multi-agent support via configuration files
  - `.cursorrules` for Cursor AI
  - `.github/copilot-instructions.md` for GitHub Copilot
  - `.aiderrc` for Aider (Claude Code)
  - `.codexrc` for OpenAI Codex
  - `.gemini/` for Gemini CLI and Antigravity
- **Testing:** Standards validation via scripts
- **Deployment:** Git submodule or direct clone distribution

## 🏗 Coding Standards (Non-Negotiables)

- **Naming:** Follow language-specific conventions (see `standards/languages/`)
  - Python: `snake_case` for functions/variables, `PascalCase` for classes
  - JavaScript/TypeScript: `camelCase` for variables/functions, `PascalCase` for classes
  - Rust: `snake_case` for functions/variables, `PascalCase` for types
- **Patterns:** Clean Architecture with strict dependency rules (Domain → Application → Infrastructure)
- **Safety:** 
  - Do not modify files ending in `.secret` or `.tfstate`
  - Do not modify `.standards_tmp/` directory (temporary files only)
  - Preserve existing standards structure and numbering
- **Security:** Follow P0-P2 severity model in `standards/security/sec-01_security_standards.md`. P0/P1 violations block merge.
- **Commits:** Follow Conventional Commits format (`feat:`, `fix:`, `docs:`, `refactor:`, etc.)
- **Architecture:** SOLID principles required, violations must be justified
- **Documentation:** All standards must be documented in Markdown with clear examples

## 🚦 Definition of Done

1. Code passes shell script validation (`bash -n` for syntax)
2. Standards follow existing format and structure
3. Documentation in `/docs` is updated for user-facing changes
4. `make generate-standards-lists` has been run if standards files were added, renamed, or removed (CI's `check-agent-configs` fails on drift)
5. Git commits follow Conventional Commits format
6. Changes are tested in a sample project integration

## 📁 Repository Structure

```
.
├── .cursorrules                    # Cursor AI configuration
├── .gemini/                        # Gemini CLI & Antigravity config
│   ├── GEMINI.md                   # This file (primary agent context)
│   ├── settings.json               # Gemini CLI settings
│   └── active_mission.log          # Active Antigravity mission URL (gitignored)
├── Makefile                        # Automation targets
├── standards/                      # All standards documents
│   ├── architecture/              # Core architecture & automation
│   ├── languages/                 # Language-specific standards
│   ├── process/                   # Process & workflow standards
│   ├── security/                  # Security standards
│   └── agents/                    # Agent-specific configurations
├── scripts/                       # Automation scripts
└── docs/                          # User documentation
```

## 🔄 Agent Workflow Protocol

When working with this repository, agents must follow the A-P-E (Analyze, Plan, Execute) cycle:

### Analyze
- Read relevant standards files in `standards/` directory
- Check `.cursorrules` for overall project context
- Review existing patterns before making changes
- Identify affected documentation files

### Plan
- Generate a plan before writing code: `/plan "Add new language standard"`
- Identify all files that need updates (standards, `standards/catalog.tsv`, docs); agent config lists are regenerated, not hand-edited
- Consider impact on existing integrations
- Check for breaking changes

### Execute
- Use `gemini edit` to provide a diff for human review rather than overwriting files blindly
- Follow existing file structure and naming conventions
- Update related documentation
- Test changes in a sample project if possible

## 🛡️ Safety Constraints

- **Never modify:**
  - Files in `.standards_tmp/` (temporary only)
  - Files ending in `.secret` or `.tfstate`
  - Git history or commit messages (unless explicitly requested)
- **Always preserve:**
  - Existing standards file naming (e.g., `arch-01_`, `lang-01_`, `proc-01_`)
  - Directory structure and organization
  - Backward compatibility for existing integrations
- **Always update:**
  - Generated standards lists (run `make generate-standards-lists`) when adding, renaming, or removing standards — never edit between `<!-- BEGIN GENERATED -->` / `<!-- END GENERATED -->` sentinels
  - Documentation in `/docs` for user-facing changes
  - `CHANGELOG.md` for significant changes

## 📚 Key Standards Files

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

## 🔗 Integration Points

- **Setup Script:** `scripts/setup.sh` - Installs standards in client projects
- **Sync Script:** `scripts/sync-standards.sh` - Updates standards in client projects
- **Makefile:** `Makefile` - Provides automation targets (`make sync-standards`, `make pr`, etc.)
- **Install Script:** `install.sh` - One-command installation for client projects

## 🎯 Agent Onboarding

When starting work on this repository:

1. Read `.gemini/GEMINI.md` (this file) to understand architecture and constraints
2. **Check for an active Antigravity Mission** — see "Active Mission Tracking" below
3. Review `standards/architecture/arch-01_project_standards_and_architecture.md` for core principles
4. Check `.cursorrules` for Cursor AI integration patterns
5. Use checkpointing via Gemini CLI before attempting any refactors
6. Do not proceed with multi-file edits without first outputting a 'Proposed Logic Plan'
7. Verify changes don't break existing integrations

## 🚀 Active Mission Tracking

**Read protocol for all agents (Claude Code, Cursor, Aider, Codex, Gemini):**

Before starting work in this repo, check whether an Antigravity Mission is in flight:

```bash
[ -s .gemini/active_mission.log ] && head -1 .gemini/active_mission.log
```

If a Mission URL is present, you are working under that Mission's scope. Reference it in commit messages and avoid scope creep beyond its stated goals. If the file is empty or absent, no Mission is active — proceed under standard issue/PR tracking.

**Set/clear the Mission** with the helper scripts:

```bash
./scripts/mission-set.sh https://antigravity.google.com/missions/<id>   # at start
./scripts/mission-clear.sh                                              # on completion
```

Full convention (feature bracketing, lifecycle, what "stale" looks like) is documented in `standards/process/proc-04_agent_workflow_standards.md` § 5.

## 🐘 Postgres MCP (opt-in)

`.gemini/settings.json` ships a `postgres` MCP server entry that gives Gemini real-time schema validation during database work. It is **opt-in via env var**:

```bash
export POSTGRES_MCP_DATABASE_URL="postgresql://user:pass@host:5432/dbname"
```

When the env var is unset, the MCP server's launcher exits cleanly (`exit 0`) and Gemini continues without it. The launcher is a `sh -lc` wrapper that conditionally execs `npx -y @modelcontextprotocol/server-postgres` only when `POSTGRES_MCP_DATABASE_URL` is non-empty — robust across Gemini CLI versions that may or may not natively expand `${...}` inside JSON args. When set, Gemini gains live introspection of your schema for migration validation, query writing, and constraint checks.

**Remove the entire `"postgres"` block from `.gemini/settings.json`** if your project does not use Postgres. Future Gemini parser versions may reject unreachable MCP servers more strictly.

## 📝 Change Workflow

1. **Identify scope:** Which standards/documents are affected?
2. **Plan changes:** Create a plan showing all files to modify
3. **Implement:** Make changes following existing patterns
4. **Update integration:** Run `make generate-standards-lists` if standards files were added, renamed, or removed
5. **Update docs:** Update relevant documentation in `/docs`
6. **Test:** Verify changes work in a sample project
7. **Commit:** Use Conventional Commits format

## 🚨 Common Pitfalls

- **Don't:** Renumber standards files (breaks references)
- **Don't:** Modify `.standards_tmp/` files (temporary only)
- **Don't:** Hand-edit generated standards lists or skip `make generate-standards-lists` when adding standards
- **Don't:** Break backward compatibility without justification
- **Do:** Follow existing file structure and naming
- **Do:** Update documentation for user-facing changes
- **Do:** Test changes in a sample project integration
