# Token Efficiency & Agent Best Practices — Design Spec

**Date:** 2026-03-25
**Status:** Draft
**Goal:** Reduce per-agent-session token consumption in consumer projects by ~80-90%, ensure all 6 AI agent configs follow current best practices.

---

## Problem Statement

The coding standards repo serves agent configs and standards docs to consumer projects via submodule. Two problems exist:

1. **Token waste:** Agents in consumer projects potentially read 1,200+ lines / ~4,800 tokens of standards content per session, with 60-75% redundancy across configs and irrelevant content (e.g., a Python project loading Rust/Swift/Dart standards).
2. **Agent best practices gaps:** Missing `.cursorrules` template, no Copilot-specific features, obsolete Codex format (`.codexrc`), no context-length/performance guidance, inline duplication of security and testing rules across all 6 configs.

## Design Decisions

- **Primary optimization target:** Per-session token cost in consumer projects (not repo maintenance burden).
- **Filtering approach:** Language + role filtering at setup time.
- **Config style:** Medium configs with condensed inline summaries (~80-120 lines). Self-contained — agents read one file, no traversal needed.
- **Agent set:** All 6 agents retained (Cursor, Copilot, Gemini, Aider, Claude Code, Codex).
- **Codex:** Migrated from `.codexrc` to `AGENTS.md` format (current OpenAI Codex CLI).

---

## 1. Content Block System

### Overview

A `standards/shared/blocks/` directory containing atomic, reusable content fragments. Each block is a condensed summary (~5-20 lines) written in imperative, dense style — no preamble, no rationale, just rules and examples. Full rationale stays in the standards docs for human readers.

### Block Inventory

**Common blocks (always included):**

| Block File | Content | ~Lines |
|---|---|---|
| `security-summary.md` | P0/P1 one-liners, banned patterns, secret scanning rules | 15 |
| `testing-policy.md` | TDD mandate, 95% coverage, domain 100%, regression requirement | 8 |
| `naming-conventions.md` | Language-agnostic naming rules, boolean prefixes, architectural prefixes | 10 |
| `architecture-core.md` | Clean Architecture layers, dependency rule, SOLID one-liners | 12 |
| `git-workflow.md` | Conventional commits, branch naming, PR expectations | 10 |
| `documentation-policy.md` | What to document, ADR triggers, changelog rules | 8 |

**Language blocks (included per detection):**

| Block File | Content | ~Lines |
|---|---|---|
| `lang-python.md` | uv, ruff, mypy strict, pytest, Python-specific patterns | 12 |
| `lang-typescript.md` | pnpm, prettier, eslint, vitest, TS-specific patterns | 12 |
| `lang-javascript.md` | JS-specific notes, same tooling family as TS | 10 |
| `lang-java.md` | Gradle/Maven, JUnit, Java patterns | 10 |
| `lang-kotlin.md` | Kotlin-specific patterns, coroutines | 10 |
| `lang-swift.md` | Swift patterns, SwiftUI/UIKit | 10 |
| `lang-dart.md` | Flutter/Dart patterns, pub | 10 |
| `lang-rust.md` | cargo, clippy, unsafe rules, error handling | 12 |
| `lang-zig.md` | Zig patterns, allocator conventions | 10 |
| `lang-ruby.md` | Bundler, RuboCop, Ruby patterns | 10 |
| `lang-rails.md` | Rails conventions, ActiveRecord, testing | 12 |

**Role blocks (one selected per project):**

| Block File | Content | ~Lines |
|---|---|---|
| `role-service.md` | API design, error responses, health checks, observability | 10 |
| `role-library.md` | Public API design, semver, minimal dependencies | 8 |
| `role-app.md` | UI patterns, state management, accessibility | 10 |
| `role-data-pipeline.md` | Data versioning, migration patterns, idempotency | 10 |

### Block Writing Guidelines

- Imperative voice: "Use ruff for linting" not "You should use ruff for linting"
- No explanations of why — just rules
- One concept per line where possible
- Code examples only when the pattern isn't obvious from the rule
- Each block must be self-contained (no cross-references to other blocks)

---

## 2. Agent Base Templates

Each agent gets a base template in `standards/agents/<agent>/` containing only agent-specific behavioral rules. No standards content — that comes from blocks.

### Base Template Inventory

