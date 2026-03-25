# AGENTS.md

Instructions for OpenAI Codex CLI working in this coding standards repository.

## Environment

Sandboxed container. No interactive commands. Use non-interactive flags.

## This Repository

This is a **coding standards repository** — Markdown docs, bash scripts, and agent configs. Not an application.

## Key Commands

- `make test-scripts` — Validate bash script syntax
- `make test` — Run all tests (scripts + bootstrap + gh-task)
- `make lint` — Lint markdown files
- `bash -n scripts/<name>.sh` — Check individual script syntax

## Conventions

- Conventional Commits: type(scope): subject
- Standards numbering: category-based prefixes (arch-XX, lang-XX, proc-XX, sec-XX)
- Shell scripts must pass `bash -n` syntax validation
- When modifying shared standards in core-standards.md, verify agent configs stay aligned

## Architecture

Standards documents in `standards/` organized by category. Agent base templates in `standards/agents/`. Content blocks in `standards/shared/blocks/`. Scripts in `scripts/` are all bash.

## Testing

No test suites — primary tests are `bash -n` syntax checks on shell scripts. Run `make test` to validate.
