---
title: "Token-Efficient Agent Configs: 60% Smaller, Zero Traversal"
date: 2026-03-25
authors:
  - name: "C65 LLC"
---

AI coding agents are only as good as the context they're given. Until now, our agent configs pointed agents into the standards submodule — references like "See `standards/languages/lang-01_python_standards.md`" meant a diligent agent might read 800-1,200+ lines of documentation per session, much of it irrelevant to the project at hand. A Python web service doesn't need Rust, Swift, or Dart standards taking up context window space.

We've rebuilt the entire agent configuration system around a simple idea: **assemble one self-contained config per agent at setup time, with only the content that project actually needs.**

## How It Works

The setup script now assembles agent configs from three ingredients:

1. **Base template** (~25-40 lines) — agent-specific behavioral rules. Cursor gets interaction modes and custom commands. Gemini gets the A-P-E workflow. Aider gets diff mode guidance. Each agent gets only what's unique to how it works.

2. **Content blocks** (~5-20 lines each) — atomic summaries of standards, stored in `standards/shared/blocks/`. Six common blocks (architecture, testing, security, naming, git, documentation) are always included. Language and role blocks are selected based on detection.

3. **Language + role filtering** — `detect-languages.sh` identifies your project's languages (now with TypeScript, Rails, Java, and Kotlin sub-detection). You pick a project role (`--role service|library|app|data-pipeline`). Only relevant blocks are included.

The result: a Python/TypeScript web service gets a ~130-line CLAUDE.md with everything the agent needs — no submodule traversal required.

## What Changed

| Before | After |
|--------|-------|
| Agent reads 329-line config + traverses into 800+ lines of standards docs | Agent reads one ~130-line self-contained file |
| All 11 language standards included regardless of project | Only detected languages included |
| Security rules duplicated across 6 agent configs | Single `security-summary.md` block assembled into each |
| No `.cursorrules` template for consumer projects | Full Cursor template with assembly support |
| Codex used obsolete `.codexrc` format | Migrated to `AGENTS.md` (current OpenAI Codex CLI) |

## Standards Cleanup

We also deduplicated the standards docs themselves:

- **arch-01** reduced from 253 to ~30 lines (Sections 2-10 were verbatim copies of `core-standards.md`)
- **arch-03** deleted entirely — content distributed to the Cursor base template and `proc-04`
- **Banned-functions lists** removed from 8 language docs (now single source in `sec-01`)
- **Git aliases catalog** extracted from `proc-02` to a standalone reference doc

## All Six Agents Supported

Every agent gets a purpose-built base template with platform-specific best practices:

- **Claude Code** — worktree conventions, key commands structure
- **Cursor** — `@new-feature`/`@refactor`/`@debug`/`@review` modes, condensed custom commands
- **GitHub Copilot** — `/explain`, `/fix`, `/tests` guidance, code review behavior
- **Gemini CLI** — Analyze-Plan-Execute workflow, checkpointing
- **Aider** — two-file model (`.aiderrc` + `.aider-instructions.md`), diff mode guidance
- **Codex** — new `AGENTS.md` format with sandbox awareness

## Try It

Existing projects can pick up the new system by syncing their standards submodule:

```bash
cd .standards && git pull
./scripts/setup.sh --role service
```

The setup script detects your languages, assembles configs for all detected agents, and saves your selections to `.standards-config` for reproducible syncs. Project-specific customizations (anything below the `<!-- BEGIN PROJECT-SPECIFIC — DO NOT EDIT THIS LINE -->` marker) are preserved across re-assembly.

New projects get this automatically via the [standard install process](/docs/getting-started/installation/).
