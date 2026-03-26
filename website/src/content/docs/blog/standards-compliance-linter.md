---
title: "Standards Compliance Linter: Enforce Your Standards in CI"
date: 2026-03-25
authors:
  - name: C65 LLC
---

Phase 2 of the standards tooling roadmap ships `make lint-standards` — a multi-language compliance linter that checks your project against coding standards and reports results in text, JSON, or SARIF format for GitHub Code Scanning integration.

## What it checks

The linter is organized into two tiers: common checks that run on every project, and language-specific checks that activate based on your `.standards.yml` configuration.

### Common checks (all projects)

| Check | What it verifies |
|-------|-----------------|
| `conventional-commits` | Last 10 git commits match `type(scope): subject` pattern |
| `test-directory` | A `tests/`, `test/`, `spec/`, or `__tests__/` directory exists and is non-empty |
| `no-secrets` | No AWS keys, private key blocks, or hardcoded passwords/API keys in source files |
| `coverage-config` | CI workflows, jest config, pytest config, or `.standards.yml` declare a coverage threshold |

### Python checks

| Check | What it verifies |
|-------|-----------------|
| `python/type-annotations` | mypy is configured; WARN if not in strict mode, FAIL if not configured at all |
| `python/banned-functions` | No `eval()`, `exec()`, `pickle.loads()`, `os.system()`, or `subprocess` with `shell=True` |
| `python/ruff-config` | `ruff.toml`, `.ruff.toml`, or `[tool.ruff]` in `pyproject.toml` |

### TypeScript / JavaScript checks

| Check | What it verifies |
|-------|-----------------|
| `typescript/strict-tsconfig` | `"strict": true` in `tsconfig.json` |
| `typescript/banned-functions` | No `eval()`, `new Function()`, `.innerHTML =`, `document.write()`, or `setTimeout` with string literal |
| `typescript/eslint-config` | An `.eslintrc*`, `eslint.config.*`, or `eslintConfig` in `package.json` |

### Go checks

| Check | What it verifies |
|-------|-----------------|
| `go/golangci-config` | `.golangci.yml`, `.golangci.yaml`, or `.golangci.toml` present |
| `go/error-handling` | No bare `_ =` or `, _ :=` patterns that discard return values (likely errors) |

### Elixir checks

| Check | What it verifies |
|-------|-----------------|
| `elixir/credo-config` | `:credo` in `mix.exs` dependencies |
| `elixir/dialyzer-config` | `:dialyxir` in `mix.exs` dependencies |

## Plugin architecture

Each check is a standalone bash script in `scripts/lint-checks/<language>/`. The interface is minimal: receive the project root as `$1`, print one line (`PASS|WARN|FAIL <check-name> <message>`), exit with `0`, `1`, or `2`. Adding a new check is as simple as dropping a new script in the right directory — the orchestrator discovers it automatically.

The orchestrator (`scripts/lint-standards.sh`) reads `.standards.yml` to determine which language-specific check directories to activate. Common checks always run.

## Output formats

### Text (default)

```
🔎 Standards Compliance Check
═══════════════════════════════════════

  ✅ PASS  conventional-commits    All recent commits follow Conventional Commits format
  ⚠️  WARN  test-directory         Test directory found but appears empty
  ✅ PASS  no-secrets              No hardcoded secrets detected
  ✅ PASS  coverage-config         Coverage gate found in .standards.yml (minimum: 95%)
  ✅ PASS  python/type-annotations mypy strict mode enabled in pyproject.toml
  ❌ FAIL  python/banned-functions eval() at src/utils.py:42
  ✅ PASS  python/ruff-config      [tool.ruff] section configured in pyproject.toml

═══════════════════════════════════════
  Results: 5 pass, 1 warn, 1 fail
```

### JSON

```bash
./scripts/lint-standards.sh --format json
```

Produces a structured JSON object with `summary` counts and a `results` array — suitable for parsing in scripts, dashboards, or custom reporters.

### SARIF (GitHub Code Scanning)

```bash
./scripts/lint-standards.sh --format sarif > results.sarif
```

SARIF 2.1.0 output maps WARN to `warning` and FAIL to `error`. Upload to GitHub Code Scanning to get inline annotations on pull requests:

```yaml
- name: Run standards linter
  run: ./scripts/lint-standards.sh --format sarif > standards.sarif || true

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: standards.sarif
```

## How to run

```bash
make lint-standards
```

Or directly with a format flag:

```bash
./scripts/lint-standards.sh --format json
./scripts/lint-standards.sh --format sarif
```

The linter exits with code `1` if any checks fail, making it CI-friendly as a blocking gate.

## Adding your own checks

Drop a new executable `*.sh` script in `scripts/lint-checks/common/` or `scripts/lint-checks/<language>/`. Follow the one-line output contract and the orchestrator picks it up automatically on the next run. Run `make test-scripts` to validate syntax before committing.