| Agent | File | Location in Consumer Project | ~Lines | Unique Content |
|---|---|---|---|---|
| Claude Code | `base-claude-code.md` | `CLAUDE.md` | 30 | CLAUDE.md structure, key commands, conventions, architecture overview placeholder |
| Cursor | `base-cursor.md` | `.cursorrules` | 35 | Interaction modes, condensed command signatures, reference to `.cursor/commands/` |
| Copilot | `base-copilot.md` | `.github/copilot-instructions.md` | 25 | `/explain`, `/fix`, `/tests` guidance, workspace context strategy, chat panel usage |
| Gemini | `base-gemini.md` | `.gemini/GEMINI.md` | 30 | A-P-E workflow, checkpointing, `active_mission.log`, safety constraints |
| Aider | `base-aider.md` | `.aiderrc` | 25 | Model selection, file exclusion, diff mode, `/add`/`/edit`/`/ask` usage |
| Codex | `base-codex.md` | `AGENTS.md` | 25 | Sandbox awareness, approval mode, tool usage patterns, no interactive commands |

### Assembly Formula

```
[agent base template]
+ ## Architecture
  [architecture-core block]
+ ## Testing
  [testing-policy block]
+ ## Security
  [security-summary block]
+ ## Naming Conventions
  [naming-conventions block]
+ ## Git Workflow
  [git-workflow block]
+ ## Documentation
  [documentation-policy block]
+ ## Language Standards
  [detected language blocks...]
+ ## Project Type
  [selected role block]
```

### Assembled Config Expectations

A Python/TypeScript web service using Claude Code:
- ~127 lines / ~508 tokens
- **89% reduction** from current potential of ~1,202 lines / ~4,800 tokens

A Rust library using Aider:
- ~103 lines / ~412 tokens

A Dart/Swift mobile app using Cursor:
- ~125 lines / ~500 tokens

---

## 3. Standards Document Deduplication

These changes reduce maintenance burden and enforce single sources of truth. They don't affect per-session cost (agents won't read these docs directly after this change).

| Document | Action | Before | After |
|---|---|---|---|
| **arch-01** | Gut and redirect — keep Section 1 (AI Behavior Guidelines), replace Sections 2-10 with cross-references to core-standards.md | 253 lines | ~40 lines |
| **arch-03** | Delete — merge Cursor interaction modes into Cursor base template, fold context handling into proc-04 | 47 lines | 0 lines |
| **arch-05** | Remove duplicated coverage gates (Section 1) and naming conventions (Section 6), replace with cross-references. Keep unique patterns. | 135 lines | ~90 lines |
| **proc-02** | Extract 60-line git alias catalog to `docs/reference/git-aliases.md`. proc-02 links to it. | 487 lines | ~430 lines |
| **Language docs** | Remove inline banned-functions lists, replace with "See sec-01 Section 4" reference | varies | -5 to -15 lines each |

**Net effect:** ~350 lines removed, arch-03 deleted, zero content lost.

---

## 4. Enhanced Setup Script

### New Interface

```bash
setup.sh [--role <service|library|app|data-pipeline>] \
         [--agents <comma-separated>] \
         [--languages <comma-separated override>]
```

- `--role` defaults to `service`
- `--agents` defaults to all detected agents (based on existing config files in the project)
- `--languages` overrides auto-detection from `detect-languages.sh`

### Assembly Logic

```
1. Run detect-languages.sh (or use --languages override)
2. Determine role from --role flag (default: service)
3. For each agent in target set:
   a. Read base template from standards/agents/<agent>/
   b. Read common blocks: architecture-core, testing-policy,
      security-summary, naming-conventions, git-workflow,
      documentation-policy
   c. Read language blocks for each detected language
   d. Read role block for selected role
   e. Concatenate with ## section headers between blocks
   f. Prepend header: "# Assembled by coding-standards setup.sh — do not edit directly"
   g. Write to correct location in consumer project
4. Copy relevant tooling configs (ruff.toml, .prettierrc, .rubocop.yml,
   clippy.toml, etc.) for detected languages
```

### Key Behaviors

- **Idempotent:** Running setup twice produces the same result.
- **Project-specific section preserved:** If the assembled config contains a `## Project-Specific` section at the bottom, setup reads it from the existing config and appends it after re-assembly.
- **`sync-standards.sh` integration:** Re-runs assembly to pick up block updates from the submodule.
- **Deprecation warning:** If `.codexrc` exists in consumer project, `sync-standards.sh` warns it's deprecated and `AGENTS.md` is the replacement.

---

## 5. Codex Migration

### Old Format (`.codexrc`)
- 77 lines of comment blocks
- All `##` headers + `#` comments
- Passive reference only, no agent-specific features

