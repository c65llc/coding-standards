# Core Project Standards

This file contains the core standards that apply across all AI coding assistants. Agent-specific configurations reference this file to ensure consistency.

## Architecture Principles

### Clean Architecture (Monorepo)

**Dependency Rule:** Source code dependencies point inward only.

```text
/
├── apps/                  # (Outer Layer) Entry points & Frameworks
├── packages/              # (Inner Layers) Shared Business Logic
│   ├── domain/            # (Core) Entities, Types (No deps)
│   ├── application/       # (Orchestration) Use Cases, Interfaces
│   └── infrastructure/    # (Adapters) External impls (DB, API)
├── tools/                 # Build scripts, generators
└── docs/                  # All architectural & project documentation
```

### Layer Responsibilities

- **Domain:** Pure business logic. No external dependencies. Contains entities, value objects, domain events, and domain exceptions.
- **Application:** Orchestrates domain logic. Defines use cases and repository interfaces. Depends only on Domain.
- **Infrastructure:** Implements application interfaces. Handles external concerns (databases, APIs, file systems). Depends on Application and Domain.
- **Apps:** Entry points (CLI, web servers, workers). Depends on all inner layers.

## Coding Standards

### SOLID Principles

Strict adherence required. Violations must be justified in code comments.

### Naming Conventions

**Python:**

- `snake_case` for variables, functions, modules, files
- `PascalCase` for classes
- `UPPER_SNAKE_CASE` for constants
- `_leading_underscore` for private/internal

**JavaScript/TypeScript:**

- `camelCase` for variables, functions
- `PascalCase` for classes, components, types, interfaces
- `kebab-case` for files, directories
- `UPPER_SNAKE_CASE` for constants
- `_leading_underscore` for private/internal

**General:**

- Verbose and descriptive names. Avoid abbreviations.
- Boolean variables use `is_`, `has_`, `should_`, `can_` prefixes.
- Functions are verbs. Classes are nouns.

### Code Style

- **Comments:** Only "Why", never "What". Self-documenting code preferred.
- **Line Length:** 100 characters (Python), 120 characters (JS/TS).
- **Imports:** Grouped (stdlib, third-party, local). Sorted alphabetically within groups.
- **Formatting:** Enforced via automated tools (Ruff, Prettier, Rustfmt).

### Error Handling

- **Fail Fast:** Validate inputs at boundaries. Reject invalid state immediately.
- **Typed Errors:** Custom error classes in Domain layer. No generic exceptions.
- **Error Propagation:** Let errors bubble up. Handle at appropriate layer (UI, API gateway).
- **Logging:** Structured logging. Include context (request ID, user ID, operation).
- **User-Facing Error Copy:** Every error a person can see (UI, CLI, API `detail`) states what happened **and the next step** — retry, fix a named input, check a named setting, or contact support with a reference id. Never a bare "Something went wrong", a raw exception message, or an error code alone.
- **Stale Responses:** A late asynchronous response must never overwrite newer state. Tag in-flight requests and discard out-of-order completions (see `arch-05` §10).

### Type Safety

- **TypeScript:** Strict mode enabled. No `any` without explicit justification.
- **Python:** **All code must be strongly typed.** Type hints required on every function, method, variable declaration, and class attribute — not just public APIs. Run `mypy` or `pyright` in **strict mode** with zero errors. No `# type: ignore` without an accompanying comment explaining why.
- **Rust:** Leverage type system. Use `Result<T, E>` for fallible operations.

## Testing Standards

### Test-Driven Development (TDD) — Mandatory

**All new code MUST be written using Test-Driven Development when possible.** TDD is not optional — it is the default methodology.

1. **Red:** Write a failing test that defines the expected behavior.
2. **Green:** Write the minimum code to make the test pass.
3. **Refactor:** Clean up the implementation while keeping tests green.

TDD applies to all layers — domain logic, application services, infrastructure adapters, and API endpoints. The only acceptable exceptions are:

