---
title: "Seven New Skills: Teaching AI Agents to Enforce Your Standards"
date: 2026-03-31
authors:
  - name: C65 LLC
---

We've added seven new skills to the Coding Standards framework. Each one teaches AI coding agents (Claude Code, Cursor, Copilot, and others) how to enforce a specific aspect of your standards — from security scanning to coverage thresholds to dependency age gates.

## What Are Skills?

Skills are markdown files that describe a workflow an AI agent should follow. They live in `standards/agents/claude-code/skills/` and contain structured instructions: when to trigger, what to check, how to report results. Think of them as runbooks that your AI assistant can execute on demand.

Unlike static linter rules, skills can reason about context. They can ask clarifying questions, combine multiple checks, and explain *why* something is a violation — not just that it is one.

## The New Skills

### 1. Standards Audit

**Skill:** `standards-audit` | **Issue:** [#49](https://github.com/c65llc/coding-standards/issues/49)

Wraps the existing `lint-standards.sh` compliance linter. Runs all applicable check modules for your detected languages, parses the structured JSON output, and reports violations grouped by severity (FAIL, WARN, PASS). This is the broadest skill — it covers everything from conventional commits to banned functions to test directory structure.

```
Standards audit: 14 passed, 2 warnings, 1 failure out of 17 checks.
```

### 2. Security Gate

**Skill:** `security-gate` | **Issue:** [#50](https://github.com/c65llc/coding-standards/issues/50)

Scans your codebase for P0 and P1 security violations from `sec-01`. Detects banned functions (`eval()`, `exec()`, `pickle.loads()`, etc.) per language, finds XSS patterns (`innerHTML`, `dangerouslySetInnerHTML`), flags hardcoded secrets, and checks for weak randomness. P0 and P1 findings are merge-blocking — the skill clearly states that the PR should not merge until they're fixed.

### 3. Dependency Age Gate

**Skill:** `dependency-age-gate` | **Issue:** [#51](https://github.com/c65llc/coding-standards/issues/51)

Born from the [axios supply chain attack](/blog/dependency-age-gate/) — this skill verifies that every dependency version in your lockfile was published at least 72 hours ago. It queries registry APIs (npm, PyPI, crates.io, RubyGems, Maven Central, pub.dev) for publish timestamps and flags anything too fresh. Includes the exception process for emergency security patches.

### 4. Config Assembly

**Skill:** `config-assembly` | **Issue:** [#52](https://github.com/c65llc/coding-standards/issues/52)

Drives the block composition system. Reads your `.standards.yml`, assembles agent configs from content blocks (architecture, testing, security, naming, language-specific, role-specific), and writes them to the correct output files. Respects the checksum system — customized files aren't overwritten, they're written to `.standards-pending/` for the merge-standards skill to resolve.

### 5. Setup Wizard

**Skill:** `setup-wizard` | **Issue:** [#53](https://github.com/c65llc/coding-standards/issues/53)

Guided onboarding for new projects. Detects languages from manifest files, asks about project role and desired agents, generates a `.standards.yml`, runs setup with dry-run preview, and finishes with a health check. Turns a multi-step manual process into a conversation.

### 6. Coverage Enforcer

**Skill:** `coverage-enforcer` | **Issue:** [#54](https://github.com/c65llc/coding-standards/issues/54)

Enforces the layer-specific test coverage thresholds from the standards: 100% for domain/core, 95%+ for application and infrastructure, 95% minimum overall. Knows which coverage tool to use per language (coverage.py, c8, simplecov, tarpaulin, JaCoCo) and can break down coverage by architecture layer. Also checks test naming conventions and file mirroring.

### 7. Naming Convention

**Skill:** `naming-convention` | **Issue:** [#55](https://github.com/c65llc/coding-standards/issues/55)

Lints identifiers against the language-specific naming rules: `snake_case` for Python, `camelCase` for JavaScript, `PascalCase` for Go exports, `?` predicates for Ruby, and so on across all 13 supported languages. Uses grep patterns for quick scans and delegates to language-specific linters (ruff, eslint, rubocop, clippy) for deeper analysis.

## Existing Skill: Merge Standards

The previously released `merge-standards` skill ([#56](https://github.com/c65llc/coding-standards/issues/56)) already handles the pending merge workflow — intelligently merging upstream standards updates into customized agent configs while preserving project-specific content.

## How They Work Together

The skills form a pipeline that covers the full lifecycle:

1. **setup-wizard** onboards the project
2. **config-assembly** generates agent configs
3. **standards-audit** checks overall compliance
4. **security-gate** enforces P0/P1 rules
5. **dependency-age-gate** validates supply chain safety
6. **coverage-enforcer** verifies test coverage by layer
7. **naming-convention** catches identifier inconsistencies
8. **merge-standards** keeps configs current as standards evolve

Each skill is self-contained — use any one independently or chain them in CI.

## Try It

Update your standards submodule:

```bash
make sync-standards
```

The new skills are available immediately to any agent with access to the `.standards/` directory. In Claude Code, reference them by name — for example, "run the standards-audit skill" or "check the dependency age gate."

See all skills in [`standards/agents/claude-code/skills/`](/standards/agents/claude-code/).
