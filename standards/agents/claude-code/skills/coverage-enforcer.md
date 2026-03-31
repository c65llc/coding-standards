---
name: coverage-enforcer
description: Enforce layer-specific test coverage thresholds from standards
---

# Coverage Enforcer

Verify that the project meets the test coverage thresholds defined in the standards, broken down by architecture layer.

## When to Use

- After running tests, to verify coverage meets thresholds
- Before opening a PR, to catch coverage regressions
- When a user asks "does this meet our coverage requirements?"
- During code review of changes that reduce coverage

## Coverage Thresholds

From `standards/shared/blocks/testing-policy.md` and `.standards.yml`:

| Layer | Default Threshold | Rationale |
|-------|------------------|-----------|
| Domain/Core | 100% | Business logic must be fully tested |
| Application/Shell | 95%+ | Orchestration layer, high confidence required |
| Infrastructure | 95%+ | Integration points, high confidence required |
| Overall minimum | 80% | Floor for project-wide coverage |

The `.standards.yml` can override these:

```yaml
coverage:
  minimum: 80    # project-wide floor
  domain: 100    # domain layer target
```

## Workflow

1. Read `.standards.yml` to get coverage thresholds. Fall back to defaults if not specified.

2. Identify the coverage tool for each detected language:

   | Language | Coverage Tool | Report Format |
   |----------|--------------|---------------|
   | Python | `coverage.py` / `pytest-cov` | `.coverage`, `coverage.xml` |
   | JavaScript/TypeScript | `c8` / `istanbul` / `vitest` | `coverage/lcov.info`, `coverage/coverage-summary.json` |
   | Ruby | `simplecov` | `coverage/.last_run.json`, `coverage/.resultset.json` |
   | Rust | `cargo-tarpaulin` / `cargo-llvm-cov` | `tarpaulin-report.json`, `lcov.info` |
   | Go | `go test -coverprofile` | `coverage.out` |
   | Elixir | `mix test --cover` | `cover/` |
   | Java/Kotlin | `JaCoCo` | `build/reports/jacoco/test/jacocoTestReport.xml` |

3. Run the test suite with coverage if no recent report exists:

   ```bash
   # Python
   uv run pytest --cov=src --cov-report=json

   # JavaScript/TypeScript
   pnpm test -- --coverage

   # Ruby
   bundle exec rspec  # (simplecov runs automatically if configured)

   # Rust
   cargo tarpaulin --out json
   ```

4. Parse the coverage report. If the tool supports per-directory breakdown, calculate coverage by architecture layer:
   - **Domain**: `src/domain/`, `src/core/`, `lib/domain/`
   - **Application**: `src/app/`, `src/application/`, `src/use_cases/`
   - **Infrastructure**: `src/infra/`, `src/infrastructure/`, `src/adapters/`

5. Compare each layer's coverage against its threshold. Report:
   - **PASS**: Layer meets or exceeds threshold
   - **FAIL**: Layer is below threshold — include actual vs. required percentage

## Test Convention Checks

Also verify:
- Test files mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
- Test names are descriptive: `test_should_raise_error_when_email_is_invalid`
- Every bug fix PR includes a regression test

## After Check

Report: "Coverage: domain X% (target 100%), application Y% (target 95%), infrastructure Z% (target 95%), overall W% (minimum 80%). N layers passing, M failing."
