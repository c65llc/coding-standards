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

### 5. Gemini CLI & Google Antigravity
- **Configuration File**: `.gemini/GEMINI.md` (primary), `.gemini/settings.json`
- **Location**: `.gemini/` directory in project root
- **Setup**: Automatically configured by `make setup` or `./scripts/setup.sh`
- **Usage**: 
  - **Gemini CLI**: Reads `.gemini/GEMINI.md` as primary context and `.gemini/settings.json` for CLI settings
  - **Antigravity**: Uses `.gemini/GEMINI.md` for mission context, `.gemini/active_mission.log` for cross-agent synchronization
- **Restart Required**: No (configuration is read on each command)

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
- `.gemini/GEMINI.md` and `.gemini/settings.json` for Gemini CLI & Antigravity

### Updating Agent Configurations

When standards are updated, sync all agent configurations:

```bash
make sync-standards
# or
.standards/scripts/sync-standards.sh
```

This updates all agent configuration files to match the latest standards. **If any agent configurations haven't been applied yet, they will be automatically added** (e.g., `.github/copilot-instructions.md` will be created if it doesn't exist).

### Manual Setup

If you only want to set up agent configurations without full standards setup:

```bash
make setup-agents
# or
.standards/scripts/setup.sh
```

### Adding Copilot Instructions to Existing Repository

To add GitHub Copilot custom instructions to an existing repository via PR:

```bash
make add-copilot-instructions
# or
.standards/scripts/add-copilot-instructions-pr.sh
```

This will:
1. Create a feature branch
2. Add `.github/copilot-instructions.md` to your repository
3. Create a PR with instructions for enabling Copilot code review

After the PR is merged, enable Copilot code review in repository settings:
- Settings > Copilot > Code review
- Toggle "Use custom instructions when reviewing pull requests" to on

## Agent-Specific Details

### GitHub Copilot

**Priority**: High (most important for GitHub integration)

GitHub Copilot uses `.github/copilot-instructions.md` to understand your project's coding standards. This file:

- References all standards documents
- Provides behavior rules for Copilot
- Ensures consistency with Cursor AI behavior
- **Enables Copilot code review** to follow project standards automatically

**After Setup:**
1. Restart your IDE (VS Code, JetBrains, etc.)
2. Copilot will automatically use the instructions
3. You'll see suggestions that follow project standards

**Enabling Code Review:**
1. Navigate to repository Settings > Copilot > Code review
2. Toggle "Use custom instructions when reviewing pull requests" to on
3. Copilot will now review PRs using your project standards

**Adding to Existing Repository:**
Use the automated PR creation:
```bash
make add-copilot-instructions
```

This creates a PR that adds `.github/copilot-instructions.md` with instructions for enabling code review.

**Verification:**
- Check that `.github/copilot-instructions.md` exists
- Ask Copilot to generate code and verify it follows standards
- Check that naming conventions match your language standards
- Create a test PR and verify Copilot code review uses custom instructions
- Confirm review comments reference project standards

**References:**
- [GitHub Docs: Add repository instructions](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions)
- [GitHub Docs: Configure code review](https://docs.github.com/en/copilot/how-tos/configure-custom-instructions/add-repository-instructions#enabling-or-disabling-custom-instructions-for-copilot-code-review)

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

### Gemini CLI & Google Antigravity

Gemini CLI and Google Antigravity use `.gemini/GEMINI.md` as the primary source of truth for AI agents. This file acts as the "system prompt" for the entire repository.

**Configuration Files:**
- `.gemini/GEMINI.md` - Repository intelligence and standards (primary context)
- `.gemini/settings.json` - Gemini CLI settings (checkpointing, model, MCP servers)
- `.gemini/active_mission.log` - Active Antigravity mission URL (gitignored, for cross-agent sync)

**Note on Configuration Location:**
Unlike other agents (Copilot, Aider, Codex) which store their configurations in `standards/agents/<agent>/`, Gemini CLI uses `.gemini/` at the project root. This follows the official Gemini CLI convention where the `.gemini/` directory is the standard location for Gemini-specific configuration files. The Gemini CLI automatically looks for `.gemini/GEMINI.md` and `.gemini/settings.json` in the project root, making this location consistent with Gemini CLI's expected behavior.

**Gemini CLI Workflow:**
Agents using Gemini CLI should follow the A-P-E (Analyze, Plan, Execute) cycle:

1. **Analyze**: Run `gemini -p "Identify dependencies in [filename]"`
2. **Plan**: Generate a plan before writing code: `/plan "Add OAuth2 flow"`
3. **Execute**: Use `gemini edit` to provide a diff for human review rather than overwriting files blindly

**Antigravity Integration:**
- **Mission Isolation**: Each major feature should be handled in a separate Antigravity Mission
- **Context Sharing**: Copy the URL of the current Mission into `.gemini/active_mission.log` to allow cross-agent synchronization
- **MCP Integration**: 
  - Enable Google Cloud MCP to allow agents to see live resource IDs
  - Enable Postgres/SQL MCP for real-time schema validation during migrations
- **Browser Agent Validation**: For UI-related code, agents should:
  - Spin up a local dev server
  - Use the Antigravity Browser Agent to take a screenshot of the change
  - Compare the screenshot against design requirements in `/assets/designs`

**After Setup:**
1. Install Gemini CLI: Follow [Gemini CLI installation guide](https://ai.google.dev/gemini-api/docs/cli)
2. Configure MCP servers (optional): Set up Google Cloud and Postgres MCP servers if needed
3. Start using: Run `gemini` commands in the project directory
4. For Antigravity: Create missions and reference `.gemini/GEMINI.md` for context

**Agent Onboarding Prompt:**
When starting a new AI agent session, paste this prompt:

```
I am working in a codebase optimized for Gemini CLI and Google Antigravity.

Start by reading .gemini/GEMINI.md to understand our architecture and constraints.

Use checkpointing via Gemini CLI before attempting any refactors.

If you need to verify UI changes, use the Antigravity Browser tool.

Do not proceed with multi-file edits without first outputting a 'Proposed Logic Plan'.
```

**Verification:**
- Check that `.gemini/GEMINI.md` exists and contains repository standards
- Check that `.gemini/settings.json` exists with proper configuration
- Run `gemini -p "What are the project standards?"` and verify it references `.gemini/GEMINI.md`
- For Antigravity: Verify missions can access repository context

**References:**
- [Gemini API Documentation](https://ai.google.dev/gemini-api/docs)
- [Model Context Protocol (MCP)](https://modelcontextprotocol.io/)

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
   ls -la .cursorrules .github/copilot-instructions.md .aiderrc .codexrc .gemini/GEMINI.md .gemini/settings.json
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

### Gemini CLI Not Reading Config

1. **Check file location**: Ensure `.gemini/GEMINI.md` exists in project root
2. **Verify file content**: Check that `.gemini/GEMINI.md` contains repository standards
3. **Check settings**: Verify `.gemini/settings.json` has valid JSON syntax
4. **Run from project root**: Always run `gemini` commands from the project root directory
5. **MCP servers**: If using MCP, verify servers are properly configured and running

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

