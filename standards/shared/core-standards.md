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
- **Python:** Type hints required for all public APIs. Use `mypy` or `pyright`.
- **Rust:** Leverage type system. Use `Result<T, E>` for fallible operations.

## Testing Standards

### Test Structure

- **Unit Tests:** Test domain logic in isolation. Mock external dependencies.
- **Integration Tests:** Test layer interactions. Use test databases/containers.
- **E2E Tests:** Test complete user workflows. Minimal set, high-value scenarios.

### Coverage Requirements

- **Domain:** 100% coverage. Business logic must be fully tested.
- **Application:** 90%+ coverage. All use cases tested.
- **Infrastructure:** 80%+ coverage. Critical paths tested.

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
- **Pull Requests:** Required for all changes. Code review mandatory.

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

## Process Standards

Reference detailed process standards in:
- `standards/process/12_documentation_standards.md`
- `standards/process/13_git_version_control_standards.md`
- `standards/process/14_code_review_expectations.md`

