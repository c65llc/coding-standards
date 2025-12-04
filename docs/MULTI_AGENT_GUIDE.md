# Multi-Agent Support Guide

This repository supports multiple AI coding assistants to ensure all team members can benefit from project standards, regardless of their preferred tool.

## Supported AI Agents

### 1. Cursor AI
- **Configuration File**: `.cursorrules`
- **Location**: Project root
- **Setup**: Automatically configured by `make setup` or `./scripts/setup.sh`
- **Usage**: Cursor automatically reads `.cursorrules` when you open the project

### 2. GitHub Copilot
- **Configuration File**: `.github/copilot-instructions.md`
- **Location**: `.github/` directory in project root
- **Setup**: Automatically configured by `make setup` or `./scripts/setup.sh`
- **Usage**: Copilot reads this file when providing suggestions in VS Code, JetBrains IDEs, or GitHub.com
- **Restart Required**: Yes, restart your IDE after setup/sync

### 3. Aider (Claude Code)
- **Configuration File**: `.aiderrc`
- **Location**: Project root
- **Setup**: Automatically configured by `make setup` or `./scripts/setup.sh`
- **Usage**: Aider automatically reads `.aiderrc` when you run `aider` in the project
- **Installation**: Install Aider with `pip install aider-chat`

### 4. OpenAI Codex
- **Configuration File**: `.codexrc`
- **Location**: Project root
- **Setup**: Automatically configured by `make setup` or `./scripts/setup.sh`
- **Usage**: Depends on your IDE's Codex integration

## Setup

### Initial Setup

When you install standards in a project, all supported agent configurations are automatically set up:

```bash
# Using the installer
curl -fsSL https://raw.githubusercontent.com/c65llc/coding_standards/main/install.sh | bash

# Or manually
git submodule add https://github.com/c65llc/coding_standards.git .standards
.standards/scripts/setup.sh
```

This will create:
- `.cursorrules` for Cursor AI
- `.github/copilot-instructions.md` for GitHub Copilot
- `.aiderrc` for Aider (Claude Code)
- `.codexrc` for OpenAI Codex

### Updating Agent Configurations

When standards are updated, sync all agent configurations:

```bash
make sync-standards
# or
.standards/scripts/sync-standards.sh
```

This updates all agent configuration files to match the latest standards.

### Manual Setup

If you only want to set up agent configurations without full standards setup:

```bash
make setup-agents
# or
.standards/scripts/setup.sh
```

## Agent-Specific Details

### GitHub Copilot

**Priority**: High (most important for GitHub integration)

GitHub Copilot uses `.github/copilot-instructions.md` to understand your project's coding standards. This file:

- References all standards documents
- Provides behavior rules for Copilot
- Ensures consistency with Cursor AI behavior

**After Setup:**
1. Restart your IDE (VS Code, JetBrains, etc.)
2. Copilot will automatically use the instructions
3. You'll see suggestions that follow project standards

**Verification:**
- Check that `.github/copilot-instructions.md` exists
- Ask Copilot to generate code and verify it follows standards
- Check that naming conventions match your language standards

### Aider (Claude Code)

Aider uses `.aiderrc` for configuration. This file:

- Configures Claude model settings
- Sets file inclusion/exclusion patterns
- References project standards
- Configures code style and architecture rules

**After Setup:**
1. Install Aider: `pip install aider-chat`
2. Run `aider` in your project
3. Aider will automatically read `.aiderrc`

**Verification:**
- Check that `.aiderrc` exists
- Run `aider --help` to verify installation
- Ask Aider to make changes and verify it follows standards

### OpenAI Codex

Codex uses `.codexrc` for configuration. This file:

- References all standards documents
- Provides guidelines for code suggestions
- Ensures consistency across agents

**After Setup:**
- Depends on your IDE's Codex integration
- Check your IDE's documentation for Codex support

## Standards Source

All agent configurations reference the same standards documents:

- **Architecture**: `standards/architecture/`
- **Languages**: `standards/languages/`
- **Process**: `standards/process/`
- **Shared Core**: `standards/shared/core-standards.md`

This ensures consistency across all AI agents.

## Troubleshooting

### Agent Configuration Not Working

1. **Verify files exist:**
   ```bash
   ls -la .cursorrules .github/copilot-instructions.md .aiderrc .codexrc
   ```

2. **Re-run setup:**
   ```bash
   make setup-agents
   ```

3. **Check standards directory:**
   ```bash
   ls -la .standards/standards/agents/
   ```

### Copilot Not Following Instructions

1. **Restart IDE**: Fully quit and restart VS Code/JetBrains IDE
2. **Check file location**: Ensure `.github/copilot-instructions.md` exists
3. **Verify file content**: Check that the file references standards correctly
4. **GitHub.com**: If using Copilot on GitHub.com, ensure the file is committed

### Aider Not Reading Config

1. **Check file location**: Ensure `.aiderrc` is in project root
2. **Verify syntax**: Check that `.aiderrc` has valid syntax
3. **Run from project root**: Always run `aider` from the project root directory

## Collaboration

### For Non-Cursor Users

Team members using other tools can:

1. **Install standards** (same as Cursor users):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/c65llc/coding_standards/main/install.sh | bash
   ```

2. **Use their preferred agent**:
   - VS Code users: GitHub Copilot will automatically use instructions
   - Aider users: `.aiderrc` is automatically configured
   - Other tools: Check if they support similar configuration files

3. **Sync updates**:
   ```bash
   make sync-standards
   ```

### Ensuring Consistency

All agents reference the same standards, ensuring:
- Consistent code style across team members
- Same architecture principles
- Unified naming conventions
- Shared testing requirements

## Adding New Agents

To add support for a new AI agent:

1. **Create agent directory**: `standards/agents/<agent-name>/`
2. **Create configuration file**: Follow the agent's documentation
3. **Reference standards**: Include references to `standards/` directory
4. **Update setup script**: Add agent setup to `scripts/setup.sh`
5. **Update sync script**: Add agent sync to `scripts/sync-standards.sh`
6. **Update documentation**: Add agent to this guide

## Best Practices

1. **Always sync after pulling standards updates**:
   ```bash
   make sync-standards
   ```

2. **Restart IDEs after syncing** to load new configurations

3. **Commit agent config files** to version control so all team members benefit

4. **Verify agent behavior** by asking it to generate code and checking standards compliance

5. **Report issues** if an agent isn't following standards correctly

## Related Documentation

- [Quick Start Guide](QUICK_START.md) - Get started in 5 minutes
- [Setup Guide](SETUP_GUIDE.md) - Detailed setup instructions
- [Integration Guide](INTEGRATION_GUIDE.md) - Complete integration guide
- [Architecture Standards](../standards/architecture/00_project_standards_and_architecture.md) - Core standards

