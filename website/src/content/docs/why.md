---
title: "Why Coding Standards?"
description: "How unified standards compare to ad-hoc approaches and why they matter for AI-assisted development."
---

# Why Coding Standards?

## The Problem

Your team uses multiple AI coding tools. Cursor for rapid development, Copilot for inline suggestions, Claude Code for complex refactors. Each tool needs its own configuration file, and without a shared source of truth, they generate inconsistent code.

The result:
- Different naming conventions from different agents
- Inconsistent architecture patterns across the codebase
- Code reviews spent catching style issues instead of logic bugs
- New team members confused by conflicting patterns

## The Old Way

**Ad-hoc standards:**
- Write a wiki page nobody reads
- Each developer configures their AI tools differently
- Standards drift over time
- No automated enforcement

**Per-tool configuration:**
- Maintain separate `.cursorrules`, `copilot-instructions.md`, `.aiderrc` files
- Each config written independently — they contradict each other
- No single source of truth
- Updating one tool means updating them all manually

## The New Way

**Coding Standards provides:**

One repository of standards → automatically synced to every AI agent.

| Capability | Ad-hoc | Per-tool configs | Coding Standards |
|-----------|--------|-----------------|-----------------|
| Single source of truth | No | No | Yes |
| Multi-agent sync | No | Manual | Automatic |
| Language coverage | Varies | Varies | 13 languages |
| Architecture enforcement | No | Limited | Clean Architecture built-in |
| Setup time | Hours | Hours per tool | 1 command, 5 minutes |
| Staying updated | Manual | Manual per tool | Auto via git hooks |
| Customizable | N/A | Per tool | Fork once, customize all |

## Key Benefits

### For Individual Developers
Install once and every AI tool in your workflow follows the same standards. No more switching mental models between tools.

### For Engineering Teams
Distribute standards to every project via git submodule. One update propagates everywhere. New hires get consistent AI assistance from day one.

### For Open Source Maintainers
Contributors using any AI tool will generate code that follows your project's conventions. Less time in code review, more time building.

## How It Works

1. **Install** — One command adds standards to your project as a git submodule
2. **Sync** — Setup script copies the right config file to each AI agent's expected location
3. **Develop** — Every AI tool follows the same standards automatically
4. **Update** — `make sync-standards` pulls the latest and re-syncs everything

See the full [How It Works](/getting-started/how-it-works/) page for the architecture, sync pipeline, and language-aware bootstrap details.

## Get Started

Ready to unify your AI coding standards?

- [Quick Start](/getting-started/quick-start/) — Up and running in 5 minutes
- [Installation Guide](/getting-started/installation/) — All installation options
- [Customization](/guides/customization/) — Fork and tailor to your team