- Thin UI rendering layers that consume view models (the view model logic itself must be TDD).
- Generated code (e.g., ORM migrations, protobuf stubs).
- One-off scripts that will not be maintained.

When modifying existing code that lacks tests, **write characterization tests first** before making changes.

### Automated Regression & Local Full-Stack Testing

Projects MUST build testing infrastructure that supports:

- **Automated regression testing:** Every bug fix must include a regression test that reproduces the bug before the fix and passes after. CI must run the full regression suite on every PR.
- **Local full-stack testing:** Developers and agents must be able to run the complete application stack locally (via `make dev` + `make test`) without relying on shared environments. Use Docker Compose, test containers, or in-memory substitutes to provide all external dependencies (databases, message queues, third-party APIs) locally.
- **Test fixtures and factories:** Maintain reusable test data builders and fixtures. Never rely on production data for testing. Use deterministic seed data (see `make seed` in automation standards).
- **CI parity:** Local test execution (`make test`) must run the same test suite as CI. No "works on CI but not locally" or vice versa.

### Test Structure

- **Unit Tests:** Test domain logic in isolation. Mock external dependencies.
- **Integration Tests:** Test layer interactions. Use test databases/containers.
- **E2E Tests:** Test complete user workflows. Minimal set, high-value scenarios.
- **Regression Tests:** Every bug fix includes a test that prevents recurrence.

### Coverage Requirements — 95% Absolute Minimum

**95% test coverage is the absolute minimum for any module, in any layer.** There are no exceptions to this floor.

| Layer | Min Coverage | Notes |
|-------|-------------|-------|
| Domain / Core | 100% | Pure business logic — no excuses |
| Application / Shell | 95%+ | All use cases and orchestration paths tested |
| Infrastructure / Integration | 95%+ | Adapters, repositories, and external integrations tested |

Coverage gates MUST be enforced in CI. A PR that drops coverage below 95% in any module MUST NOT be merged.

Projects with inherited, generated, or native code that no CI runner can execute declare **per-scope floors** in `.standards.yml` (`coverage.scopes`) instead of a single blanket number. Domain/core scopes stay at 100%; any scope below the overall minimum states a `reason` and where the code is verified instead. See `proc-05_test_governance.md` § 6.

### Untestable Boundaries

Some runtime surfaces genuinely cannot run in CI — a real filesystem-access API,
a device keychain, a native window server, a third-party SDK with no test mode.
The coverage floor is met with **real tests**, never by gaming the number.

- **Keep the untestable boundary thin.** Push all logic *behind* it into pure,
  testable units (the parsing, the decision, the transformation) and cover those
  fully. The thin remaining adapter is the only part that can't be unit-tested.
- **Never add dead or unreachable branches to hit a coverage target.** That is the
  opposite of the goal — it ships untested code paths *and* hides the real gap, and
  automated reviewers will (correctly) flag it.
- **Flag the residual manual-verification step explicitly** — in the PR body and,
  for agents, as a tracked item — rather than pretending the boundary is covered.
- **Commit an auditable manual-QA checklist in-repo** (e.g.
  `docs/planning/<version>-manual-qa.md`) enumerating the exact steps CI cannot
  reach — Touch-ID prompts, native window-server behavior, on-device flows — and
  update it each release. A committed checklist makes the carve-out reviewable and
  travels with the release, instead of living only as a verbal "flag it."
- Document the exclusion (and why) where the project records coverage policy, so
  the carve-out is auditable rather than silent.

### Test Organization

- Mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
- Use descriptive test names: `test_should_raise_error_when_email_is_invalid`
- One assertion per test when possible.

### Test Governance

Flaky and slow tests, change-scoped suites, and gates that can pass without running are governed by `standards/process/proc-05_test_governance.md`:

