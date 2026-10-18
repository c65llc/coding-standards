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

## Aider — `.aiderrc` + `.aider-instructions.md`

**Location:** Project root (`.aiderrc`, `.aider-instructions.md`)

Aider reads `.aiderrc` on startup; it is a short verbatim copy of `standards/agents/aider/aiderrc.template` (`read = .aider-instructions.md`, `auto-lint`, `show-diffs`, the file-ignore list). The template pins no model: Aider takes it from its own config or `--model`, and a `model =` line the project adds to `.aiderrc` is carried into every refreshed copy, so a standards sync never changes which model a project runs. The coding standards and behavioural rules live in the assembled `.aider-instructions.md`, with the same 95% coverage floor (domain 100%) as every other agent config.

**Format:** Aider config keys (`.aiderrc`); Markdown (`.aider-instructions.md`).

A pre-1.2 `.aiderrc` copied from the old template carries `architecture_rules` / `testing_standards` blocks with 100/90/80 coverage tiers and a pinned `model =`; `setup.sh --migrate` raises the tiers to the floor, drops the template model line and rewrites its standards references (see [Renamed Files](renamed-files.md)).

## OpenAI Codex — `AGENTS.md`

**Location:** Project root (`AGENTS.md`)

OpenAI Codex CLI reads `AGENTS.md` for project-specific instructions. It is assembled from `standards/agents/codex/base-codex.md` plus the shared content blocks.

**Format:** Markdown.

**What's included:**

- Sandbox environment and approval-mode behaviour
- Instructions referencing core standards
- Architecture and testing requirements

The pre-#40 template was a comment-style `.codexrc`, which Codex no longer reads. `setup.sh` and `sync-standards.sh` warn when one is present; `setup.sh --migrate` converts it to Markdown `AGENTS.md` (or stages the conversion as `.standards-pending/AGENTS.md.from-codexrc` when an `AGENTS.md` already exists) and keeps the original as `.codexrc.pre-standards-setup`.

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
