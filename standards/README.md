# Standards

This directory contains all coding standards documents organized by category.

## Directory Structure

| Directory | Prefix | Contents |
|-----------|--------|----------|
| `architecture/` | `arch-XX` | Core architecture, automation, Cursor-specific |
| `languages/` | `lang-XX` | Per-language standards (Python, Java, Kotlin, Swift, Dart, TypeScript, JavaScript, Rust, Zig, Ruby/Rails) |
| `process/` | `proc-XX` | Documentation, git workflow, code review, agent workflow |
| `security/` | `sec-XX` | Security guidelines with P0-P2 severity model |
| `shared/` | — | Cross-cutting standards (`core-standards.md`) referenced by all agent configs |
| `agents/` | — | Template configs for AI coding assistants (Copilot, Aider, Codex, Gemini) |

## Naming Convention

Files use category-based prefixes with zero-padded numbers:

```text
<category>-<number>_<descriptive_name>.md
```

Examples: `arch-01_project_standards_and_architecture.md`, `lang-05_dart_standards.md`, `sec-01_security_standards.md`

When adding new standards, use the next available number in the appropriate category.

## Content Blocks (`shared/blocks/`)

Atomic content fragments used to assemble agent configs at setup time. Each block is a condensed summary (~5-20 lines) of standards content, written in imperative style for token-efficient agent consumption.

- **Common blocks** (always included): architecture-core, testing-policy, security-summary, naming-conventions, git-workflow, documentation-policy
- **Language blocks** (per detection): lang-python, lang-typescript, lang-javascript, lang-java, lang-kotlin, lang-swift, lang-dart, lang-rust, lang-zig, lang-ruby, lang-rails
- **Role blocks** (one per project): role-service, role-library, role-app, role-data-pipeline

## Agent Base Templates (`agents/`)

Agent-specific behavioral rules. Combined with content blocks by `scripts/assemble-config.sh` to produce self-contained configs for consumer projects.

- `claude-code/base-claude-code.md` → assembles `CLAUDE.md`
- `cursor/base-cursor.md` → assembles `.cursorrules`
- `copilot/base-copilot.md` → assembles `.github/copilot-instructions.md`
- `gemini/base-gemini.md` → assembles `.gemini/GEMINI.md`
- `aider/base-aider.md` + `aiderrc.template` → assembles `.aider-instructions.md` + `.aiderrc`
- `codex/base-codex.md` → assembles `AGENTS.md`