- **Flaky tests** go in the committed quarantine registry (`test-quarantine.json`: exact test id, issue, owner, reason, `added`, `expires` ≤ 30 days). Never retry, skip, or disable a test in place. Expired entries fail CI. Quarantine never lowers a coverage threshold. `make test-quarantined` runs the queue.
- **Flakes are surfaced, not gated:** retried-then-passed tests are reported to the step summary and never fail the build.
- **Fast/slow tiers** with per-test timeouts and a slow-test top-N report; the fast tier runs on every PR.
- **Scoped suites:** `ci-routing.yml` maps changed paths to the minimum checks; CI and agents read the same table; unmatched paths run everything.
- **PR evidence:** tested commit SHA plus a slow-check evidence table. Never report an unrun check as passing.
- **Gates** self-test on every run, fail closed on an empty scan, and require a reason on every escape marker.
- **E2E lanes never target production**; they use protected test identities, and human-only operations ship as runbooks.

## Dependency Management

### Package Managers

- **Python:** `uv` for dependency management (preferred over `poetry` or naked `pip`). Lock files committed.
- **JavaScript/TypeScript:** `pnpm` preferred, `npm` acceptable. Lock files committed.
- **Rust:** `cargo`. `Cargo.lock` committed for applications, not libraries.
- **Ruby:** `bundler` for gem management. `mise` for Ruby version management. `Gemfile.lock` committed.

### Version Pinning

- Pin exact versions in production dependencies.
- Use ranges for development dependencies.
- Regular dependency audits and updates.

### Automated Dependency Updates