### New Format (`AGENTS.md`)
- Standard markdown, per current OpenAI Codex CLI spec
- Supports instructions, tool guidance, sandbox awareness
- Base template (~25 lines) covers:
  - Sandbox environment awareness
  - Read project structure before changes
  - Approval mode guidance (full-auto vs. suggest)
  - Tool usage patterns (terminal, file edits)
  - No interactive commands constraint

### Migration Path
- `setup.sh` generates `AGENTS.md` instead of `.codexrc`
- `sync-standards.sh` warns if `.codexrc` found, does not delete it
- This repo: replace root `.codexrc` with `AGENTS.md`
- Update `standards/agents/codex/` directory to contain new base template

---

## 6. New `.cursorrules` Template

Currently missing — Cursor config cannot be auto-deployed to consumer projects.

### Fix
- Create `standards/agents/cursor/base-cursor.md` as the base template
- Cursor's `\address_feedback` workflow condensed from 183 lines to ~15 lines:
  - Command signature + brief steps
  - Reference to `.cursor/commands/address_feedback.md` for full logic
- Cursor interaction modes (@new-feature, @refactor, @debug, @review) moved from arch-03 into the base template
- Setup script generates `.cursorrules` from base + blocks, same as all other agents

---

## 7. File Structure After Changes

```
standards/
├── shared/
│   ├── core-standards.md              (unchanged — human-readable canonical source)
│   └── blocks/
│       ├── architecture-core.md
│       ├── testing-policy.md
│       ├── security-summary.md
│       ├── naming-conventions.md
│       ├── git-workflow.md
│       ├── documentation-policy.md
│       ├── lang-python.md
│       ├── lang-typescript.md
│       ├── lang-javascript.md
│       ├── lang-java.md
│       ├── lang-kotlin.md
│       ├── lang-swift.md
│       ├── lang-dart.md
│       ├── lang-rust.md
│       ├── lang-zig.md
│       ├── lang-ruby.md
│       ├── lang-rails.md
│       ├── role-service.md
│       ├── role-library.md
│       ├── role-app.md
│       └── role-data-pipeline.md
├── agents/
│   ├── claude-code/
│   │   ├── base-claude-code.md        (new — replaces CLAUDE.md.template)
│   │   ├── settings.json.example      (unchanged)
│   │   └── permissions/               (unchanged)
│   ├── cursor/
│   │   └── base-cursor.md             (new)
│   ├── copilot/
│   │   └── base-copilot.md            (new — replaces .github/copilot-instructions.md)
│   ├── gemini/
│   │   └── base-gemini.md             (new — replaces GEMINI.md)
│   ├── aider/
│   │   └── base-aider.md              (new — replaces .aiderrc)
│   └── codex/
│       └── base-codex.md              (new — replaces .codexrc, AGENTS.md format)
├── architecture/
│   ├── arch-01_...md                  (gutted — 253→40 lines)
│   ├── arch-02_...md                  (unchanged)
│   ├── arch-04_...md                  (unchanged)
│   └── arch-05_...md                  (trimmed — 135→90 lines)
├── languages/                         (banned-functions lists removed, otherwise unchanged)
├── process/
│   ├── proc-01_...md                  (unchanged)
│   ├── proc-02_...md                  (aliases extracted — 487→430 lines)
│   ├── proc-03_...md                  (unchanged)
│   └── proc-04_...md                  (context handling from arch-03 merged in)
├── security/
│   └── sec-01_...md                   (unchanged)
└── README.md                          (updated to reflect new structure)
```

**Deleted:** `arch-03_cursor_automation_standards.md`
**New directory:** `standards/shared/blocks/`
**New files:** 21 block files + 6 base templates = 27 new files

---

## 8. Success Criteria

1. **Token reduction:** Assembled agent configs for a typical 2-language project are <150 lines / <600 tokens (vs. current ~1,200 lines / ~4,800 tokens potential).
2. **Self-contained:** No assembled config requires the agent to read additional files from the submodule.
3. **All 6 agents functional:** Each agent config follows current best practices for that agent's platform.
4. **Idempotent assembly:** `setup.sh` and `sync-standards.sh` produce identical results on repeated runs.
5. **Project-specific sections preserved:** Custom content survives re-assembly.
6. **Existing tests pass:** `make test-scripts` validates all shell scripts.
7. **Codex migration complete:** `.codexrc` replaced with `AGENTS.md` in this repo and in templates.
