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

Examples: `arch-01_core_architecture.md`, `lang-05_dart_standards.md`, `sec-01_security_standards.md`

When adding new standards, use the next available number in the appropriate category.
