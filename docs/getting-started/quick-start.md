---
title: "Quick Start"
description: "Get up and running with coding standards in 5 minutes."
---

# Quick Start

Get up and running with project standards in 5 minutes.

## Step 1: Install Standards

**Option A: One-line installer**

```bash
curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash
```

**Option B: Git submodule (recommended for teams)**

```bash
git submodule add https://github.com/c65llc/coding-standards.git .standards
```

**Option C: Clone directly**

```bash
git clone https://github.com/c65llc/coding-standards.git .standards
```

## Step 2: Run Setup

```bash
.standards/scripts/setup.sh                # configure the agents already in your project
.standards/scripts/setup.sh --agents all   # or configure every supported agent
.standards/scripts/setup.sh --help         # list every flag
```

Supported agents and the files setup assembles for them:

- `CLAUDE.md` (and `.claude/settings.json`) for Claude Code
- `.cursorrules` and `.cursor/commands/` for Cursor AI
- `.github/copilot-instructions.md` for GitHub Copilot
- `.gemini/GEMINI.md` and `.gemini/settings.json` for Gemini CLI
- `AGENTS.md` for OpenAI Codex
- `.aider-instructions.md` and `.aiderrc` for Aider

Pass an explicit `--agents` list (for example `--agents codex`) to install only that agent's artifacts: git hooks, git aliases, Cursor commands, `.claude/settings.json` and `.gemini/` are skipped unless the owning agent is listed. Unknown flags exit 2 without writing anything.

## Step 3: Restart Your Editor

Quit and reopen your editor (Cursor, VS Code, etc.) to load the new configuration.

## Common Commands

```bash
# Initial setup
make setup

# Sync to latest standards
make sync-standards

# Check if standards are current
make check-standards

# Update the standards submodule
make update-standards
```

## Project Layout After Setup

```text
your-project/
├── .cursorrules            # Cursor AI configuration
├── .github/
│   └── copilot-instructions.md  # GitHub Copilot config
├── .aiderrc                # Aider / Claude Code config
├── .codexrc                # OpenAI Codex config
├── .gemini/
│   ├── GEMINI.md           # Gemini CLI context
│   └── settings.json       # Gemini CLI settings
├── .standards/             # Standards submodule
│   ├── standards/          # Standards documents
│   ├── scripts/            # Automation scripts
│   └── docs/               # Documentation
└── ...
```

## Keeping Standards Up to Date

Team members sync by running:

```bash
make sync-standards
# or
.standards/scripts/sync-standards.sh
```

## Troubleshooting

**Editor not using standards?**

- Make sure `.cursorrules` (or the relevant config file) is in your project root.
- Restart your editor completely.

**Standards out of date?**

```bash
make sync-standards
```

## Next Steps

- [How It Works](./how-it-works.md) to understand the architecture and sync pipeline
- [Installation Guide](./installation.md) for detailed setup options
- [Multi-Agent Setup](../guides/multi-agent-setup.md) for configuring specific AI agents
- [Customization Guide](../guides/customization.md) to adapt standards for your team