- Bot updates (Dependabot, Renovate) are **grouped** for every ecosystem watched: minor + patch bumps batched per ecosystem per week, majors as their own PRs — except GitHub Actions majors (pinned SHAs change on every release and a major is rarely breaking; one group for all) and lockstep partners (a partner set's major lands in its pattern group so it never splits). An ungrouped queue gets hand-merged in omnibus commits nobody reviewed.
- Partners that only break in company (`react` + `react-dom`, `@typescript-eslint/*`, `vite` + `@vitejs/*`, `tokio` + `tokio-*`) share a pattern group so their updates land in one PR. A group batches what is available; it does not force partners to move together, so the lockstep invariant itself is a CI assertion on the lockfile (arch-07 §3), and the group is what keeps that assertion green. List the project's lockstep sets explicitly.
- Bot PRs pass the same gate as any PR, including the age gate below. Template: `templates/dependabot.yml.example`; rationale in `standards/security/sec-01_security_standards.md` §5.

### Dependency Age Gate

- **All 3rd-party dependency versions must be at least 3 days old before adoption.** Do not upgrade to or add a dependency version published less than 72 hours ago.
- This applies to new dependencies and version upgrades alike.
- CI should enforce age verification against the registry publish date.
- Emergency security patches may bypass this gate only through the `dep-age-override` label plus an approval comment `Dep-age approved: <head SHA>` from a listed approver who is not the PR author, plus a `Dep-age override:` block in the PR body naming that approver; merging then opens a `dep-age-follow-up` issue due 24 hours after merge. A red advisory lane is not an override. See `standards/security/sec-01_security_standards.md` §5 for the reference implementation.

### Package Patches (`patches/`)

A patch to a third-party package (`patch-package`, pnpm `patchedDependencies`, Cargo `[patch]`, a vendored diff, a fork pin) is a fork you now maintain. Every override is recorded in `patches/README.md`, one entry per overridden dependency, identified by its patch file path or — for a manifest-only override such as a Cargo `[patch]` table or a fork pin — by the manifest coordinate and the pinned revision (`[patch.crates-io] foo = { git = "…", rev = "abc123" }`), with three fields:

- **Why** — the upstream bug or missing hook, with the upstream issue or PR link.
- **Regression test** — the test in this repo that fails without the patch, so a bot bump that silently drops it is caught by CI rather than in production.
- **Removal criterion** — the upstream version (or condition) at which the patch is deleted, and who checks it on each bump.

A patch with no README entry is removed. A README entry whose removal criterion has been met is a toolchain workaround past its expiry (`standards/architecture/arch-02_automation_standards.md` §8) and is deleted or re-justified with a new `TODO(#issue)`. Grouped bot updates re-apply patches when the group lands; the README is how the next person knows what to re-verify.

### Dependency Rules

- No circular dependencies between packages.
- Domain has zero external dependencies (except standard library).
- Infrastructure may depend on external libraries (ORM, HTTP clients).

## Environment & Isolation

### Development Environment

- **Isolation:** All dev environments must be containerized (Docker) or strictly virtualized (venv/conda).
- **No Global Installs:** Never rely on system-wide packages.
- **Reproducibility:** `make dev` must provision identical environment for all developers.

### Environment Variables

- Use `.env.example` template. Never commit `.env` files.
- Validate required environment variables at startup.
- Use typed configuration objects. No magic strings.

## Version Control

### Git Workflow

- **Branching:** Feature branches from `main`. Descriptive branch names: `feature/user-authentication`.
- **Commits:** Atomic, meaningful commits. Use conventional commit format.
- **Pull Requests:** Required for all changes. Code review mandatory. PRs are the terminal step of all work — nothing is "done" without one.
- **One task = one branch = one PR.** Each discrete unit of work gets its own branch and its own pull request.

### Commit Messages

Format: `type(scope): subject`

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`

Example: `feat(domain): add user email validation`

## Documentation

### Code Documentation

- **API Docs:** Generate from code (JSDoc, docstrings, rustdoc).
- **README:** Every package/app must have README with setup instructions.
- **Architecture Decisions:** Document in `docs/adr/` using the ADR template (bullet metadata: Status, Date, Related, Supersedes/Extends; sections Context, Decision, Consequences). Spec, plan, design-pass and verification templates live in `templates/docs/` of the standards repository — `.standards/templates/docs/` in a project that installed it (`proc-01` §11).

### Inline Documentation

- Document complex algorithms and business rules.
- Explain non-obvious design decisions.
- Reference related issues/PRs when applicable.

## Security

> Full security standards with code examples: `standards/security/sec-01_security_standards.md`
>
> Severity model: **P0** (Critical) and **P1** (High) findings block merge. **P2** (Medium) are warnings.

### P0 — Critical (Must Block Merge)

- Never construct SQL via string concatenation with user input. Use parameterized queries.
- Never pass unsanitized user input to `eval()`, `exec()`, `system()`, or shell commands.
- Never commit secrets, API keys, passwords, or credentials to source code.
- Never deserialize untrusted data using native serialization (pickle, Marshal, ObjectInputStream).
- Never ship default credentials in production.
- Verify authentication on every request. Never bypass auth checks.

### P1 — High (Must Block Merge)

- Encode all output in HTML contexts. Never use `innerHTML` with untrusted data.
- Validate and sanitize URL inputs. Block SSRF to internal IP ranges.
- Enable CSRF protection on all state-changing endpoints.
- Set secure cookie attributes (`Secure`, `HttpOnly`, `SameSite`). Regenerate session IDs after login.
- Never pass user input into server-side template expressions or evaluated template strings.
- Enforce authorization checks on every endpoint.
- Use cryptographically secure random for tokens, keys, and session IDs.
- Run dependency vulnerability scanning in CI/CD. Commit lock files.
- Enforce HTTPS/TLS for all external communication.
- Configure security headers (CSP, HSTS, X-Content-Type-Options, X-Frame-Options).
- Never log passwords, tokens, API keys, or PII.
- Add `.env` to `.gitignore`. Never commit `.env` files.
- Fence external content returned to an AI agent in `<untrusted-data>`; never interpolate it into prompts or tool descriptions.
- Gate every agent tool write behind a `writes` flag, `preview`, and approval; audit-log every tool call.

### P2 — Medium (Flag as Warning)

- Missing rate limiting on public-facing endpoints.
- Verbose error messages exposing internal details in production.
- Unpinned dependency versions.
- Missing encryption at rest for sensitive data.

### Secrets Management

- Use secret management services (AWS Secrets Manager, Vault, GCP Secret Manager).
- Rotate credentials regularly.
- Scan for secrets with `git-secrets`, `truffleHog`, or `detect-secrets`.

### Dependency Security

- Regular security audits (`pnpm audit`, `npm audit`, `cargo audit`, `pip-audit`, `bundle-audit`).
- Automated vulnerability scanning in CI/CD.
- Patch critical vulnerabilities immediately.

## Language-Specific Standards

Reference detailed standards in:

- `standards/languages/lang-01_python_standards.md`
- `standards/languages/lang-02_java_standards.md`
- `standards/languages/lang-03_kotlin_standards.md`
- `standards/languages/lang-04_swift_standards.md`
- `standards/languages/lang-05_dart_standards.md`
- `standards/languages/lang-06_typescript_standards.md`
- `standards/languages/lang-07_javascript_standards.md`
- `standards/languages/lang-08_rust_standards.md`
- `standards/languages/lang-09_zig_standards.md`
- `standards/languages/lang-10_ruby_standards.md`
- `standards/languages/lang-11_ruby_on_rails_standards.md`

## Work Tracking

### GitHub Issues as Default Tracker

**All identified work — features, bugs, tech debt, refactors, and follow-ups — MUST be tracked as GitHub Issues on the repository unless a project specifies an alternative tool.**

#### What Must Be Tracked

- **Bugs:** Every bug discovered during development, testing, or code review.
- **Features:** New functionality, enhancements, and user-facing changes.
- **Tech debt:** Shortcuts, known limitations, and deferred improvements.
- **Follow-ups:** Items discovered during implementation that are out of scope for the current PR.
- **TODOs:** Any `TODO` or `FIXME` comment added to the codebase MUST have a corresponding GitHub Issue. The comment must reference the issue number (e.g., `# TODO(#42): refactor once auth module is extracted`).

#### Issue Requirements

- **Title:** Clear, actionable description in imperative form (e.g., "Add rate limiting to /api/users endpoint").
- **Labels:** Use consistent labels (`bug`, `enhancement`, `tech-debt`, `documentation`, etc.).
- **Context:** Include enough detail for someone unfamiliar with the current work to understand and act on the issue.
- **Linking:** PRs should reference related issues (`Closes #123`, `Fixes #456`, `Part of #789`).

#### Overriding the Default Tracker

Projects MAY use an alternative tracking tool (Jira, Linear, Shortcut, etc.) by specifying it in one of these locations:

1. **`CLAUDE.md`** — in a `## Work Tracking` section.
2. **`README.md`** — in project setup or contributing docs.
3. **`.github/CONTRIBUTING.md`** — in the contribution guidelines.

When an alternative is specified, all references to "GitHub Issues" in these standards should be read as referring to the configured tool. The same requirements (actionable titles, context, linking) still apply.

#### Agent Responsibility

AI agents MUST create GitHub Issues (or the project's configured tracker items) when they:

- Discover bugs or failing edge cases during implementation.
- Identify tech debt or shortcuts taken to meet scope.
- Encounter out-of-scope work that should be addressed later.
- Add `TODO` or `FIXME` comments to the codebase.

Agents must NOT silently defer work. If something needs to be done, it needs to be tracked.

## Process Standards

Reference detailed process standards in:

- `standards/process/proc-01_documentation_standards.md`
- `standards/process/proc-02_git_version_control_standards.md`
- `standards/process/proc-03_code_review_expectations.md`
- `standards/process/proc-05_test_governance.md`

## Architecture Patterns

Reference architecture pattern standards in:

- `standards/architecture/arch-04_data_versioning_and_migration_standards.md`
- `standards/architecture/arch-05_resilient_architecture_patterns.md`
- `standards/architecture/arch-06_monorepo_workspace_standards.md`
- `standards/architecture/arch-07_cross_platform_shared_core_standards.md`
- `standards/architecture/arch-08_ci_cd_pipeline_standards.md`
- `standards/architecture/arch-10_agent_tools_and_mcp_server_standards.md`

## Security Standards

Reference detailed security standards in:

- `standards/security/sec-01_security_standards.md`

## Agent Workflow

Reference agent workflow standards in:

- `standards/process/proc-04_agent_workflow_standards.md`
