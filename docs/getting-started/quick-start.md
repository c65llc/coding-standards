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
.standards/scripts/setup.sh
```

This automatically configures all supported AI agents:

- `.cursorrules` for Cursor AI
- `.github/copilot-instructions.md` for GitHub Copilot
- `.aiderrc` for Aider / Claude Code
- `.codexrc` for OpenAI Codex
- `.gemini/GEMINI.md` and `.gemini/settings.json` for Gemini CLI

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

- [Installation Guide](../getting-started/installation.md) for detailed setup options
- [Multi-Agent Setup](../guides/multi-agent-setup.md) for configuring specific AI agents
- [Customization Guide](../guides/customization.md) to adapt standards for your team
