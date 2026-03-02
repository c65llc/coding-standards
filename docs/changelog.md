---
title: "Changelog"
description: "All notable changes to the coding standards project."
---

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Multi-agent support for GitHub Copilot, Aider (Claude Code), OpenAI Codex, Gemini CLI, and Google Antigravity
- `.github/copilot-instructions.md` for GitHub Copilot configuration
- `.aiderrc` for Aider (Claude Code) configuration
- `.codexrc` for OpenAI Codex configuration
- `.gemini/GEMINI.md` for Gemini CLI and Antigravity repository intelligence
- `.gemini/settings.json` for Gemini CLI configuration (checkpointing, model, MCP servers)
- `standards/shared/core-standards.md` - Shared core standards for all agents
- `standards/agents/` directory structure for agent-specific configurations
- `make setup-agents` target for setting up AI agent configurations
- Comprehensive multi-agent setup guide
- Codebase review and improvement plan
- Updated setup and sync scripts to automatically configure all supported agents

### Changed

- Updated `scripts/setup.sh` to detect and configure multiple AI agents (including Gemini CLI and Antigravity)
- Updated `scripts/sync-standards.sh` to sync all agent configurations (including Gemini CLI and Antigravity)
- Updated `install.sh` to show which agent configurations were installed

### Improved

- Better collaboration support for non-Cursor users
- Consistent standards across all AI coding assistants
- Enhanced documentation for multi-agent workflows
