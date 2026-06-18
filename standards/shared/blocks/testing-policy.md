TDD is mandatory. Red → Green → Refactor. Write failing tests before implementation code.
Coverage enforced in CI — blocks merge if violated:

- Domain / Core: 100%
- Application / Shell: 95%+
- Infrastructure: 95%+

Every bug fix must include a regression test.
Meet coverage with real tests — never add dead/unreachable branches to hit a number. For genuinely untestable boundaries (real filesystem/keychain/native APIs), keep the boundary thin, push logic into pure testable units, and flag the residual manual-verification step explicitly.
Run the build (e.g. `tsc -b`), not just typecheck — a narrow typecheck config often excludes test files and the project references that the full build compiles, so the build catches errors typecheck misses.
Mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
Use descriptive test names: `test_should_raise_error_when_email_is_invalid`
