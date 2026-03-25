---
title: "Declarative Config and make doctor: Phase 1 of Standards Tooling"
date: 2026-03-25
authors:
  - name: C65 LLC
---

Two new additions land in Phase 1 of our standards tooling roadmap: `.standards.yml` — a declarative configuration file that replaces the old shell-variable-based approach — and `make doctor`, a health check command that audits your project's standards setup and tells you exactly what to fix.

## .standards.yml: Declarative Standards Configuration

Previously, consumer projects configured standards through a `.standards-config` file using `KEY=value` shell variables. It worked, but it was limited: no schema, no version field, no way to express nested settings like coverage thresholds.

`.standards.yml` replaces that with a proper YAML config:

```yaml
# .standards.yml — Project standards configuration
version: 1

languages:
  - python
  - typescript

agents:
  - claude-code
  - cursor
  - copilot

role: service

coverage:
  minimum: 95
  domain: 100

architecture: clean
security: strict
```

### What each field controls

| Field | Purpose |
|-------|---------|
| `version` | Config schema version — enables forward-compatible migrations |
| `languages` | Which language standards to load during assembly |
| `agents` | Which AI agents get config files during setup and sync |
| `role` | Project type — `service`, `library`, `app`, or `data-pipeline` |
| `coverage.minimum` | Overall test coverage floor (%) |
| `coverage.domain` | Domain-layer coverage requirement (%) |
| `architecture` | `clean` enforces Clean Architecture; `none` removes constraints |
| `security` | `strict` makes P0/P1 merge-blocking; `moderate` warns on P1 |

The `setup.sh` script generates `.standards.yml` automatically during installation using language detection. You can edit it afterward to adjust agents, coverage thresholds, or architecture mode. `sync-standards.sh` reads it on every run to assemble only the configs you need.

The legacy `.standards-config` format remains supported for backward compatibility — `make doctor` will warn you if you're on the old format.

## make doctor: Standards Health Check

`make doctor` runs a seven-point audit of your project's standards setup and produces a scored report:

```
Standards Health Check
=======================================

  ✅ PASS  Configuration          .standards.yml found (version 1)
  ✅ PASS  Claude Code            CLAUDE.md present
  ✅ PASS  Cursor                 .cursorrules present
  ⚠️  WARN  Copilot               .github/copilot-instructions.md missing
  ✅ PASS  Checksums              All config checksums match
  ⚠️  WARN  Languages             Detected 'go' not in .standards.yml
  ✅ PASS  Submodule              .standards/ is a valid git repo
  ❌ FAIL  Git Hooks              post-merge hook not installed
  ✅ PASS  Gitignore              All required entries present

=======================================
  Score: 6/9 (67%)

  Fixes needed:
    -> Run: make setup-agents  (to install missing Copilot config)
    -> Add: 'go' to .standards.yml languages list
    -> Run: make setup  (to install git hooks for automatic standards sync)
```

### What it checks

1. **Configuration** — `.standards.yml` exists (or legacy `.standards-config`)
2. **Agent files** — each agent declared in config has its expected file on disk
3. **Checksums** — `.standards-checksums` exists and config hashes match stored values, detecting unauthorized edits
4. **Languages** — runs `detect-languages.sh` and compares against declared languages, flagging gaps
5. **Submodule** — `.standards/` is a valid initialized git repo (skipped when running in the standards repo itself)
6. **Git hooks** — `.git/hooks/post-merge` exists and references standards sync
7. **Gitignore** — `.gitignore` contains `.standards-pending/` and `*.pre-standards-setup`

Every warning and failure includes a concrete fix command so you know exactly what to run.

## Try It

Update your standards submodule and run the health check:

```bash
cd .standards && git pull origin main && cd ..
make doctor
```

If you haven't installed standards yet:

```bash
curl -fsSL https://raw.githubusercontent.com/c65llc/coding-standards/main/install.sh | bash
make doctor
```

A perfect score means your project is fully configured, checksums are clean, and automatic sync is in place via git hooks.
