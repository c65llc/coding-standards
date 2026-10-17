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
| Common (all repos) | ✅ | ci-workflow-hygiene, conventional-commits, coverage-config, headless-ci, no-secrets, quarantine-policy, test-directory-structure |
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
| `rust/clippy-ci` | PASS when a CI step runs `cargo clippy … -D warnings` (or `RUSTFLAGS=-D warnings`), directly or via a `Makefile`/`justfile` that CI invokes; WARN when clippy runs without `-D warnings`; FAIL when no CI definition exists or no CI step runs clippy |
| `rust/deny-config` | PASS when `deny.toml` has a non-empty `[licenses] allow` list (double- or single-quoted TOML strings); WARN when the file exists without one; FAIL when missing |
| `rust/toolchain-pin` | PASS when `rust-toolchain.toml`, `Cargo.toml rust-version`, and CI toolchain pins agree; FAIL when CI pins a different version or `rust-version` is newer than the toolchain; WARN when the toolchain file is missing, floats (`stable`, or `1.99` without a patch component), or `rust-version` trails it. Reads GitHub, GitLab, CircleCI, and Buildkite definitions |
| `rust/ffi-no-unwrap` | PASS when `ffi.rs`/`wasm.rs`/`*_ffi.rs`/`*_wasm.rs`/`ffi/`/`wasm/` contain no `unwrap`/`expect`/`panic!`-family calls (or none exist); FAIL otherwise, naming each file |
| `swift/swift-format-config` | PASS when `.swift-format` exists (or `.swift-format.json` is passed via `--configuration` in CI); WARN when only `.swift-format.json`, `.swiftlint.yml`, or `.swiftformat` exists; FAIL when no formatter config |
| `swift/package-resolved` | PASS when `Package.resolved` is committed (or the package has no dependencies); FAIL when an executable target or a CI definition exists and the lockfile is missing, or when it is untracked or gitignored; WARN for a dependency-only library with no CI build (lang-04 §1 lets it omit the lockfile) or when there is no `Package.swift` |
| `swift/warnings-as-errors` | PASS when CI, `Package.swift`, `project.yml`, an `.xcconfig`, or a build script enables `-warnings-as-errors` / `SWIFT_TREAT_WARNINGS_AS_ERRORS` / `treatAllWarnings(as: .error)`; FAIL otherwise |

### Common checks

| Check | Standard | What it looks at | Severity on finding |
| --- | --- | --- | --- |
| `conventional-commits` | proc-02 | Recent commit subjects match `type(scope): subject` | WARN/FAIL |
| `coverage-config` | core-standards, proc-05 § 6 | A coverage gate exists in CI, test config, or `.standards.yml`; `coverage.scopes` entries have a path, an integer floor, 100% for domain/core, and a stated `reason` for any lowered scope | FAIL |
| `no-secrets` | sec-01 | AWS keys, private-key blocks, hardcoded passwords/tokens in source | FAIL |
| `quarantine-policy` | proc-05 § 2 | The flaky-test quarantine registry is valid JSON whose every `entries` element is a complete entry: non-blank required fields, exact unique test ids, real ISO dates, `added` not in the future, ≤ 30-day windows, no past-due entries, and no coverage overrides; fails closed when a declared registry is missing, empty, or not valid JSON | WARN/FAIL |
| `test-directory-structure` | core-standards | A recognizable test directory exists | WARN/FAIL |
| `ci-workflow-hygiene` | arch-08 §3 | Every `pull_request` workflow declares `concurrency` + `cancel-in-progress` (workflow-level or on every job), `timeout-minutes` on each job that runs steps, and path scoping (`paths:` on the PR trigger, a paths-filter + gate job, or `# ci-hygiene: paths-exempt <reason>`) | WARN |
| `headless-ci` | arch-08 §6 | Workflows and composite actions free of `store-credentials`, `unlock-keychain … login`, `osascript`, `open -a` (steps that need an unlocked desktop) | WARN |

## Module options

### conventional-commits

Checks recent history for `<type>(<scope>): <subject>` subjects. Merge
commits, `fixup!`/`squash!`/`amend!` prefixes and `git revert` subjects are
exempt. Violations up to max(3, 10% of the range) are a `WARN`; more than that is
a `FAIL` (the floor of 3 keeps a short PR range from failing on one straggler).

| Setting | Where | Effect |
| --- | --- | --- |
| `--window <n>` / `commits.window` | flag / `.standards.yml` | Inspect the last *n* non-merge commits (default **50**) |
| `--since <ref>` / `commits.since` | flag / `.standards.yml` | Inspect `<ref>..HEAD` instead of a window (wins over `window`); an unknown ref is a `WARN` |
| `STANDARDS_COMMITS_SINCE` | env | Range used when `commits.since` is unset; beats `commits.window` so the standards-review action (which sets it to `origin/<pr-base>`) always judges a PR on its own commits |
| `commits.scopes` | `.standards.yml` | Allow-list; scoped commits must use a listed scope (unscoped commits pass). Inline `[a, b]` and block lists both work |

