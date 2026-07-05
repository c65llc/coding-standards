---
title: "Multi-Agent Setup"
description: "Configure multiple AI coding assistants to follow the same project standards."
---

# Multi-Agent Setup

This repository supports six AI coding assistants out of the box. Every agent reads the same underlying standards, so your team gets consistent suggestions regardless of which tool each person uses.

## Supported Agents

| Agent | Config File | Location |
| ----- | ----------- | -------- |
| Claude Code | `CLAUDE.md` | Project root |
| Cursor AI | `.cursorrules` | Project root |
| GitHub Copilot | `.github/copilot-instructions.md` | `.github/` directory |
| Aider | `.aiderrc` | Project root |
| OpenAI Codex | `AGENTS.md` | Project root |
| Gemini CLI / Antigravity | `.gemini/GEMINI.md`, `.gemini/settings.json` | `.gemini/` directory |

## Automatic Setup

Running the setup script configures every agent at once:

```bash
.standards/scripts/setup.sh
```

This creates all the configuration files listed above. If a file already exists, it is backed up before being replaced.

## Syncing All Agents

When standards are updated, sync everything in one command:

```bash
make sync-standards
# or
.standards/scripts/sync-standards.sh
```

Any agent configuration that has not been applied yet is added automatically during sync.

## Agent-Specific Details

### Claude Code

- **Config:** `CLAUDE.md` in your project root.
- **How it works:** Claude Code reads `CLAUDE.md` automatically when you run `claude` in the project directory, using it as project-specific guidance. Language-aware permissions and settings are written to `.claude/`.
- **After setup:** No restart needed; the config is read on each invocation. Customize `CLAUDE.md` with your project's specifics.

### Cursor AI

- **Config:** `.cursorrules` in your project root.
- **How it works:** Cursor reads this file on startup and uses it to guide code generation, refactoring, and review suggestions.
- **After setup:** Quit Cursor completely and reopen it.

### GitHub Copilot

- **Config:** `.github/copilot-instructions.md`.
- **How it works:** Copilot uses this file for code suggestions in VS Code, JetBrains, and on GitHub.com. It also powers Copilot code review on pull requests.
- **After setup:** Restart your IDE.
- **Enabling code review:**
  1. Go to repository **Settings > Copilot > Code review**.
  2. Turn on "Use custom instructions when reviewing pull requests".

To add Copilot instructions to an existing repo via a pull request:

```bash
make add-copilot-instructions
```

### Aider

- **Config:** `.aiderrc` in your project root.
- **How it works:** Aider reads `.aiderrc` automatically when you run `aider` in the project directory.
- **Installation:** `pip install aider-chat`
- **After setup:** No restart needed; the config is read on each invocation.

### OpenAI Codex

- **Config:** `AGENTS.md` in your project root. (The older `.codexrc` is deprecated; if present it is preserved but no longer the source of truth.)
- **How it works:** Codex reads `AGENTS.md` for project-specific guidance.
- **After setup:** Check your IDE's Codex integration documentation.

### Gemini CLI and Google Antigravity

- **Config:** `.gemini/GEMINI.md` (primary context) and `.gemini/settings.json` (CLI settings).
- **How it works:** Gemini CLI reads `.gemini/GEMINI.md` as the system prompt for the repository. The settings file controls checkpointing, model selection, and MCP server configuration.
- **Installation:** Follow the [Gemini CLI installation guide](https://ai.google.dev/gemini-api/docs/cli).
- **After setup:** No restart needed; configuration is read on each command.
- **Antigravity integration:** Each major feature should use a separate Antigravity Mission. Copy the mission URL into `.gemini/active_mission.log` for cross-agent synchronization.

## Standards Source

All agent configurations reference the same standards documents:

- `standards/architecture/` -- architecture and automation standards
- `standards/languages/` -- language-specific conventions
- `standards/process/` -- documentation, git workflow, code review
- `standards/shared/core-standards.md` -- shared core standards

This guarantees consistent behavior across every agent.

## Verification

After setup, verify each agent is working:

```bash
# Check that config files exist
ls -la CLAUDE.md .cursorrules .github/copilot-instructions.md .aiderrc AGENTS.md .gemini/GEMINI.md .gemini/settings.json
```

Then ask each agent to generate a small piece of code and confirm it follows the project's naming conventions and architecture rules.

## Adding a New Agent

1. Create a directory: `standards/agents/<agent-name>/`
2. Add the agent's configuration file with references to `standards/`.
3. Update `scripts/setup.sh` to copy the new config during setup.
4. Update `scripts/sync-standards.sh` to sync the new config.
5. Document the agent in this guide.

## Troubleshooting

### Agent not following standards

1. Confirm the config file exists in the expected location.
2. Re-run `make setup-agents` to regenerate configs.
3. Restart your editor.

### Copilot not reviewing with custom instructions

1. Make sure `.github/copilot-instructions.md` is committed to the repository.
2. Enable custom instructions in **Settings > Copilot > Code review**.

### Gemini CLI not reading config

1. Confirm `.gemini/GEMINI.md` exists at the project root.
2. Validate `.gemini/settings.json` is valid JSON: `python3 -m json.tool .gemini/settings.json`
3. Run Gemini commands from the project root directory.
