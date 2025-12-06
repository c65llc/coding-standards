# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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
- Updated `scripts/setup.sh` to detect and configure multiple AI agents
- Updated `scripts/sync-standards.sh` to sync all agent configurations
- Updated `install.sh` to show which agent configurations were installed
- Updated `README.md` to mention multi-agent support
- Updated `STRUCTURE.md` to include new agent directories

### Improved
- Better collaboration support for non-Cursor users
- Consistent standards across all AI coding assistants
- Enhanced documentation for multi-agent workflows

