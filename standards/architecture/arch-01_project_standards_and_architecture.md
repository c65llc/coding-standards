# Project Standards & Architecture

## 1. AI Behavior Guidelines

* **Tone:** Terse, objective, professional.
* **Response Style:** Code-focused. No conversational filler.
* **Iterative:** Output interface/structure first, confirm, then implement details.

## 2. Monorepo Architecture (Clean Architecture)

**Dependency Rule:** Source code dependencies point inward only.

### Directory Structure

```text
/
├── apps/                  # (Outer Layer) Entry points & Frameworks
│   ├── [app_name]/        # Deployable units
│   └── ...
├── packages/              # (Inner Layers) Shared Business Logic
│   ├── domain/            # (Core) Entities, Types (No deps)
│   ├── application/       # (Orchestration) Use Cases, Interfaces
│   └── infrastructure/    # (Adapters) External impls (DB, API)
├── tools/                 # Build scripts, generators
└── docs/                  # (Explicit Home) All architectural & project documentation
```

### Layer Responsibilities

* **Domain:** Pure business logic. No external dependencies. Contains entities, value objects, domain events, and domain exceptions.
* **Application:** Orchestrates domain logic. Defines use cases and repository interfaces. Depends only on Domain.
* **Infrastructure:** Implements application interfaces. Handles external concerns (databases, APIs, file systems). Depends on Application and Domain.
* **Apps:** Entry points (CLI, web servers, workers). Depends on all inner layers.

## 3. Coding Standards

### SOLID Principles

Strict adherence required. Violations must be justified in code comments.

### Naming Conventions

**Python:**

* `snake_case` for variables, functions, modules, files
* `PascalCase` for classes
* `UPPER_SNAKE_CASE` for constants
* `_leading_underscore` for private/internal

**JavaScript/TypeScript:**

* `camelCase` for variables, functions
* `PascalCase` for classes, components, types, interfaces
* `kebab-case` for files, directories
* `UPPER_SNAKE_CASE` for constants
* `_leading_underscore` for private/internal

**General:**

* Verbose and descriptive names. Avoid abbreviations.
* Boolean variables use `is_`, `has_`, `should_`, `can_` prefixes.
* Functions are verbs. Classes are nouns.

**Architectural Naming:**

* Use distinct naming prefixes for library crates/packages vs. app crates/packages. This makes it immediately clear which architectural layer a module belongs to.
* Library/framework packages use a framework prefix (e.g., `lattice-core`, `lattice-layout`).
* App/product packages use a product prefix (e.g., `trellis-cli`, `trellis-desktop`).
* Document the naming convention in the project's AI guide (`CLAUDE.md`) or `README.md`.

### Code Style

* **Comments:** Only "Why", never "What". Self-documenting code preferred.
* **Line Length:** 100 characters (Python), 120 characters (JS/TS).
* **Imports:** Grouped (stdlib, third-party, local). Sorted alphabetically within groups.
* **Formatting:** Enforced via automated tools (Black, Prettier, Rustfmt).

### Error Handling

* **Fail Fast:** Validate inputs at boundaries. Reject invalid state immediately.
* **Typed Errors:** Custom error classes in Domain layer. No generic exceptions.
* **Error Propagation:** Let errors bubble up. Handle at appropriate layer (UI, API gateway).
* **Logging:** Structured logging. Include context (request ID, user ID, operation).

### Type Safety

* **TypeScript:** Strict mode enabled. No `any` without explicit justification.
* **Python:** **All code must be strongly typed.** Type hints required on every function, method, variable declaration, and class attribute — not just public APIs. Run `mypy` or `pyright` in **strict mode** with zero errors. No `# type: ignore` without an accompanying comment explaining why.
* **Rust:** Leverage type system. Use `Result<T, E>` for fallible operations.

## 4. Testing Standards

### Test-Driven Development (TDD) — Mandatory

**All new code MUST be written using Test-Driven Development when possible.** TDD is the default methodology, not an optional practice.

1. **Red:** Write a failing test that defines the expected behavior.
2. **Green:** Write the minimum code to make the test pass.
3. **Refactor:** Clean up the implementation while keeping tests green.

When modifying existing untested code, write characterization tests first before making changes.

### Automated Regression & Local Full-Stack Testing

* **Regression tests:** Every bug fix MUST include a test that reproduces the bug and prevents recurrence.
* **Local full-stack testing:** The complete application stack must be runnable locally via `make dev` + `make test`. Use Docker Compose, test containers, or in-memory substitutes for all external dependencies.
* **CI parity:** Local `make test` must run the same suite as CI. No environment-specific test gaps.

### Test Structure

