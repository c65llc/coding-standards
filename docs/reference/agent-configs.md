---
title: "Agent Configurations"
description: "How each AI coding assistant is configured by this standards framework."
---

# Agent Configurations

This project distributes coding standards to multiple AI coding assistants simultaneously. Each agent has its own configuration format and file location.

## Cursor AI — `.cursorrules`

**Location:** Project root (`.cursorrules`)

Cursor reads this file automatically when opening a project. It contains instructions that guide Cursor's AI responses, including references to all standards documents.

**Format:** Plain text with markdown. Cursor treats the entire file as system-level context for its AI features.

**What's included:**

- References to all architecture, language, and process standards
- Instructions for Clean Architecture enforcement
- Code review and PR generation guidelines

## GitHub Copilot — `.github/copilot-instructions.md`

**Location:** `.github/copilot-instructions.md`

GitHub Copilot reads this file as custom instructions for code generation and chat. Available in VS Code, JetBrains, and Neovim with Copilot.

**Format:** Markdown. Copilot uses the content as additional context when generating suggestions.

**What's included:**

- Core standards summary (Clean Architecture, SOLID, naming conventions)
- Language-specific guidelines for supported languages
- Testing and error handling requirements

## Aider / Claude Code — `.aiderrc`

**Location:** Project root (`.aiderrc`)

Aider reads this YAML configuration file on startup. It controls model settings, conventions, and architectural rules.

**Format:** YAML with specific Aider configuration keys.

**Key settings:**

- `conventions` — coding style and architecture rules
- `architect-mode` — enables architecture-aware suggestions
- `read` — references to standards files Aider should be aware of

## OpenAI Codex — `.codexrc`

**Location:** Project root (`.codexrc`)

OpenAI Codex CLI reads this configuration file for project-specific instructions.

**Format:** YAML configuration.

**What's included:**

- Model and approval mode settings
- Instructions referencing core standards
- Architecture and testing requirements

## Gemini CLI & Antigravity — `.gemini/`

**Location:** `.gemini/GEMINI.md` and `.gemini/settings.json`

Gemini CLI and Google Antigravity read the `.gemini/` directory for repository intelligence and configuration.

**Files:**

- `GEMINI.md` — Repository context document. Contains project overview, architecture decisions, agent protocols, and standards references. Acts as the primary context for Gemini's understanding of the codebase.
- `settings.json` — CLI configuration including model selection, checkpointing, and MCP server settings.

## Adding a New Agent

To add support for a new AI coding assistant:

1. Create the agent's config file under `standards/agents/<agent-name>/`
2. Add the config to the setup script (`scripts/setup.sh`) so it gets copied during installation
3. Update the sync script (`scripts/sync-standards.sh`) to keep it updated
4. Document the new agent in this file
