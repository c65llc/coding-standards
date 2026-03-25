# Coding Standards

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/c65llc/coding-standards/actions/workflows/ci.yml/badge.svg)](https://github.com/c65llc/coding-standards/actions/workflows/ci.yml)

Unified coding standards for every AI coding assistant.

Modern teams use multiple AI coding tools -- Cursor, Copilot, Claude Code, Codex, Gemini -- but each one needs its own configuration file. This project provides a single source of truth for coding standards that automatically syncs to every AI agent in your workflow. The result is consistent, high-quality AI-generated code across your entire team, whether you are a solo developer, an engineering organization, or an open-source maintainer.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash
```

## What You Get

The installer sets up the following in your project:

- A `.standards.yml` declarative config — declares your languages, agents, coverage thresholds, and architecture mode
- All AI agent configuration files (see table below)
- A `make sync-standards` Makefile target for on-demand updates
- A `make doctor` target for auditing your standards setup health
- Git hooks that keep standards in sync automatically

## Supported AI Agents

| Agent | Config File | Status |
|-------|-------------|--------|
| Cursor AI | `.cursorrules` | Supported |
| GitHub Copilot | `.github/copilot-instructions.md` | Supported |
| Claude Code / Aider | `CLAUDE.md`, `.aiderrc` + `.aider-instructions.md` | Supported |
| OpenAI Codex | `AGENTS.md` | Supported |
| Gemini CLI | `.gemini/GEMINI.md`, `.gemini/settings.json` | Supported |

## Supported Languages

Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby, Ruby on Rails, Go, Elixir

## Feature Highlights

- **Multi-Agent Sync** -- One standards source, every AI agent stays consistent.
- **Clean Architecture** -- Enforces domain-driven design across all languages.
- **One-Command Setup** -- Install everything with a single command.
- **Auto-Updating** -- Git hooks keep standards in sync whenever you pull.
- **GitHub Project Lifecycle** -- CLI-driven workflow connecting issues to Draft PRs via GitHub Projects V2.

## Documentation

- [Quick Start](https://coding-standards.c65llc.com/getting-started/quick-start/)
- [Installation Guide](https://coding-standards.c65llc.com/getting-started/installation/)
- [Multi-Agent Setup](https://coding-standards.c65llc.com/guides/multi-agent-setup/)
- [Full Documentation](https://coding-standards.c65llc.com)

## Contributing

We welcome bug reports and feature requests via GitHub Issues. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

MIT -- see [LICENSE](LICENSE).
