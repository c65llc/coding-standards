TDD is mandatory. Red → Green → Refactor. Write failing tests before implementation code.
Coverage enforced in CI — blocks merge if violated:

- Domain / Core: 100%
- Application / Shell: 95%+
- Infrastructure: 95%+

Every bug fix must include a regression test.
Flaky tests go in the committed quarantine registry (`test-quarantine.json`: exact test id, issue, owner, reason, `expires` ≤ 30 days) — never retry, skip, or disable a test in place; expired entries fail CI; quarantine never lowers a coverage floor. Scoped floors live in `.standards.yml` `coverage.scopes` (domain/core stay 100%; a lowered scope needs a stated reason).
Before pushing, run the checks `ci-routing.yml` selects for your changed paths (unmatched paths = full suite) and report them in the PR evidence table with the tested commit SHA. Never report an unrun check as passing. E2E lanes never target production. Full rules: `proc-05_test_governance.md`.
Meet coverage with real tests — never add dead/unreachable branches to hit a number. For genuinely untestable boundaries (real filesystem/keychain/native APIs), keep the boundary thin, push logic into pure testable units, and flag the residual manual-verification step explicitly.
Run the full build, not just a typecheck or syntax pass — a narrow typecheck config often excludes test files and sub-projects that the full build compiles, so the build catches errors typecheck misses. The language block names the exact build command.
Mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
Use descriptive test names: `test_should_raise_error_when_email_is_invalid`
Visual/snapshot baselines: regenerate via a CI dispatch job, never commit from a local run — rendered pixels are environment-specific and local baselines drift from CI.
