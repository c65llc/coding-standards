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
| Swift (lang-04) | ✅ | swift-format-config, package-resolved, warnings-as-errors |
| TypeScript (lang-06) | ✅ | banned-functions, eslint-config, strict-tsconfig |
| Rust (lang-08) | ✅ | clippy-ci, deny-config, toolchain-pin, ffi-no-unwrap |
| Go (lang-12) | ✅ | error-handling, golangci-config |
| Elixir (lang-13) | ✅ | credo-config, dialyzer-config |
| Java, Kotlin, Dart, JavaScript, Zig, Ruby, Rails | ❌ standards-only | — |

The seven "standards-only" languages have full standards documents under
`standards/languages/` and are followed by the AI-agent configs, but there are
no automated check modules for them yet. Consumers should not assume
`lint-standards.sh` validates those languages.

### What each language module verifies

| Check | Severity model |
| --- | --- |
| `rust/clippy-ci` | PASS when a CI step runs `cargo clippy … -D warnings` (or `RUSTFLAGS=-D warnings`); WARN when clippy runs without `-D warnings`; FAIL when no CI step runs clippy |
| `rust/deny-config` | PASS when `deny.toml` has a non-empty `[licenses] allow` list; WARN when the file exists without one; FAIL when missing |
| `rust/toolchain-pin` | PASS when `rust-toolchain.toml`, `Cargo.toml rust-version`, and CI toolchain pins agree; FAIL when CI pins a different version or `rust-version` is newer than the toolchain; WARN when the toolchain file is missing/floating or `rust-version` trails it |
| `rust/ffi-no-unwrap` | PASS when `ffi.rs`/`wasm.rs`/`*_ffi.rs`/`*_wasm.rs`/`ffi/`/`wasm/` contain no `unwrap`/`expect`/`panic!`-family calls (or none exist); FAIL otherwise, naming each file |
| `swift/swift-format-config` | PASS when `.swift-format` exists; WARN when only `.swiftlint.yml`/`.swiftformat` exists; FAIL when no formatter config |
| `swift/package-resolved` | PASS when `Package.resolved` is committed (or the package has no dependencies); FAIL when dependencies exist but the lockfile is missing, untracked, or gitignored; WARN when there is no `Package.swift` |
| `swift/warnings-as-errors` | PASS when CI, `Package.swift`, `project.yml`, an `.xcconfig`, or a build script enables `-warnings-as-errors` / `SWIFT_TREAT_WARNINGS_AS_ERRORS` / `treatAllWarnings(as: .error)`; FAIL otherwise |

## Roadmap

Per-language check modules are added incrementally. Rust and Swift landed in
1.6 (issue #193). Highest-value next candidates (by ecosystem size and tooling
maturity): **JavaScript** (eslint/prettier config, banned functions, shared
with the TypeScript modules) and **Kotlin** (ktlint/detekt config). Contributions
welcome — see "Adding a check module" below.

## Adding a check module

1. Create `scripts/lint-checks/<lang-or-common>/<check-name>.sh`.
2. Emit one status line per finding: `PASS <check-name> <message>`,
   `WARN <check-name> <message>`, or `FAIL <check-name> <message>`.
3. Keep it POSIX/bash-3.2 compatible (macOS is a first-class dev platform) and
   pass `shellcheck`.
4. Language directories are auto-discovered: `lint-standards.sh` runs every
   `*.sh` under `lint-checks/<lang>/` when `<lang>` appears in the project's
   `.standards.yml` `languages:` list. Only the `common/` set needs no opt-in.
5. Update the table above and add a functional test in
   `scripts/test-lint-standards.sh` (one PASS fixture and one FAIL/WARN fixture
   per module, plus a runner-wiring assertion for a new language directory).
