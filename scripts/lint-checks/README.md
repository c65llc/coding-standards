# Standards Compliance Checks

Modules run by [`scripts/lint-standards.sh`](../lint-standards.sh). Each module
is a small bash script that emits `PASS`/`WARN`/`FAIL` lines; the runner
aggregates them into text, JSON, or SARIF output.

## Enforced vs. standards-only

The repository ships **13 language standards** but automated compliance checks
exist for only some of them. A language having a standards document does **not**
mean the linter enforces it — the table below is the source of truth.

| Category | Machine-enforced by `lint-standards.sh`? | Checks |
| --- | --- | --- |
| Common (all repos) | ✅ | conventional-commits, coverage-config, no-secrets, test-directory-structure |
| Python (lang-01) | ✅ | banned-functions, ruff-config, type-annotations |
| TypeScript (lang-06) | ✅ | banned-functions, eslint-config, strict-tsconfig |
| Go (lang-12) | ✅ | error-handling, golangci-config |
| Elixir (lang-13) | ✅ | credo-config, dialyzer-config |
| Java, Kotlin, Swift, Dart, JavaScript, Rust, Zig, Ruby, Rails | ❌ standards-only | — |

The nine "standards-only" languages have full standards documents under
`standards/languages/` and are followed by the AI-agent configs, but there are
no automated check modules for them yet. Consumers should not assume
`lint-standards.sh` validates those languages.

## Roadmap

Per-language check modules are added incrementally. Highest-value next
candidates (by ecosystem size and tooling maturity): **JavaScript** and
**Rust**. Contributions welcome — see "Adding a check module" below.

## Adding a check module

1. Create `scripts/lint-checks/<lang-or-common>/<check-name>.sh`.
2. Emit one status line per finding: `PASS <check-name> <message>`,
   `WARN <check-name> <message>`, or `FAIL <check-name> <message>`.
3. Keep it POSIX/bash-3.2 compatible (macOS is a first-class dev platform) and
   pass `shellcheck`.
4. Wire it into the language's section of `.standards.yml` handling in
   `lint-standards.sh` if it isn't auto-discovered.
5. Update the table above and add a functional test.
