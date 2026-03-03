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
make sync-standards          # Sync standards files and update .cursorrules
make setup-agents            # Setup AI agent configurations
make add-copilot-instructions # Create PR to add Copilot instructions
```

There are no build steps, no test suites, and no application to run. The primary "tests" are `bash -n` syntax checks on shell scripts.

## Architecture

### Standards Documents (`standards/`)

Markdown files organized by category with prefix-based naming:
- `architecture/` (arch-01 through arch-03): Core architecture, automation standards, Cursor-specific automation
- `languages/` (lang-01 through lang-11): Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby, Ruby on Rails
- `process/` (proc-01 through proc-04): Documentation, git/version control, code review, agent workflow
- `security/` (sec-01): Security guidelines with P0-P2 severity model
- `shared/core-standards.md`: Canonical source of cross-cutting standards (Clean Architecture, SOLID, naming, testing coverage targets). All agent configs reference this file.

### Agent Configurations (`standards/agents/`)

Template configs deployed to consumer projects during setup:
- `copilot/.github/copilot-instructions.md` — GitHub Copilot
- `aider/.aiderrc` — Aider (Claude Code)
- `codex/.codexrc` — OpenAI Codex
- Gemini CLI config lives at `.gemini/` (root level, per Gemini convention)

### Scripts (`scripts/`)

All bash. Key scripts:
- `setup.sh` — Installs standards into a target project, detects and configures AI agents
- `sync-standards.sh` — Pulls latest standards and updates agent configs in consumer projects
- `add-copilot-instructions-pr.sh` — Creates a PR to add Copilot instructions to a repo
- `setup-git-aliases.sh` — Configures git aliases

### Installation Flow

`install.sh` (root) is the one-line curl installer. It adds this repo as a `.standards/` submodule in the target project, runs `setup.sh` to configure agents, and adds a `make sync-standards` target.

## Conventions

- **Standards numbering**: Files use category-based prefixes (arch-XX, lang-XX, proc-XX). Preserve this naming scheme when adding new standards.
- **Conventional Commits**: `type(scope): subject` — types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`
- **Temporary files**: Go in `.standards_tmp/` (gitignored).
- **Agent config consistency**: When modifying shared standards in `core-standards.md`, check that agent configs (`.cursorrules`, copilot-instructions.md, `.aiderrc`, `.codexrc`, `GEMINI.md`) stay aligned.
- **Shell scripts**: Must pass `bash -n` syntax validation.
- **Safety**: Never modify `.standards_tmp/`, `.secret`, or `.tfstate` files. Always preserve standards file numbering. Update `.cursorrules` when adding new standards.
