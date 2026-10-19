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

- A `.standards.yml` declarative config — declares your languages, agents, coverage thresholds, architecture mode, the project overview and key commands assembled into the agent configs, which configs are hand-curated (`managed:`), and your git hook manager (`hooks:`)
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

Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby, Ruby on Rails, Go, Elixir, C++

## Feature Highlights

- **Multi-Agent Sync** -- One standards source, every AI agent stays consistent. The workflow text is agent-neutral: every config names the same worktree root (`worktree_dir:` in `.standards.yml`), and the skills under `standards/skills/` reach each agent in its own shape -- Claude Code skills, Cursor commands, Copilot prompt files, a Skills index in `AGENTS.md` / `GEMINI.md` / the Aider instructions.
- **Clean Architecture** -- Enforces domain-driven design across all languages.
- **One-Command Setup** -- Install everything with a single command.
- **Auto-Updating** -- Git hooks keep standards in sync whenever you pull.
- **Preview Before You Commit** -- `--dry-run` flag for `setup.sh` and `sync-standards.sh` shows every write operation without modifying files. `make diff-standards` shows line-level diffs for all agent configs, and `diff-standards.sh --exit-code` turns that into a CI gate.
- **Install Only What You Use** -- `setup.sh --agents codex` (or any explicit list) installs just that agent's artifacts; git hooks, aliases, Cursor commands, `.claude/settings.json` and `.gemini/` are skipped unless requested. `setup.sh --help` lists every flag, and unknown flags exit 2 without writing anything.
- **Upgrade Path for Old Installs** -- `setup.sh --migrate` brings a pre-1.2 consumer forward: dead standards references are rewritten in place from `docs/reference/renamed-files.md`, `.codexrc` becomes `AGENTS.md`, `.standards.yml` and checksums are bootstrapped, and anything ambiguous is staged with a merge plan. `make doctor` recognises the shape and prints that one command instead of a page of warnings.
- **Standards Compliance Linter** -- `make lint-standards` checks commits, secrets, coverage (including `coverage.scopes` floors), the flaky-test quarantine registry, docs (ADR fields and relative links), type safety, and banned functions. Automated compliance checks currently ship for **Python, Swift, TypeScript, Rust, Go, Elixir, and C++** (plus common cross-language checks); the other seven language standards are documented but not yet machine-enforced (see [scripts/lint-checks/README.md](scripts/lint-checks/README.md)). Outputs text, JSON, or SARIF for GitHub Code Scanning. Monorepo-aware: declare `members:` in `.standards.yml` (or let `*/.standards.yml` be auto-discovered) and one run lints every sub-root against its own config.
- **Worktree Hygiene** -- One gitignored worktree root per repo (`worktree_dir:` in `.standards.yml`, default `.claude/worktrees`). `setup.sh` gitignores it and installs a pre-commit guard that refuses commits adding worktree paths; `make doctor` reports worktree count, idle age and size and warns on nesting; `make worktree-gc` removes merged, gone and idle worktrees and reports what it reclaimed. See [proc-04 § Worktree Hygiene](standards/process/proc-04_agent_workflow_standards.md#worktree-hygiene).
- **Automated PR Review** -- A composite GitHub Action posts structured standards compliance results as a PR comment on every pull request. Opt-in: install the workflow with `.standards/scripts/setup.sh --workflow` (or `./scripts/setup.sh --workflow` from a clone of this repo); blocks merge when checks fail.
- **Containerized Agent Development** -- [arch-09](standards/architecture/arch-09_containerized_agent_dev_standards.md) sandboxes autonomous agents in a disposable Docker dev container behind a deny-by-default egress proxy. Opt-in: `.standards/scripts/setup.sh --containerized` installs the [starter kit](templates/containerized-dev/README.md) (Dockerfiles, compose file, host-side scripts, proxy config, devcontainer, Cursor rules) without overwriting anything you already have, and git-ignores `.env` and `.env.secret`.
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
