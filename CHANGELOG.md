# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **GitHub Project Lifecycle Automation Suite**
  - `bin/gh-task` - CLI tool for GitHub Projects V2 integration
  - Commands: `create`, `start`, `status`, `update`, `submit`
  - Automatic project status updates (Todo → In Progress → In Review → Done)
  - Branch management with naming conventions (`task/<id>-<title>`)
  - Pre-flight validation with test execution
  - Draft PR creation with automatic issue linking
- **Reusable GitHub Actions Workflows**
  - `.github/workflows/lifecycle-sync.yml` - Auto-sync project status on PR events
  - `.github/workflows/definition-of-done.yml` - Quality checks for PRs
- **PR Templates**
  - `.github/PULL_REQUEST_TEMPLATE/default.md` - Standard PR template with issue linking
- **Configuration Templates**
  - `templates/settings.json.example` - GitHub Projects V2 configuration
  - `templates/gh-task.conf.example` - Alternative configuration format
  - `templates/project-workflows.yml.example` - Example workflows for projects
- **Comprehensive Documentation**
  - `docs/GH_TASK_GUIDE.md` - Complete gh-task CLI reference (12k+ words)
  - `docs/GH_TASK_QUICKSTART.md` - 5-minute quick start guide
  - `docs/TOOLING.md` - Architecture and AI agent instructions (14k+ words)
  - `docs/PROJECT_SETUP_EXAMPLE.md` - Complete project setup walkthrough
- **Testing Infrastructure**
  - `scripts/test-gh-task.sh` - Comprehensive test suite for gh-task
  - `make test-gh-task` - Makefile target for testing
- Multi-agent support for GitHub Copilot, Aider (Claude Code), and OpenAI Codex
- `.github/copilot-instructions.md` for GitHub Copilot configuration
- `.aiderrc` for Aider (Claude Code) configuration
- `.codexrc` for OpenAI Codex configuration
- `standards/shared/core-standards.md` - Shared core standards for all agents
- `standards/agents/` directory structure for agent-specific configurations
- `make setup-agents` target for setting up AI agent configurations
- `docs/MULTI_AGENT_GUIDE.md` - Comprehensive guide for multi-agent support
- `REVIEW.md` - Codebase review and improvement plan
- Updated setup and sync scripts to automatically configure all supported agents

### Changed
- Updated `README.md` with GitHub Project Lifecycle Automation section
- Updated `README.md` repository structure to include new components
- Updated `scripts/setup.sh` to include gh-task setup instructions
- Updated `install.sh` to reference gh-task tooling
- Updated `.gitignore` to exclude `.gh-task-state` and `.gh-task.conf` files
- Updated `Makefile` with `test-gh-task` target
- Updated `scripts/setup.sh` to detect and configure multiple AI agents
- Updated `scripts/sync-standards.sh` to sync all agent configurations
- Updated `install.sh` to show which agent configurations were installed
- Updated `STRUCTURE.md` to include new agent directories

### Improved
- Better collaboration support for non-Cursor users
- Consistent standards across all AI coding assistants
- Enhanced documentation for multi-agent workflows



