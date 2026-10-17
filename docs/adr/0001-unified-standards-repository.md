# ADR 0001: Unified Standards Repository

- **Status:** Accepted
- **Date:** 2025-12-22
- **Related:** —
- **Supersedes:** —
- **Extends:** —

## Context

Development teams increasingly rely on multiple AI coding assistants (Cursor, GitHub Copilot, Claude Code, OpenAI Codex, Gemini CLI). Each tool has its own configuration format, and without a shared source of truth, they produce inconsistent code that violates team conventions.

We needed a way to:

1. Define coding standards once and distribute them to every AI agent.
2. Keep standards in sync across projects without manual copy-paste.
3. Support multiple languages, architectures, and processes in a single framework.

## Decision

We will maintain a **single standards repository** distributed to consumer projects via **git submodule** (installed at `.standards/`).

Key design choices:

- **Markdown-based standards** — human-readable, diffable, and parseable by AI agents.
- **Category-prefixed naming** (`arch-XX`, `lang-XX`, `proc-XX`, `sec-XX`) — enables deterministic ordering and prevents numbering collisions when adding new standards.
- **Agent config templates** in `standards/agents/` — each AI tool gets a generated config that references `core-standards.md` as the canonical source.
- **One-line installer** (`install.sh`) — adds the submodule, runs setup, and configures a `make sync-standards` target.
- **Sync script** (`sync-standards.sh`) — pulls latest standards and regenerates agent configs in consumer projects.

## Consequences

### Positive

- Single source of truth for all coding standards across all AI agents.
- Adding a new standard or updating an existing one propagates to every consumer project on next sync.
- New AI agents can be supported by adding a template to `standards/agents/`.
- Standards are version-controlled with full git history.

### Negative

- Consumer projects take a dependency on this repository via submodule.
- Submodule workflows add complexity for developers unfamiliar with them.
- Standards updates require an explicit sync step (not fully automatic).

## Alternatives Considered

- **Copy-paste per project** — rejected due to drift and maintenance burden.
- **npm/pip package** — rejected because standards are language-agnostic Markdown, not code.
- **Monorepo template** — rejected because it couples application code to standards.
