---
name: standards-audit
description: Run standards compliance checks and report violations with severity levels
---

# Standards Audit

Run the standards compliance linter against the current project and report results inline.

## When to Use

- Before opening a PR, to catch standards violations early
- During code review, to verify compliance
- When onboarding a project to coding-standards, to identify gaps
- When a user asks "does this project follow the standards?"

## Workflow

1. Verify `.standards.yml` exists at the project root. If not, report: "No `.standards.yml` found — run the setup-wizard skill first."

2. Run the linter:

   ```bash
   .standards/scripts/lint-standards.sh --format json
   ```

   If the standards repo is installed elsewhere, adjust the path. The script auto-detects the project root via `git rev-parse --show-toplevel`.

3. Parse the JSON output. The structure is:

   ```json
   {
     "timestamp": "...",
     "projectRoot": "...",
     "summary": { "pass": N, "warn": N, "fail": N, "total": N },
     "results": [
       { "status": "PASS|WARN|FAIL", "check": "check-name", "message": "..." }
     ]
   }
   ```

4. Present results grouped by status:
   - **FAIL** items first — these are blocking violations under the standards (typically merge-blocking)
   - **WARN** items second — these are advisory/non-blocking unless the standards for this project say otherwise
   - **PASS** items last — only show count, not individual items

5. For each FAIL or WARN, include:
   - The check name (e.g., `python/banned-functions`, `common/no-secrets`)
   - The message explaining what was found
   - A remediation suggestion based on the check type

## Available Checks

Checks live in `.standards/scripts/lint-checks/` organized by category:

- `common/` — Cross-language: conventional commits, coverage config, no secrets, test directory structure
- `python/` — Banned functions, ruff config, type annotations
- `typescript/` — Banned functions, eslint config, strict tsconfig
- `go/` — Error handling, golangci config
- `elixir/` — Credo config, dialyzer config

Each check script exits 0 (PASS), 1 (FAIL), or 2 (WARN).

## Output Formats

The linter supports three formats via `--format`:

- `text` — Human-readable with color (default, best for terminal)
- `json` — Machine-readable (best for skill consumption)
- `sarif` — SARIF 2.1.0 for GitHub Code Scanning integration

## After Audit

Report a one-line summary: "Standards audit: X passed, Y warnings, Z failures out of N checks."

If there are failures, suggest specific fixes. If all checks pass, confirm the project is compliant.