* **Unit Tests:** Test domain logic in isolation. Mock external dependencies.
* **Integration Tests:** Test layer interactions. Use test databases/containers.
* **E2E Tests:** Test complete user workflows. Minimal set, high-value scenarios.
* **Regression Tests:** Every bug fix includes a test that prevents recurrence.

### Coverage Requirements — 95% Absolute Minimum

**95% test coverage is the absolute minimum for any module, in any layer.**

* **Domain:** 100% coverage. Business logic must be fully tested.
* **Application:** 95%+ coverage. All use cases and orchestration paths tested.
* **Infrastructure:** 95%+ coverage. Adapters and integrations tested.

Coverage gates MUST be enforced in CI. A PR that drops any module below 95% MUST NOT be merged.

### Test Organization

* Mirror source structure: `src/domain/user.py` → `tests/domain/test_user.py`
* Use descriptive test names: `test_should_raise_error_when_email_is_invalid`
* One assertion per test when possible.

### Pure Logic Separation

* View model transformations and business logic SHOULD be pure functions testable without framework dependencies.
* UI rendering layers should consume view models (plain data structures) rather than computing state inline.
* This enables testing complex UI behavior (sidebar trees, drag-drop logic, navigation) without spinning up a framework runtime.

## 5. Dependency Management

### Package Managers

* **Python:** `uv` for dependency management (preferred over `poetry` or naked `pip`). Lock files committed.
* **JavaScript/TypeScript:** `pnpm` preferred, `npm` acceptable. Lock files committed.
* **Rust:** `cargo`. `Cargo.lock` committed for applications, not libraries.

### Version Pinning

* Pin exact versions in production dependencies.
* Use ranges for development dependencies.
* Regular dependency audits and updates.

### Dependency Rules

* No circular dependencies between packages.
* Domain has zero external dependencies (except standard library).
* Infrastructure may depend on external libraries (ORM, HTTP clients).

## 6. Environment & Isolation

### Development Environment

* **Isolation:** All dev environments must be containerized (Docker) or strictly virtualized (venv/conda).
* **No Global Installs:** Never rely on system-wide packages.
* **Reproducibility:** `make dev` must provision identical environment for all developers.

### Environment Variables

* Use `.env.example` template. Never commit `.env` files.
* Validate required environment variables at startup.
* Use typed configuration objects. No magic strings.

### Containerization

* Multi-stage Docker builds for production.
* Development containers for consistent tooling.
* Docker Compose for local orchestration.

## 7. Version Control

### Git Workflow

* **Branching:** Feature branches from `main`. Descriptive branch names: `feature/user-authentication`.
* **Commits:** Atomic, meaningful commits. Use conventional commit format.
* **Pull Requests:** Required for all changes. Code review mandatory. PRs are the terminal step of all work — nothing is "done" without one.
* **One task = one branch = one PR.** Each discrete unit of work gets its own branch and its own pull request.

### Commit Messages

Format: `type(scope): subject`

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `ci`

Example: `feat(domain): add user email validation`

### Git Hooks

* Pre-commit: Run linters and formatters.
* Pre-push: Run test suite.
* Commit-msg: Validate commit message format.

## 8. Documentation

### Code Documentation

* **API Docs:** Generate from code (JSDoc, docstrings, rustdoc).
* **README:** Every package/app must have README with setup instructions.
* **Architecture Decisions:** Document in `docs/adr/` using ADR format.

### Inline Documentation

* Document complex algorithms and business rules.
* Explain non-obvious design decisions.
* Reference related issues/PRs when applicable.

## 9. Work Tracking

* **Default tool:** GitHub Issues. All bugs, features, tech debt, and follow-ups MUST be tracked.
* **TODOs in code:** Every `TODO` or `FIXME` comment MUST reference a GitHub Issue number (e.g., `# TODO(#42): ...`).
* **PR linking:** PRs must reference related issues (`Closes #123`, `Fixes #456`).
* **Override:** Projects may specify an alternative tracker (Jira, Linear, etc.) in `CLAUDE.md`, `README.md`, or `.github/CONTRIBUTING.md`.
* **Agents:** AI agents must create issues when they discover bugs, identify tech debt, or add TODO comments. Never silently defer work.

See `standards/shared/core-standards.md` for full details.

## 10. Security

### Secrets Management

* Never commit secrets, API keys, or credentials.
* Use secret management services (AWS Secrets Manager, Vault).
* Rotate credentials regularly.

### Input Validation

* Validate and sanitize all external inputs.
* Use parameterized queries. No string concatenation for SQL.
* Rate limiting on public APIs.

### Dependency Security

* Regular security audits (`npm audit`, `cargo audit`, `safety`).
* Automated vulnerability scanning in CI/CD.
* Patch critical vulnerabilities immediately.
