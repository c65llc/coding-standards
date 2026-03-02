# Core Project Standards

This file contains the core standards that apply across all AI coding assistants. Agent-specific configurations reference this file to ensure consistency.

## Architecture Principles

### Clean Architecture (Monorepo)

**Dependency Rule:** Source code dependencies point inward only.

```
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
- **Formatting:** Enforced via automated tools (Black, Prettier, Rustfmt).

### Error Handling

- **Fail Fast:** Validate inputs at boundaries. Reject invalid state immediately.
- **Typed Errors:** Custom error classes in Domain layer. No generic exceptions.
- **Error Propagation:** Let errors bubble up. Handle at appropriate layer (UI, API gateway).
- **Logging:** Structured logging. Include context (request ID, user ID, operation).

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

### Test Organization

- Mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
- Use descriptive test names: `test_should_raise_error_when_email_is_invalid`
- One assertion per test when possible.

## Dependency Management

### Package Managers

- **Python:** `poetry` or `uv` for dependency resolution. Lock files committed.
- **JavaScript/TypeScript:** `pnpm` preferred, `npm` acceptable. Lock files committed.
- **Rust:** `cargo`. `Cargo.lock` committed for applications, not libraries.

### Version Pinning

- Pin exact versions in production dependencies.
- Use ranges for development dependencies.
- Regular dependency audits and updates.

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
- **Architecture Decisions:** Document in `docs/adr/` using ADR format.

### Inline Documentation

- Document complex algorithms and business rules.
- Explain non-obvious design decisions.
- Reference related issues/PRs when applicable.

## Security

### Secrets Management

- Never commit secrets, API keys, or credentials.
- Use secret management services (AWS Secrets Manager, Vault).
- Rotate credentials regularly.

### Input Validation

- Validate and sanitize all external inputs.
- Use parameterized queries. No string concatenation for SQL.
- Rate limiting on public APIs.

### Dependency Security

- Regular security audits (`npm audit`, `cargo audit`, `safety`).
- Automated vulnerability scanning in CI/CD.
- Patch critical vulnerabilities immediately.

## Language-Specific Standards

Reference detailed standards in:
- `standards/languages/03_python_standards.md`
- `standards/languages/04_java_standards.md`
- `standards/languages/05_kotlin_standards.md`
- `standards/languages/06_swift_standards.md`
- `standards/languages/07_dart_standards.md`
- `standards/languages/08_typescript_standards.md`
- `standards/languages/09_javascript_standards.md`
- `standards/languages/10_rust_standards.md`
- `standards/languages/11_zig_standards.md`

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
- `standards/process/12_documentation_standards.md`
- `standards/process/13_git_version_control_standards.md`
- `standards/process/14_code_review_expectations.md`

## Architecture Patterns

Reference architecture pattern standards in:
- `standards/architecture/16_data_versioning_and_migration_standards.md`
- `standards/architecture/17_resilient_architecture_patterns.md`

## Agent Workflow

Reference agent workflow standards in:
- `standards/process/15_agent_workflow_standards.md`



