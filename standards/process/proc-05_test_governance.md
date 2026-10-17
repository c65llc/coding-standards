# Test Governance Standards

**Governing principle: a check is a gate only if it cannot pass without running, and a test suite is an asset only while it stays fast, honest, and bounded.**

Flaky tests, slow suites, and "green" checks that never executed are the three ways a test suite stops protecting a codebase while still looking like it does. This standard defines the controls that keep the suite trustworthy: a bounded quarantine for flaky tests, flake reporting that does not gate, fast/slow tiers with budgets, change-scoped suites, scoped coverage floors, rules for writing gates that fail closed, PR evidence that names what actually ran, and end-to-end lanes that can never reach production.

It extends the Testing Standards in [`core-standards.md`](../shared/core-standards.md) (TDD, 95%/100% coverage floors, regression tests). Nothing here lowers those floors.

## 1. Scope and Definitions

| Term | Meaning |
|------|---------|
| **Flaky test** | A test that passes and fails on the same commit without a code change. |
| **Quarantine** | Removing a flaky test from the merge gate, for a bounded time, while it is fixed. Quarantined tests still run. |
| **Fast tier** | Tests that run on every PR and finish within the fast budget (default: whole tier under 10 minutes, each test under `tests.slow_threshold_ms`). |
| **Slow tier** | Tests above the per-test threshold or needing heavy fixtures (containers, browsers, devices). Run on a schedule, on `main`, or when the routing table selects them. |
| **Gate** | Any check whose result blocks a merge or release. |
| **Lane** | A CI job or local target that runs one tier or one surface (for example `e2e-web`, `e2e-ios`, `e2e-cleanup`). |

Applies to every project consuming these standards, in every language. Language standards (`lang-XX`) name the concrete tools; this document names the rules the tools must implement.

## 2. Flaky-Test Quarantine Registry

Retrying or skipping a flaky test in place is forbidden. The **only** way to take a flaky test out of the merge gate is a committed quarantine registry entry.

### 2.1 Registry file

The registry is a committed JSON file, by default `test-quarantine.json` at the project root. Projects MAY place it elsewhere and declare the path in `.standards.yml`:

```yaml
tests:
  quarantine_file: .github/ci/test-quarantine.json
```

