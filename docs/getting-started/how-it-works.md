---
title: "How It Works"
description: "How Coding Standards distributes a single source of truth to every AI coding assistant in your workflow."
---

# How It Works

Coding Standards keeps every AI agent in your project aligned through a three-layer architecture: **standards → sync → agent configs**.

## The Big Picture

```text
┌─────────────────────────────────────────────────────┐
│  .standards/ (git submodule)                        │
│                                                     │
│  standards/                                         │
│  ├── shared/core-standards.md    ← single source    │
│  ├── architecture/arch-*.md        of truth         │
│  ├── languages/lang-*.md                            │
│  ├── process/proc-*.md                              │
│  ├── security/sec-*.md                              │
│  └── agents/                     ← templates        │
│      ├── copilot/                                   │
│      ├── aider/                                     │
│      └── codex/                                     │
│                                                     │
│  scripts/                                           │
│  ├── setup.sh                    ← one-time install │
│  └── sync-standards.sh           ← ongoing sync     │
└──────────────────┬──────────────────────────────────┘
                   │ setup.sh / sync-standards.sh
                   ▼
┌─────────────────────────────────────────────────────┐
│  your-project/                                      │
│  ├── .cursorrules              → Cursor AI          │
│  ├── .github/copilot-instructions.md → Copilot     │
│  ├── .aiderrc                  → Claude Code/Aider  │
│  ├── .codexrc                  → OpenAI Codex       │
│  ├── .gemini/GEMINI.md         → Gemini CLI         │
│  └── .claude/settings.json     → Claude Code tools  │
└─────────────────────────────────────────────────────┘
```

## Layer 1: Standards

All standards live in Markdown files inside `standards/`. They are the canonical source of truth — human-readable, version-controlled, and organized by category:

| Category | What it covers |
|----------|----------------|
| `shared/core-standards.md` | Cross-cutting rules: Clean Architecture, SOLID, naming, testing (95% coverage floor) |
| `architecture/` | Architecture patterns, automation, Cursor-specific automation |
| `languages/` | Per-language conventions for 10 languages (Python through Ruby/Rails) |
| `process/` | Documentation, git workflow, code review, agent workflow |
| `security/` | P0-P2 severity model, injection prevention, secrets, dependencies |

Every AI agent config references `core-standards.md` as its base, plus the relevant language and architecture standards.

## Layer 2: Distribution

Standards reach your project through a **git submodule** installed at `.standards/`. This gives you:

- **Version pinning** — your project references a specific commit of the standards repo
- **Atomic updates** — `make sync-standards` pulls the latest and regenerates all agent configs in one step
- **No copy-paste drift** — the submodule is the source; configs are derived from it

### Install Flow

```bash
# One-line installer adds the submodule and runs setup
curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash
```

Under the hood:

1. `install.sh` adds this repo as `.standards/` via `git submodule add`
2. `setup.sh` copies agent config templates to their expected locations
3. A `post-merge` git hook is installed to remind you when standards have upstream updates
4. A `make sync-standards` target is added to your Makefile

### Sync Flow

```bash
make sync-standards
```

This runs `sync-standards.sh`, which:

1. Pulls the latest commit in the `.standards/` submodule
2. Copies updated agent configs to project root (`.cursorrules`, `.aiderrc`, etc.)
3. Regenerates any derived configs (e.g., `.gemini/GEMINI.md`)
4. Prints a reminder to restart your editor

## Layer 3: Agent Configs

Each AI tool reads its own config file format. The sync step translates the shared standards into each format:

| Agent | Config file | What it contains |
|-------|------------|-----------------|
| Cursor AI | `.cursorrules` | Full standards inline — Cursor reads this on startup |
| GitHub Copilot | `.github/copilot-instructions.md` | Standards formatted for Copilot's instruction system |
| Claude Code / Aider | `.aiderrc` | References to standards files that Claude Code reads |
| OpenAI Codex | `.codexrc` | Codex-compatible instructions |
| Gemini CLI | `.gemini/GEMINI.md` | Repository context document for Gemini |

All configs point back to the same `core-standards.md`, so every agent enforces the same rules.

## Language-Aware Bootstrap

When `setup.sh` runs, it also detects your project's languages and generates a `settings.json` for Claude Code with the right tools pre-approved:

```text
Project files detected     →  Tools enabled in settings.json
─────────────────────────     ──────────────────────────────
*.py, pyproject.toml       →  ruff, pytest, mypy
Gemfile, *.rb              →  rubocop, rspec, brakeman
package.json, *.ts         →  eslint, vitest, tsc
Cargo.toml, *.rs           →  cargo test, cargo clippy
```

This means Claude Code can run your linters, test runners, and formatters without manual tool allowlisting.

## Update Lifecycle

```text
Standards repo                Your project
─────────────                 ────────────
New standard committed   →   (nothing yet)
                              make sync-standards
                         →   .standards/ updated
                         →   Agent configs regenerated
                         →   Restart editor
                         →   All agents use new rules
```

You control when updates land. Pin to a tag for stability, or track `main` for the latest.

## What Happens When You Add a Language

1. A new `lang-XX_<language>_standards.md` file is added to `standards/languages/`
2. `core-standards.md` is updated if the language introduces new cross-cutting rules
3. Agent config templates are updated to reference the new standard
4. On next `make sync-standards`, your project picks up the new language support

No config changes needed in your project — the sync handles everything.

## Next Steps

- [Quick Start](/getting-started/quick-start/) — install and set up in 5 minutes
- [Multi-Agent Setup](/guides/multi-agent-setup/) — detailed per-agent configuration
- [Customization](/guides/customization/) — fork and adapt for your team