```yaml
# .standards.yml
commits:
  window: 50
  # since: origin/main
  scopes: [api, domain, ui]
```

Precedence: flags > `commits.since` > `STANDARDS_COMMITS_SINCE` > `commits.window` > default
(a range from any source beats a window).

The same type list, regex and allow-list parser live in
`scripts/lib/conventional-commits.sh` and back `scripts/check-commit-message.sh`
(commit-msg hooks via `templates/husky-commit-msg.example` /
`templates/lefthook.yml.example`, and the PR-title step of the
standards-review action).

## File enumeration and exclusions

Checks that scan file contents (`no-secrets`, `python/banned-functions`,
`typescript/banned-functions`, `go/error-handling`, `rust/ffi-no-unwrap`) do
not walk the tree with `find`. They source
[`scripts/lib/lint-files.sh`](../lib/lint-files.sh), which enumerates
candidates in this order:

1. **Tracked files** — `git ls-files -z`, or, under `--since` / `--changed`,
   the runner's list of tracked files changed since the merge-base (see
   below).
2. **Untracked, not-ignored files** — `git ls-files -z -o --exclude-standard`.
   `.gitignore` is honoured, so build output and caches are never read, and
   nested worktrees (`.claude/worktrees/*`, `.worktrees/*`) are never
   descended into. Untracked files are enumerated even in `--since` mode, so
   a new, uncommitted file is still scanned.
3. **Pruned `find -print0`** — only when the project is not a git repository.
   The built-in exclusions below are `-prune`d, so excluded trees are not
   walked.

After enumeration the list is filtered by:

- **Built-in directory exclusions** (any depth): `.git`, `node_modules`,
  `.standards`, `.standards_tmp`, `vendor`, `third_party`, `dist`, `build`,
  `.build`, `target`, `.next`, `__pycache__`, `.venv`, `venv`, `.tox`,
  `coverage`, `.pnpm-store`, `.wrangler`, `DerivedData`, `.worktrees`,
  `.claude/worktrees`, `.Codex/worktrees`, `.workspaces`.
