---
title: "Renamed Files"
description: "Old path to new path map for every standards document that was renamed or removed; consumed by setup.sh --migrate."
---

# Renamed Files

Standards documents have moved twice since the first installs: the `#21` renumbering (2026-03-03) replaced the flat numeric prefixes (`00_`, `03_`, `12_`, …) with category prefixes (`arch-`, `lang-`, `proc-`), and the `#40` block-assembly rewrite (2026-03-25) removed the Cursor automation standard and the hand-rolled agent templates. An agent config written against the old names cites files that exist in no release.

`setup.sh --migrate` reads the first table below and rewrites every dead reference it finds in the project's agent configs (`CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `.aider-instructions.md`, `.aiderrc`, `.codexrc`). `doctor.sh` uses the same table to recognise a pre-1.2 install and point at that one command. See [Scripts: setup.sh](scripts.md#setupsh) for what the migration does end to end.

## Standards documents

Paths are relative to the standards checkout (`.standards/` in a consumer project). A rename keeps the file in its category directory, so a reference such as `standards/languages/03_python_standards.md` becomes `standards/languages/lang-01_python_standards.md`; the migration swaps the file name and leaves whatever prefix the config used (`standards/…`, `.standards/standards/…`, or a bare file name).

A row whose new path is `(removed)` has no replacement. The migration deletes a list item or comment line that only cites the removed file; a reference inside running text is left in place and listed under *Migration* in `.standards-pending/MERGE_PLAN.md` for a manual decision.

Keep the table between the markers machine-readable: one row per file, back-ticked paths, `(removed)` for a deletion, and a new path that exists in this repository (`scripts/test-setup-safe.sh` checks every target).

<!-- BEGIN RENAME MAP — consumed by scripts/lib/migrate.sh; keep one row per file, back-ticked paths, "(removed)" for deletions -->

| Old path | New path | Changed in | Notes |
| --- | --- | --- | --- |
| `standards/architecture/00_project_standards_and_architecture.md` | `standards/architecture/arch-01_project_standards_and_architecture.md` | #21 (2026-03-03) | |
| `standards/architecture/01_automation_standards.md` | `standards/architecture/arch-02_automation_standards.md` | #21 (2026-03-03) | |
| `standards/architecture/02_cursor_automation_standards.md` | (removed) | #21 renamed it to `arch-03_…`; #40 (2026-03-25) removed it | Cursor guidance is assembled into `.cursorrules` from `standards/agents/cursor/base-cursor.md`; interaction modes live in `.cursor/commands/` |
| `standards/architecture/arch-03_cursor_automation_standards.md` | (removed) | #40 (2026-03-25) | Same replacement as above; the v1.0 `.cursorrules` still cited it |
| `standards/architecture/16_data_versioning_and_migration_standards.md` | `standards/architecture/arch-04_data_versioning_and_migration_standards.md` | #21 (2026-03-03) | |
| `standards/architecture/17_resilient_architecture_patterns.md` | `standards/architecture/arch-05_resilient_architecture_patterns.md` | #21 (2026-03-03) | |
| `standards/languages/03_python_standards.md` | `standards/languages/lang-01_python_standards.md` | #21 (2026-03-03) | |
| `standards/languages/04_java_standards.md` | `standards/languages/lang-02_java_standards.md` | #21 (2026-03-03) | |
| `standards/languages/05_kotlin_standards.md` | `standards/languages/lang-03_kotlin_standards.md` | #21 (2026-03-03) | |
| `standards/languages/06_swift_standards.md` | `standards/languages/lang-04_swift_standards.md` | #21 (2026-03-03) | |
| `standards/languages/07_dart_standards.md` | `standards/languages/lang-05_dart_standards.md` | #21 (2026-03-03) | |
| `standards/languages/08_typescript_standards.md` | `standards/languages/lang-06_typescript_standards.md` | #21 (2026-03-03) | |
| `standards/languages/09_javascript_standards.md` | `standards/languages/lang-07_javascript_standards.md` | #21 (2026-03-03) | |
| `standards/languages/10_rust_standards.md` | `standards/languages/lang-08_rust_standards.md` | #21 (2026-03-03) | |
| `standards/languages/11_zig_standards.md` | `standards/languages/lang-09_zig_standards.md` | #21 (2026-03-03) | |
| `standards/process/12_documentation_standards.md` | `standards/process/proc-01_documentation_standards.md` | #21 (2026-03-03) | |
| `standards/process/13_git_version_control_standards.md` | `standards/process/proc-02_git_version_control_standards.md` | #21 (2026-03-03) | |
| `standards/process/14_code_review_expectations.md` | `standards/process/proc-03_code_review_expectations.md` | #21 (2026-03-03) | |
| `standards/process/15_agent_workflow_standards.md` | `standards/process/proc-04_agent_workflow_standards.md` | #21 (2026-03-03) | |

<!-- END RENAME MAP -->

## Agent templates and consumer files

These moves are informational: the migration does not rewrite text that mentions them. It does convert a consumer's `.codexrc` to `AGENTS.md` and retires a legacy `.standards-config` once `.standards.yml` is written.

| Old | New | Changed in | Notes |
| --- | --- | --- | --- |
| `standards/agents/aider/.aiderrc` | `standards/agents/aider/aiderrc.template` + `standards/agents/aider/base-aider.md` | #40 (2026-03-25) | `.aiderrc` is now a short verbatim copy; the rules live in the assembled `.aider-instructions.md`. Coverage floors follow `core-standards.md` (95%, domain 100%); no model is pinned |
| `standards/agents/codex/.codexrc` | `standards/agents/codex/base-codex.md` | #40 (2026-03-25) | OpenAI Codex reads `AGENTS.md` at the project root; a consumer `.codexrc` is converted by `setup.sh --migrate` |
| `standards/agents/copilot/.github/copilot-instructions.md` | `standards/agents/copilot/base-copilot.md` | #40 (2026-03-25) | Assembled to `.github/copilot-instructions.md` |
| `standards/agents/claude-code/CLAUDE.md.template` | `standards/agents/claude-code/base-claude-code.md` | #40 (2026-03-25) | Assembled to `CLAUDE.md` |
| `.standards-config` (consumer, `KEY=value`) | `.standards.yml` | 1.1 | `read_standards_config` still reads the legacy file; `setup.sh --migrate` writes `.standards.yml` from it and keeps the original as `.standards-config.pre-standards-setup` |
| `.codexrc` (consumer) | `AGENTS.md` | #40 (2026-03-25) | Converted in place by `setup.sh --migrate`; staged as `.standards-pending/AGENTS.md.from-codexrc` when an `AGENTS.md` already exists |

## Adding a row

When a standards document is renamed or removed, add its row to the first table in the same commit (old path, new path or `(removed)`, the PR and date, and where the content went). `scripts/test-setup-safe.sh` verifies that every new path resolves to a file in this repository, so a stale row fails CI rather than rewriting one dead reference into another.