Start from [`templates/test-quarantine.json.example`](https://github.com/c65llc/coding-standards/blob/main/templates/test-quarantine.json.example). The file is an object with a `version` and an `entries` array of flat objects:

```json
{
  "version": 1,
  "entries": [
    {
      "test": "tests/api/test_users.py::test_list_users_paginates",
      "issue": "#482",
      "owner": "@alice",
      "reason": "Shares a DB fixture with test_bulk_import; fails under xdist when both schedule on one worker.",
      "added": "2026-10-01",
      "expires": "2026-10-29"
    }
  ]
}
```

### 2.2 Required fields

Every entry MUST carry all six fields. An entry missing any of them fails CI.

| Field | Rule |
|-------|------|
| `test` | The **exact** test id as the runner reports it (pytest node id, Jest/Vitest full title, Go `TestName/subtest`, XCTest `Class/test`). No globs, no wildcards, no file-level entries. One test per entry. |
| `issue` | Tracker reference for the fix (`#482`, `PROJ-123`, or a URL). Quarantine without an open issue is a silent skip. |
| `owner` | A person or team handle accountable for the fix. |
| `reason` | What is known about the failure mode. "Flaky" alone is not a reason. |
| `added` | ISO date (`YYYY-MM-DD`) the entry was added. |
| `expires` | ISO date the entry stops being honored. MUST be no more than **30 days** after `added`. |

### 2.3 Rules

1. **Bounded.** `expires - added` is at most 30 days. Extending an entry is a new entry with a new `added` date and a comment on the issue explaining why the first window was not enough. Two extensions of the same test require a decision from the project owner recorded on the issue: fix it, delete it, or rewrite it.
2. **Expired entries fail CI.** When `expires` is in the past the gate fails closed. The failure message names the test and the issue. Nobody may silently bump the date in the same PR that touches the failing test.
3. **Quarantined tests still run.** They move out of the merge gate; they do not stop executing. Their results feed the flake report (§ 3).
4. **Quarantine never lowers a coverage threshold.** Coverage is measured as if the quarantined tests ran and passed, or the floor is met by other tests. A registry that carries a coverage override (`coverage`, `threshold`, or similar keys) fails CI. If quarantining a test drops a module below its floor, the test is not flaky enough to quarantine; fix it.
5. **A `make test-quarantined` target runs the queue.** Developers and agents must be able to run exactly the quarantined set locally and in a scheduled CI lane, so fixes are verifiable against the real failure.

   ```makefile
   test-quarantined: ## Run only the quarantined tests (proc-05 § 2)
   	@./scripts/run-quarantined.sh test-quarantine.json
   ```

6. **Exit is a PR.** Removing an entry requires the fix PR to run the test at least 20 times without failure (`pytest --count=20`, `vitest --repeat`, `go test -count=20`, or an equivalent) and to cite that run in the PR body.

### 2.4 Enforcement

- `scripts/lint-checks/common/quarantine-policy.sh` validates the registry in `make lint-standards` and in the standards-review action: the file is valid JSON and every element of `entries` is a complete entry with non-blank required fields, exact unique ids, real ISO calendar dates, an `added` date that is not in the future, a 30-day window, no past-due entries, and no coverage overrides. It fails closed when `.standards.yml` declares a registry file that is missing, empty, or not valid JSON. A registry whose `entries` array is empty is the normal state after the last flaky test is fixed and passes, with the PASS line saying `0 quarantined test(s)`.
- The project's test runner MUST read the same file to decide what to exclude from the gate. One registry, two readers: a quarantine that only one of them knows about is a configuration bug.

## 3. Flake Surfacing Without Gating

Automatic retries hide flakes: a test that fails once and passes on retry shows up as green. Retries are allowed only when paired with a reporter.

- **Record every retried-then-passed test as a flake.** The runner's retry hook (pytest-rerunfailures, Playwright `retries`, Vitest `retry`, Go wrapper) writes the test id, attempt count, and duration to a machine-readable file (`flake-report.json`).
- **Publish, do not gate.** A flake-report step appends the list to the CI step summary (`$GITHUB_STEP_SUMMARY` or equivalent) and posts or updates a single PR comment. It never fails the build. The point is visibility; gating on it would recreate the incentive to hide flakes.
- **Trend it.** Keep the last N reports (artifact or branch) so a weekly review can see which tests flake repeatedly. Three flakes in seven days on `main` opens an issue automatically or by the on-call reviewer; the test is then quarantined per § 2 or fixed.
- **Quarantined tests report into the same file**, tagged `quarantined: true`, so the registry and the report reconcile.

## 4. Fast and Slow Test Tiers

### 4.1 Tiers

| Tier | Runs | Budget | Contents |
|------|------|--------|----------|
| **Fast** | Every PR push, every local `make test` | Whole tier under 10 minutes; each test under `tests.slow_threshold_ms` (default 2000 ms) | Unit tests, pure integration tests with in-memory substitutes, contract tests |
| **Slow** | `main`, nightly, release branches, and PRs when the routing table (§ 5) selects it | Each lane under 30 minutes; each test under its declared timeout | Container-backed integration, browser and device e2e, migration replays, performance baselines |

A test is assigned to a tier explicitly (marker, tag, directory, or build tag) and the fast lane MUST exclude the slow marker. Tier assignment is reviewed like code.

| Language | Fast/slow mechanism |
|----------|---------------------|
| Python | `@pytest.mark.slow`; fast lane runs `-m "not slow"`; `timeout` via pytest-timeout |
| TypeScript / JavaScript | Separate Vitest/Jest projects or `*.slow.test.ts` glob; `testTimeout` per project |
| Go | `//go:build slow` or `testing.Short()`; fast lane runs `-short` |
| Rust | `#[ignore]` for slow tests; slow lane runs `-- --ignored` |
| Swift / Kotlin / Java | Separate test targets or JUnit tags; per-target timeouts |
| Elixir | `@tag :slow` with `--exclude slow` in the fast alias |

### 4.2 Per-test timeouts

Every test has a timeout, enforced by the runner, not the CI job. A hanging test must fail as *that* test, with its name in the log, rather than killing the job at the 6-hour ceiling. Defaults: fast tier `tests.slow_threshold_ms`; slow tier declared per test or per lane. A test that needs more than its tier's budget moves to the next tier or is split.

### 4.3 Slow-test top-N report

Every full run (fast on PRs, fast + slow on `main`) emits the **N slowest tests** (default N = 10) with durations into the step summary and `slow-tests.json`. The report is informational, never a gate. Review it in the weekly flake review (§ 3): tests that enter the top-N while in the fast tier are candidates for the slow tier or for a fixture rewrite.

```bash
# pytest
pytest --durations=10 --durations-min=1.0
# vitest
vitest run --reporter=verbose --slowTestThreshold=2000
# go
go test -json ./... | go run ./tools/slowest -n 10
```

### 4.4 Configuration

```yaml
tests:
  slow_threshold_ms: 2000   # fast-tier per-test ceiling; also the top-N report cutoff
```

## 5. Scoped Test Suites: the Routing Table

Running every lane on every change wastes the budget; letting each developer or agent guess which lanes matter loses coverage. The project commits a **routing table** that maps changed paths to the minimum set of checks, and both CI and agents read it.

### 5.1 The file

`test-routing.yml` at the project root (or `.github/test-routing.yml`), from [`templates/test-routing.yml.example`](https://github.com/c65llc/coding-standards/blob/main/templates/test-routing.yml.example). This is the check-selection table; the CI lane filter from [arch-08 § 3](../architecture/arch-08_ci_cd_pipeline_standards.md) (`.github/ci/routing.yml`) is the workflow-side file, and a repository that uses both keeps their path globs in step:

```yaml
version: 1
default: [lint, unit]          # always run
fallback: [lint, unit, integration, e2e-web, e2e-ios]   # unmatched path => everything
routes:
  - paths: ["packages/domain/**"]
    checks: [unit, contract]
  - paths: ["packages/api/**", "migrations/**"]
    checks: [unit, integration, migration-replay]
  - paths: ["apps/web/**"]
    checks: [unit, e2e-web]
  - paths: ["apps/ios/**"]
    checks: [unit, e2e-ios]
  - paths: ["docs/**", "**/*.md"]
    checks: [docs-lint]
```

### 5.2 Rules

1. **One table, two readers.** CI's change detection (`dorny/paths-filter`, `git diff --name-only`, or the project's own script) and the agent's "what must I run before I push" step both resolve against this file. Agent configs reference it; they do not restate it.
2. **Fail closed.** A changed path matched by no route resolves to `fallback`, which is the full suite. A route may only *add* to `default`, never remove from it.
3. **Union, not first-match.** A PR touching paths in several routes runs the union of their checks.
4. **Changes to the table itself, to CI workflows, to test infrastructure, or to the lockfile resolve to `fallback`.**
5. **Checks are named, not described.** Every name in the table is a real lane that exists in CI and as a `make` target (`make check-<name>`), so an agent can run exactly the selected set locally.
6. **The PR body reports what was selected and what ran** (§ 8). A route that selected `e2e-ios` and a PR body that does not show `e2e-ios` ran is an unrun check.

## 6. Scoped Coverage

A single blanket percentage is unusable the moment a codebase contains inherited engine code, generated bindings, or native layers that no CI runner can execute. Projects declare **per-scope floors** in `.standards.yml` instead, and the floors are enforced per scope.

### 6.1 Declaration

```yaml
coverage:
  minimum: 95          # overall floor; applies to any path no scope claims
  domain: 100
  scopes:
    - path: packages/domain
      layer: domain
      minimum: 100
    - path: packages/app
      layer: application
      minimum: 95
    - path: packages/infra
      layer: infrastructure
      minimum: 95
    - path: vendor/engine
      layer: inherited
      minimum: 0
      reason: Upstream engine vendored verbatim; covered by upstream's suite, tracked in #210
    - path: apps/ios/Metal
      layer: native
      minimum: 0
      reason: Metal shaders cannot execute on CI runners; see docs/planning/manual-qa.md
```

### 6.2 Rules

1. **Domain and core stay at 100%.** A scope with `layer: domain` or `layer: core` MUST declare `minimum: 100`. No reason can lower it.
2. **Lowering needs a reason.** Any scope whose `minimum` is below the overall `coverage.minimum` MUST carry a `reason` that names *why the code cannot be measured* and *where it is verified instead* (upstream suite, manual-QA checklist, device lab). "Legacy" is not a reason.
3. **Scopes carve out; they do not average.** Each scope is measured and gated on its own. A 100% domain does not offset a 60% adapter.
4. **Unclaimed paths get the overall minimum.** New code lands under `coverage.minimum` unless a scope says otherwise, so adding code to an excluded scope to dodge the floor is visible in review.
5. **The coverage tool reads the same scopes.** The project's coverage script (`script/check_coverage.py`, `scripts/rust-coverage.sh`, Jest `coverageThreshold` per glob, or similar) derives its floors from `.standards.yml`, or a test asserts the two stay in sync.

### 6.3 Enforcement

`scripts/lint-checks/common/coverage-config.sh` parses `coverage.scopes` and fails on: a scope without a `path`, a non-integer or out-of-range `minimum`, a domain/core scope below 100, a lowered scope without a `reason`, or a duplicate path. It still accepts the single-number form for projects that have not adopted scopes.

## 7. Writing a Gate

Three gates once reported clean on a project without ever running: the scanner found zero files to scan, the detector's regex had rotted, and a skip marker had no owner. Every gate — lint check, coverage script, secret scanner, policy linter — follows these rules.

1. **Self-test on every run.** Before scanning the repository, the gate runs its detector against a built-in fixture that MUST trip it. If the fixture does not trip, the gate exits with a **distinct non-zero code** reserved for rot (this repository's lint modules emit `FAIL <check> self-test failed` and exit 1; standalone scripts use exit 2) and prints that it refused to report. A rotted detector must never print "0 findings".
2. **Fail closed on an empty scan.** A gate that scans a path set and finds **nothing to scan** fails, with a message naming the glob. An empty match is a configuration error (moved directory, wrong working directory, renamed extension), not a clean result. The only exception is a gate whose domain is legitimately optional, which must say so in its PASS line (`No quarantine registry (none declared) — nothing quarantined`).
3. **Escape markers state a reason.** Any inline suppression (`# noqa: E501 -- reason`, `// eslint-disable-next-line rule -- reason`, `# standards: allow-secret-pattern reason=test fixture`) MUST carry a reason on the same line, and the gate MUST reject a bare marker. Markers without an issue reference for anything other than a documented false positive are review blockers.
4. **Never report an unrun check as passing.** A gate that is skipped — by a path filter, a missing tool, a disabled input — reports `skipped`, never `passed`. Status checks that aggregate lanes treat `skipped` as not-run, and the PR evidence (§ 8) lists it as such.
5. **Deterministic across hosts.** A gate's verdict does not depend on which optional tools are installed. If a dependency is optional, its absence is a `FAIL`/`skipped` with a message, not a different code path that passes.
6. **Exit codes are documented in the header** and tested: at least one functional test asserts the gate trips on the fixture and one asserts it passes on a clean input.

These rules apply to this repository's own `scripts/lint-checks/*` modules; see [`scripts/lint-checks/README.md`](https://github.com/c65llc/coding-standards/blob/main/scripts/lint-checks/README.md).

## 8. PR Evidence: Tested Commit and Slow-Check Table

Fast CI passing on a PR does not prove the slow lanes ran. The PR body carries the evidence. Projects install [`templates/pull_request_template.md.example`](https://github.com/c65llc/coding-standards/blob/main/templates/pull_request_template.md.example) as `.github/pull_request_template.md`.

### 8.1 Required sections

- **Tested commit SHA.** The exact commit the evidence below was produced on. If the branch moves after the evidence was gathered, the evidence is stale and the section is updated or the PR is marked as not ready.
- **Routing.** Which routes from `test-routing.yml` (§ 5) the changed paths selected.
- **Slow-check evidence table.** One row per selected slow or platform-specific check:

  | Surface | Command | Result | Evidence |
  |---------|---------|--------|----------|
  | iOS e2e | `make check-e2e-ios` | pass (42/42) | run link or log excerpt |
  | Migration replay | `make check-migration-replay` | not run | reason |

- **"Fast CI passing does not satisfy this section."** The sentence stays in the template so nobody treats a green PR check as evidence for a lane that did not execute.

### 8.2 Rules

1. **Never report an unrun check as passing.** `not run` with a reason is acceptable and reviewable; `pass` for a check that did not execute is a reporting failure and, for agents, a standards violation that blocks the PR.
2. **Evidence is a link or an excerpt**, not an adjective. "Tested locally" is not evidence.
3. **Agents fill the table from real output.** An agent that cannot run a lane (no device, no credentials) writes `not run — <reason>` and tracks the manual step as an issue per `core-standards.md` § Untestable Boundaries.
4. **Reviewers check the SHA.** The review approves the tested commit; a later force-push without updated evidence re-requests review.

## 9. End-to-End Lanes Never Target Production

An e2e cleanup lane once came within one guard of deleting a real customer account. The rules below are not optional for any lane that can log in, mutate data, or delete anything.

1. **No e2e lane targets production.** Base URLs, API hosts, and credentials for e2e come from a staging or ephemeral environment. The lane asserts at startup that its target is not a production host (hostname allowlist, environment tag, or a `NOT_PRODUCTION` canary endpoint) and aborts if it is.
2. **Protected test identities.** E2E runs use dedicated test accounts whose identifiers carry a recognizable marker (`e2e-` prefix, reserved domain, tagged tenant). Cleanup lanes may only act on identities carrying that marker and MUST refuse to run if the marker filter matches zero rows or is missing.
3. **Production-touching lanes are opt-in and gated.** Any lane that must reach production (smoke after deploy, synthetic monitoring) is a separate workflow with `workflow_dispatch` or environment protection, a named approver, read-only credentials where possible, and no delete capability.
4. **Human-only operations ship as runbooks.** When a step cannot be safely automated (purging real data, rotating a production credential, approving an app-store build), the PR ships a runbook (`docs/runbooks/<operation>.md`) with the exact commands, the preconditions, the verification, and the rollback. The tracking issue stays open until a human records that the runbook was executed. Automating the step later is a new PR against the runbook.
5. **Secrets for e2e are scoped.** Staging credentials live in the CI environment for the e2e lane only, never in the fast lane, so a fast-tier test can never accidentally reach a real system.

## 10. Configuration Reference

Keys added to `.standards.yml` by this standard (see [`standards-yml-schema.md`](../shared/standards-yml-schema.md) for the full schema):

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `coverage.scopes` | list of `{path, layer, minimum, reason}` | none | Per-path coverage floors (§ 6) |
| `tests.quarantine_file` | string | `test-quarantine.json` | Location of the quarantine registry (§ 2) |
| `tests.slow_threshold_ms` | integer | `2000` | Fast-tier per-test ceiling and top-N report cutoff (§ 4) |

Templates shipped with this standard:

| Template | Install as |
|----------|-----------|
| `templates/test-quarantine.json.example` | `test-quarantine.json` (or the declared `tests.quarantine_file`) |
| `templates/pull_request_template.md.example` | `.github/pull_request_template.md` |
| `templates/test-routing.yml.example` | `test-routing.yml` |
| `templates/standards.yml.example` | `.standards.yml` (already installed by `setup.sh`; adds `coverage.scopes` and `tests.*`) |

## Related Standards

- [`core-standards.md`](../shared/core-standards.md) § Testing Standards — TDD, coverage floors, untestable boundaries
- [`proc-03_code_review_expectations.md`](./proc-03_code_review_expectations.md) — what reviewers verify in the evidence table
- [`proc-04_agent_workflow_standards.md`](./proc-04_agent_workflow_standards.md) — the agent lifecycle that produces the PR evidence
- [`arch-08_ci_cd_pipeline_standards.md`](../architecture/arch-08_ci_cd_pipeline_standards.md) — pipeline structure the lanes live in
- [`sec-01_security_standards.md`](../security/sec-01_security_standards.md) — credential handling for e2e environments