- **`lint.exclude` in `.standards.yml`** — project-relative path prefixes or
  shell-style globs (`*` within a segment, `**` any run of characters,
  `**/` zero or more whole segments, so `**/*.py` also matches a top-level
  `app.py`):

  ```yaml
  lint:
    exclude:
      - docs/              # whole directory
      - skills/smoke.sh    # single file
      - fixtures/**        # glob
      - "gen#tmp/"         # quote a value that contains "#"
  ```

  A `#` starts a comment only at the start of a value or after whitespace
  (YAML's rule), so a quoted or unspaced `#` is part of the path. Backslashes
  are literal. An entry that still yields an invalid pattern is ignored with
  a note on stderr rather than emptying the scan — scanning too much is the
  safe failure.

- **Per-check defaults** — both `banned-functions` checks skip the top-level
  `docs/` directory (wireframes and mockups are not shipped code).
- **Regular files only** — a tracked symlink is never followed (its target may
  lie outside the project, or be a FIFO that would block the scan), and a
  tracked path deleted from the working tree is dropped.

**`no-secrets` is strict.** It applies neither `lint.exclude` nor the built-in
directory exclusions to *tracked* files: a committed secret under `vendor/`,
`docs/`, or a path a PR adds to `lint.exclude` is still reported, so the
exclude list cannot be used to smuggle a secret past CI. Built-in exclusions
still drop *untracked* worktrees and caches, which never reach CI. If a
tracked file is a legitimate false positive, fix the content (the password /
API-key patterns already skip `test`, `spec`, `fixture`, `example`, `sample`,
`mock`, `dummy` and `placeholder` paths) rather than excluding the path.

**Path safety.** Enumeration is NUL-delimited end to end (`git -z`,
`find -print0`, `xargs -0`), so names with spaces, quotes, `#` or `:` are
passed to grep exactly. A filename that contains a newline cannot be carried
by a line-oriented list; such files are not skipped silently — every
file-scanning check reports them as `N file(s) not scanned (newline in
filename)`, after the same exclusion policy as ordinary candidates, so a
name under an excluded path is not reported. Comment suppression in the `banned-functions` checks is anchored
on a per-file `<line>:` prefix (two-stage grep: `grep -l --null` to find the
files, then `grep -n` per matching file), so neither a filename containing
`:1:#` nor a trailing `# :1: #` on the offending line can forge a
suppression.

Matches are grepped in batches, skip binaries, and report project-relative
`path:line:` locations.

`test-directory-structure` compares directory names exactly: `Tests/` does
not satisfy `tests/`, even on a case-insensitive filesystem, so a project that
passes on macOS also passes on Linux CI.

### Runner flags for PR runs

| Flag | Effect |
| --- | --- |
| `--since <ref>` | File-scanning checks only look at files changed since the merge-base with `<ref>` (added, copied, modified, renamed or type-changed — e.g. a symlink replaced by a real file — committed, staged or unstaged) plus untracked files. Paths are relative to the project root (`git diff --relative`), so a root that is a subdirectory of a larger work tree is scoped correctly. Config/history checks still run on the whole project. |
| `--changed` | `--since` with the base auto-detected (`origin/HEAD`, `origin/main`, `origin/master`, `main`, `master`); falls back to a full scan with a note on stderr. |
| `--timeout <secs>` | Wall-clock guard per check module (default 60, `0` disables, env `LINT_CHECK_TIMEOUT`). A check that overruns is sent `SIGTERM`, then `SIGKILL` after a 2 s grace period (so a module that traps the signal cannot hang the run), and reported as `WARN` — except `no-secrets` and `*/banned-functions`, which are always reported as `FAIL`: an incomplete security scan must not pass a gate. |
| `--fail-on-timeout` | Report *every* timed-out check as `FAIL` (env `LINT_FAIL_ON_TIMEOUT=1`). The `standards-review` action sets this by default so CI never fails open. |

The `standards-review` composite action exposes these as the `changed-only`,
`timeout` and `fail-on-timeout` inputs. If the linter aborts before producing
JSON (for example an invalid `timeout` value), the action reports a failure
rather than an empty, passing result.

## Roadmap

Per-language check modules are added incrementally. Rust and Swift landed in
1.6 (issue #193). Highest-value next candidates (by ecosystem size and tooling
maturity): **JavaScript** (eslint/prettier config, banned functions, shared
with the TypeScript modules) and **Kotlin** (ktlint/detekt config). Contributions
welcome — see "Adding a check module" below.

## Writing a gate

These modules are gates: a `PASS` from one of them is treated as evidence that a
rule holds. Three gates on a consumer project once reported clean without ever
running — an empty scan, a rotted regex, and an unowned skip marker. Every module
in this directory therefore follows the rules in
[`proc-05_test_governance.md` § 7](../../standards/process/proc-05_test_governance.md#7-writing-a-gate):

1. **Self-test on every run.** Before touching the project, run the detector
   against a built-in fixture that MUST trip it (and, where cheap, one that must
   not). If the fixture result is wrong, emit
   `FAIL <check-name> self-test failed (detector rot, refusing to report): <why>`
   and exit 1. A rotted detector must never print a clean result. (The runner
   reserves exit 2 for `WARN`, so rot is signalled as `FAIL` with the
   `self-test` message rather than a separate exit code; the message text is
   what distinguishes it in JSON/SARIF output.)
   See `quarantine-policy.sh` and `coverage-config.sh` for the pattern.
2. **Fail closed on an empty scan.** If the module scans a path set and the set
   is empty, or a declared input file is missing or unreadable, emit `FAIL` with
   a message naming what was expected. An empty match is a configuration error,
   not a clean result. A module whose domain is legitimately optional says so
   in its `PASS` line (for example `No quarantine registry (none declared) —
   nothing quarantined`) so a reader can tell "nothing to check" from "checked
   and clean".
3. **Escape markers state a reason.** If a module honors an inline suppression
   (an allowlist file, a `# standards: allow-<rule>` comment), it MUST require a
   reason on the same line and reject a bare marker.
4. **Never report an unrun check as passing.** If a required tool is missing or
   the module cannot run, emit `WARN`/`FAIL` with the reason. Do not fall
   through to `PASS`.
5. **Deterministic across hosts.** The verdict must not depend on optional tools
   (python3, node, GNU vs BSD `date`). Use bash 3.2 + POSIX `awk`/`sed`/`tr`
   only, so macOS and Linux agree.
6. **One line of output.** The runner reads the first token as the status and
   the rest as the message; put details after the check name on the same line
   and cap the list (first four problems, then `(+N more)`).

## Adding a check module

1. Create `scripts/lint-checks/<lang-or-common>/<check-name>.sh` (`chmod +x`).
2. Emit one status line per finding: `PASS <check-name> <message>`,
   `WARN <check-name> <message>`, or `FAIL <check-name> <message>`.
   Exit 0 for PASS, 1 for FAIL, 2 for WARN, and document that in the header.
3. Keep it POSIX/bash-3.2 compatible (macOS is a first-class dev platform) and
   pass `shellcheck -x --severity=warning`. If the check reads file contents,
   enumerate them with `lint_list_files` from `scripts/lib/lint-files.sh`
   rather than `find`, so `.gitignore`, worktrees, `lint.exclude` and the
   runner's `--since` scope are honoured consistently.
4. Follow **Writing a gate** above: self-test fixture, fail closed, no silent
   skips.
5. Language directories are auto-discovered: `lint-standards.sh` runs every
   `*.sh` under `lint-checks/<lang>/` when `<lang>` appears in the project's
   `.standards.yml` `languages:` list. Only the `common/` set needs no opt-in.
6. Add functional tests to [`scripts/test-lint-standards.sh`](../test-lint-standards.sh):
   at least one fixture that trips the check and one clean fixture that passes
   (plus a runner-wiring assertion for a new language directory). Write the
   failing test first.
7. Update the tables above and, if the check enforces a standard, the
   "Enforcement" note in that standard.
