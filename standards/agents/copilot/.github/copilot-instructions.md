# GitHub Copilot Instructions

You are an AI coding assistant working within a project that follows strict architectural and coding standards. You MUST adhere to all standards documents in this repository.

## Core Standards

This project follows comprehensive development standards. Reference these documents:

### Architecture & Standards
- `standards/architecture/00_project_standards_and_architecture.md` - Core architecture, SOLID principles, naming conventions
- `standards/architecture/01_automation_standards.md` - Makefile targets and automation requirements
- `standards/shared/core-standards.md` - Shared core standards

### Language-Specific Standards
- `standards/languages/03_python_standards.md` - Python (poetry/uv, black, ruff, mypy, pytest)
- `standards/languages/04_java_standards.md` - Java (Gradle/Maven, Java 17+, JUnit 5)
- `standards/languages/05_kotlin_standards.md` - Kotlin (Gradle, ktlint, detekt, MockK)
- `standards/languages/06_swift_standards.md` - Swift (SPM, swiftformat, XCTest)
- `standards/languages/07_dart_standards.md` - Dart (pub, dart format, test package)
- `standards/languages/08_typescript_standards.md` - TypeScript (pnpm, prettier, eslint, vitest, strict mode)
- `standards/languages/09_javascript_standards.md` - JavaScript (pnpm, prettier, eslint, vitest)
- `standards/languages/10_rust_standards.md` - Rust (cargo, rustfmt, clippy, Result<T, E>)
- `standards/languages/11_zig_standards.md` - Zig (zig build, zig fmt, manual memory management)

### Process Standards
- `standards/process/12_documentation_standards.md` - ADR, code docs, changelog, user docs
- `standards/process/13_git_version_control_standards.md` - Git workflow, commits, branching
- `standards/process/14_code_review_expectations.md` - Code review process and expectations

## Non-Negotiable Requirements

These mandates apply to ALL code changes, regardless of scope or urgency:

1. **Test-Driven Development (TDD) is mandatory.** Write failing tests before implementation code. Red → Green → Refactor. No exceptions except thin UI rendering layers, generated code, and one-off scripts.
2. **95% test coverage is the absolute minimum** for any module, in any layer. Domain must reach 100%. Bug fixes must include regression tests.
3. **Python code must be strongly typed throughout.** Every function, method, variable, and class attribute requires type annotations. `mypy --strict` must pass with zero errors.
4. **Build for automated regression and local full-stack testing.** Tests must run locally without external dependencies. Use test containers and in-memory substitutes.
5. **Track all work as GitHub Issues** (or the project's configured tracker). Every bug, feature, tech debt item, and follow-up must have an issue. Every `TODO`/`FIXME` in code must reference an issue number. Never silently defer work.

## Behavior Rules

1. **Always check relevant standards** before making changes:
   - Architecture decisions → `standards/architecture/00_project_standards_and_architecture.md`
   - Language-specific code → corresponding language standards file in `standards/languages/`
   - Documentation → `standards/process/12_documentation_standards.md`
   - Git operations → `standards/process/13_git_version_control_standards.md`

2. **Enforce standards automatically:**
   - Check naming conventions match language standards
   - Verify architecture layer dependencies (Domain → Application → Infrastructure)
   - Ensure error handling follows language patterns
   - Validate test coverage requirements

3. **Documentation requirements:**
   - Update code documentation for public APIs
   - Create ADRs for architectural decisions
   - Update CHANGELOG.md for user-facing changes
   - Follow documentation format from `standards/process/12_documentation_standards.md`

4. **Git commit standards:**
   - Use Conventional Commits format from `standards/process/13_git_version_control_standards.md`
   - Ensure commit messages follow: `type(scope): subject`
   - Reference issues/PRs in commit footer

## Language Detection

When working with code, automatically detect the language and apply the corresponding standards file:
- `.py` files → `standards/languages/03_python_standards.md`
- `.java` files → `standards/languages/04_java_standards.md`
- `.kt` files → `standards/languages/05_kotlin_standards.md`
- `.swift` files → `standards/languages/06_swift_standards.md`
- `.dart` files → `standards/languages/07_dart_standards.md`
- `.ts`, `.tsx` files → `standards/languages/08_typescript_standards.md`
- `.js`, `.jsx` files → `standards/languages/09_javascript_standards.md`
- `.rs` files → `standards/languages/10_rust_standards.md`
- `.zig` files → `standards/languages/11_zig_standards.md`

## Response Style

- **Tone:** Terse, objective, professional
- **Code-focused:** No conversational filler
- **Iterative:** Output interface/structure first, confirm, then implement details
- **Reference files:** Always reference specific file paths when discussing code

## Violation Detection

When reviewing code, automatically check for:
- **TDD compliance** — tests committed before or alongside implementation
- **Coverage below 95%** in any modified module
- **Untyped Python code** — all functions, methods, and variables must have type annotations
- **Missing regression tests** for bug fixes
- Architecture violations (Domain importing Infrastructure)
- Naming convention mismatches
- Missing error handling
- Documentation gaps
- Git commit message format issues

If violations are detected, suggest fixes referencing the specific standards document.

## Code Suggestions

When providing code suggestions:
1. Follow the architecture layer structure (Domain → Application → Infrastructure)
2. Use language-specific naming conventions
3. Include proper error handling
4. Add type hints/annotations where required
5. Suggest test cases for new functionality
6. Reference relevant standards documents in comments when appropriate

## Pull Request Assistance

When helping with pull requests:
- Review for standards compliance
- Check commit message format
- Verify test coverage
- Ensure documentation is updated
- Validate architecture layer dependencies



