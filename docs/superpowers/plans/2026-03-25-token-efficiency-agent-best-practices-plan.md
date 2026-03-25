# Token Efficiency & Agent Best Practices Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce per-agent-session token consumption in consumer projects by ~60% through composable content blocks, agent base templates, and language+role filtering at setup time.

**Architecture:** A `standards/shared/blocks/` directory holds atomic content fragments (~5-20 lines each). Six agent base templates hold agent-specific behavioral rules. The setup script assembles a single self-contained config per agent by concatenating base + relevant blocks based on detected languages and project role. No submodule traversal needed at runtime.

**Tech Stack:** Bash (setup/sync scripts), Markdown (blocks, templates, agent configs)

**Spec:** `docs/superpowers/specs/2026-03-25-token-efficiency-agent-best-practices-design.md`

---

## Task Group A: Content Blocks (Independent — no dependencies on other groups)

### Task 1: Create common content blocks

**Files:**

- Create: `standards/shared/blocks/architecture-core.md`
- Create: `standards/shared/blocks/testing-policy.md`
- Create: `standards/shared/blocks/security-summary.md`
- Create: `standards/shared/blocks/naming-conventions.md`
- Create: `standards/shared/blocks/git-workflow.md`
- Create: `standards/shared/blocks/documentation-policy.md`
- Reference: `standards/shared/core-standards.md` (source material)
- Reference: `standards/security/sec-01_security_standards.md` (source for security block)
- Reference: `standards/process/proc-02_git_version_control_standards.md` (source for git block)
- Reference: `standards/process/proc-01_documentation_standards.md` (source for docs block)

**Writing guidelines:** Imperative voice, no rationale, one concept per line, code examples only when pattern isn't obvious. Each block must be self-contained.

- [ ] **Step 1: Create `architecture-core.md` (~12 lines)**

```markdown
Apply Clean Architecture. Dependencies point inward only.
Layers: Domain (pure logic, no deps) → Application (use cases, interfaces) → Infrastructure (DB, API adapters) → Apps (entry points).
Follow SOLID strictly. Justify violations in code comments.
Single Responsibility: one reason to change per module.
Open/Closed: extend via interfaces, not modification.
Liskov: subtypes must be substitutable for their base types.
Interface Segregation: prefer small, focused interfaces.
Dependency Inversion: depend on abstractions, not concretions.
Prefer composition over inheritance.
Keep domain logic free of framework imports.
Repository interfaces live in Application; implementations in Infrastructure.
Entry points (CLI, HTTP, workers) live in Apps, never in packages/.
```

- [ ] **Step 2: Create `testing-policy.md` (~8 lines)**

```markdown
TDD required: write failing test → implement → refactor. No implementation before a failing test.
Minimum 95% line coverage across all modules. Domain layer requires 100%.
Every bug fix must include a regression test that reproduces the bug.
Test structure: Arrange → Act → Assert. One assertion concept per test.
Name tests descriptively: test_<behavior>_when_<condition>_then_<expected>.
Integration tests use real dependencies (databases, APIs) — do not mock infrastructure in integration tests.
Run full test suite before pushing. CI must pass before merge.
Coverage gate: PR blocked if coverage drops below threshold.
```

- [ ] **Step 3: Create `security-summary.md` (~15 lines)**

```markdown
P0 (Critical — blocks merge): hardcoded secrets/keys, SQL injection via string concat, command injection via shell exec, insecure deserialization, authentication bypass, default credentials in prod config.
P1 (High — blocks merge): missing CSRF protection, XSS via unescaped output, SSRF via user-controlled URLs, missing authorization checks, sensitive data in logs, HTTP dependencies where HTTPS required, missing security headers, insecure random for crypto.
P2 (Medium — fix before next release): verbose error messages exposing internals, missing rate limiting, overly permissive CORS, session fixation.
Never commit secrets, API keys, or credentials. Use environment variables or secret managers.
Validate and sanitize all external input at system boundaries.
Use parameterized queries — never string-concatenate SQL.
Escape all user content in HTML/template output.
Banned patterns: eval(), exec(), pickle.loads() on untrusted data, os.system(), subprocess with shell=True, Function() constructor, setTimeout/setInterval with string args.
Pin dependency versions. Run `npm audit` / `pip audit` / `cargo audit` in CI.
Review CVE databases for known vulnerabilities in dependencies quarterly.
Apply principle of least privilege to all service accounts and API tokens.
Log security events (auth failures, permission denials) but never log credentials or PII.
Use HTTPS everywhere. Set Strict-Transport-Security, Content-Security-Policy, X-Frame-Options headers.
```

- [ ] **Step 4: Create `naming-conventions.md` (~10 lines)**

```markdown
Python: snake_case (vars, functions, modules, files), PascalCase (classes), UPPER_SNAKE_CASE (constants), _leading_underscore (private).
JavaScript/TypeScript: camelCase (vars, functions), PascalCase (classes, components, types, interfaces), kebab-case (files, dirs), UPPER_SNAKE_CASE (constants).
Ruby: snake_case (vars, methods, files), PascalCase (classes, modules), UPPER_SNAKE_CASE (constants), trailing ? (predicates), trailing ! (mutators).
Java/Kotlin: camelCase (vars, methods), PascalCase (classes, interfaces), UPPER_SNAKE_CASE (constants), kebab-case (Kotlin files optional).
Swift: camelCase (vars, methods), PascalCase (types, protocols), UPPER_SNAKE_CASE (constants).
Rust: snake_case (vars, functions, modules), PascalCase (types, traits), UPPER_SNAKE_CASE (constants), SCREAMING_SNAKE_CASE (statics).
Dart: camelCase (vars, methods), PascalCase (classes), snake_case (files, libraries), UPPER_SNAKE_CASE (constants).
Boolean naming: prefix with is_, has_, should_, can_, was_, will_ (or equivalent in camelCase languages).
Architectural prefixes: lib_/app_ to distinguish library code from application code in ambiguous contexts.
Abbreviations: avoid unless domain-standard (e.g., URL, HTTP, ID are fine; msg, mgr, util are not).
```

- [ ] **Step 5: Create `git-workflow.md` (~10 lines)**

```markdown
Conventional Commits required: type(scope): subject. Types: feat, fix, refactor, test, docs, chore, perf, ci.
Branch naming: type/short-description (e.g., feat/add-user-auth, fix/login-redirect).
One task = one branch = one PR. No multi-feature branches.
Rebase before merge to keep linear history. Squash only for trivial multi-commit PRs.
PR requirements: linked issue, description of changes, test evidence, reviewer assigned.
Never force-push to main/master. Protect default branch with required reviews and CI checks.
Tag releases with semver: vMAJOR.MINOR.PATCH. Use annotated tags.
Commit messages: imperative mood ("Add feature" not "Added feature"), <72 char subject line.
Sign commits when possible (GPG or SSH signing).
Keep PRs small (<400 lines changed). Split large changes into stacked PRs.
```

- [ ] **Step 6: Create `documentation-policy.md` (~8 lines)**

```markdown
Document public APIs with docstrings/JSDoc. Internal code needs comments only where intent isn't obvious.
Create ADR (Architecture Decision Record) for: new dependencies, pattern changes, technology choices, deviations from standards.
Maintain CHANGELOG.md using Keep a Changelog format. Update on every user-facing change.
README must include: project purpose, setup instructions, key commands, architecture overview.
Code comments explain "why" not "what". Delete commented-out code — use git history instead.
Update docs in the same PR as code changes. Stale docs are worse than no docs.
API documentation must include request/response examples and error codes.
Use diagrams for complex flows (Mermaid in Markdown preferred).
```

- [ ] **Step 7: Verify all 6 common blocks exist and are within line budgets**

Run: `wc -l standards/shared/blocks/*.md`
Expected: Each file within ±2 lines of target (architecture-core ~12, testing-policy ~8, security-summary ~15, naming-conventions ~10, git-workflow ~10, documentation-policy ~8)

- [ ] **Step 8: Commit common blocks**

```bash
git add standards/shared/blocks/architecture-core.md standards/shared/blocks/testing-policy.md standards/shared/blocks/security-summary.md standards/shared/blocks/naming-conventions.md standards/shared/blocks/git-workflow.md standards/shared/blocks/documentation-policy.md
git commit -m "feat(blocks): add 6 common content blocks for agent config assembly

Condensed summaries of core standards for architecture, testing, security,
naming, git workflow, and documentation. Written in imperative style for
token-efficient agent consumption."
```

### Task 2: Create language content blocks

**Files:**

- Create: `standards/shared/blocks/lang-python.md`
- Create: `standards/shared/blocks/lang-typescript.md`
- Create: `standards/shared/blocks/lang-javascript.md`
- Create: `standards/shared/blocks/lang-java.md`
- Create: `standards/shared/blocks/lang-kotlin.md`
- Create: `standards/shared/blocks/lang-swift.md`
- Create: `standards/shared/blocks/lang-dart.md`
- Create: `standards/shared/blocks/lang-rust.md`
- Create: `standards/shared/blocks/lang-zig.md`
- Create: `standards/shared/blocks/lang-ruby.md`
- Create: `standards/shared/blocks/lang-rails.md`
- Reference: `standards/languages/lang-01_python_standards.md` through `lang-11_ruby_on_rails_standards.md`

- [ ] **Step 1: Create `lang-python.md` (~12 lines)**

Condense from `standards/languages/lang-01_python_standards.md`. Include: uv for package management, ruff for lint+format, mypy --strict required, pytest for testing, type hints on all public APIs, prefer dataclasses/Pydantic for data objects, async via asyncio (not threading), project structure conventions.

- [ ] **Step 2: Create `lang-typescript.md` (~12 lines)**

Condense from `standards/languages/lang-06_typescript_standards.md`. Include: pnpm for packages, prettier+eslint for format+lint, vitest or jest for testing, strict tsconfig (strict: true, noUncheckedIndexedAccess), prefer type over interface for unions, use zod for runtime validation, path aliases for clean imports.

- [ ] **Step 3: Create `lang-javascript.md` (~10 lines)**

Condense from `standards/languages/lang-07_javascript_standards.md`. Include: same tooling as TS where applicable, ESLint config, JSDoc for type annotations when not using TS, module system (ESM preferred), avoid var (use const/let).

- [ ] **Step 4: Create `lang-java.md` (~10 lines)**

Condense from `standards/languages/lang-02_java_standards.md`. Include: Gradle or Maven, JUnit 5, records for DTOs, Optional for nullable returns, Stream API for collections, sealed classes where applicable, checkstyle/spotless for formatting.

- [ ] **Step 5: Create `lang-kotlin.md` (~10 lines)**

Condense from `standards/languages/lang-03_kotlin_standards.md`. Include: Gradle KTS, data classes, coroutines for async, null safety (avoid !!), extension functions for utility, sealed classes for state, detekt for static analysis.

- [ ] **Step 6: Create `lang-swift.md` (~10 lines)**

Condense from `standards/languages/lang-04_swift_standards.md`. Include: SPM for packages, XCTest, structs over classes by default, protocol-oriented design, async/await for concurrency, SwiftLint, guard for early returns.

- [ ] **Step 7: Create `lang-dart.md` (~10 lines)**

Condense from `standards/languages/lang-05_dart_standards.md`. Include: pub for packages, Flutter test framework, freezed for immutable models, Riverpod/Bloc for state, dart_lints strict mode, null safety always enabled.

- [ ] **Step 8: Create `lang-rust.md` (~12 lines)**

Condense from `standards/languages/lang-08_rust_standards.md`. Include: cargo for packages, clippy for lints (deny warnings in CI), rustfmt for formatting, Result/Option for error handling (no unwrap in prod), thiserror for library errors / anyhow for applications, unsafe blocks require safety comment, #[must_use] on fallible functions.

- [ ] **Step 9: Create `lang-zig.md` (~10 lines)**

Condense from `standards/languages/lang-09_zig_standards.md`. Include: build.zig for build system, allocator pattern (accept allocator as param), explicit error handling, comptime for generics, no hidden allocations, test blocks in source files.

- [ ] **Step 10: Create `lang-ruby.md` (~10 lines)**

Condense from `standards/languages/lang-10_ruby_standards.md`. Include: Bundler for gems, RuboCop for lint, RSpec or Minitest for testing, prefer composition over mixins, freeze string literals, use keyword arguments for >2 params, Sorbet or RBS for type annotations.

- [ ] **Step 11: Create `lang-rails.md` (~12 lines)**

Condense from `standards/languages/lang-11_ruby_on_rails_standards.md`. Assumes `lang-ruby.md` content is present. Include: Rails conventions (REST, MVC), ActiveRecord validations on model, service objects for complex business logic, strong parameters always, database indexes for foreign keys, background jobs via Sidekiq/GoodJob, RSpec with FactoryBot.

- [ ] **Step 12: Verify all 11 language blocks exist**

Run: `ls -la standards/shared/blocks/lang-*.md | wc -l`
Expected: 11

- [ ] **Step 13: Commit language blocks**

```bash
git add standards/shared/blocks/lang-*.md
git commit -m "feat(blocks): add 11 language content blocks

Condensed language-specific standards for Python, TypeScript, JavaScript,
Java, Kotlin, Swift, Dart, Rust, Zig, Ruby, and Rails."
```

### Task 3: Create role content blocks

**Files:**

- Create: `standards/shared/blocks/role-service.md`
- Create: `standards/shared/blocks/role-library.md`
- Create: `standards/shared/blocks/role-app.md`
- Create: `standards/shared/blocks/role-data-pipeline.md`
- Reference: `standards/architecture/arch-04_data_versioning_and_migration_standards.md` (for data-pipeline role)
- Reference: `standards/architecture/arch-05_resilient_architecture_patterns.md` (for service/app roles)

- [ ] **Step 1: Create `role-service.md` (~10 lines)**

```markdown
Design APIs RESTfully: nouns for resources, HTTP verbs for actions, proper status codes.
Return structured error responses: { "error": { "code": "...", "message": "..." } }.
Implement health check endpoint (GET /health) returning service status and dependency health.
Add observability: structured logging (JSON), request tracing (correlation IDs), metrics (latency, error rate, throughput).
Rate limit public endpoints. Return 429 with Retry-After header.
Use circuit breakers for external service calls. Fail gracefully with fallback responses.
Implement graceful shutdown: stop accepting new requests, drain in-flight, close connections.
API versioning via URL path (/v1/) or Accept header. Never break existing clients.
Document all endpoints with OpenAPI/Swagger spec.
Idempotency keys for mutating operations (POST/PUT) to handle retries safely.
```

- [ ] **Step 2: Create `role-library.md` (~8 lines)**

```markdown
Public API surface must be minimal. Hide implementation details behind a clean interface.
Follow semver strictly: breaking changes = major, new features = minor, bug fixes = patch.
Minimize dependencies. Every dependency is a liability for consumers.
Document all public types, functions, and methods with examples in docstrings.
Provide a CHANGELOG.md updated on every release.
Export types explicitly. Do not rely on transitive exports.
Support the two most recent major versions of your language runtime.
Include a "Getting Started" section in README with install + basic usage example.
```

- [ ] **Step 3: Create `role-app.md` (~10 lines)**

```markdown
Separate UI rendering from business logic. Use presenters or view models.
State management: single source of truth, unidirectional data flow, immutable state updates.
Implement loading, error, and empty states for every data-driven view.
Accessibility: semantic HTML, ARIA labels, keyboard navigation, sufficient color contrast.
Responsive design via semantic state (isCompact, isWide) not pixel breakpoints.
Optimize initial load: code split routes, lazy load below-fold content, compress assets.
Handle offline/degraded network gracefully. Show cached data when possible.
Form validation: client-side for UX, server-side for security. Never trust client-only validation.
Error boundaries: catch and display errors per component tree, not globally.
User-facing strings must be externalizable for i18n readiness.
```

- [ ] **Step 4: Create `role-data-pipeline.md` (~10 lines)**

```markdown
All pipeline operations must be idempotent. Re-running produces the same result.
Version data schemas explicitly. Include version field in all data records.
Use additive-only schema changes (add fields, not remove/rename) for backwards compatibility.
Migration scripts must be reversible. Provide up() and down() for every migration.
Validate data at ingestion boundaries. Reject malformed records with clear error messages.
Partition and index data for query patterns. Document access patterns alongside schema.
Log pipeline run metadata: start time, end time, records processed, records failed, data lineage.
Test with representative production-scale data, not just toy datasets.
Implement dead-letter queues for failed records. Alert on dead-letter growth.
Checkpoint long-running pipelines. Resume from last checkpoint on failure.
```

- [ ] **Step 5: Commit role blocks**

```bash
git add standards/shared/blocks/role-*.md
git commit -m "feat(blocks): add 4 role content blocks

Project-type-specific standards for services, libraries, apps,
and data pipelines."
```

---

## Task Group B: Agent Base Templates (Independent — no dependencies on Group A)

### Task 4: Create Claude Code base template

**Files:**

- Create: `standards/agents/claude-code/base-claude-code.md`
- Reference: `standards/agents/claude-code/CLAUDE.md.template` (existing, to be replaced)

- [ ] **Step 1: Write `base-claude-code.md` (~30 lines)**

This template uses `{{PROJECT_NAME}}` and `{{KEY_COMMANDS}}` placeholders that the setup script will prompt the user for or leave as TODOs.

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

{{PROJECT_NAME}} — customize this section with your project description, purpose, and key architectural decisions.

## Key Commands

{{KEY_COMMANDS}}

## Conventions

- Conventional Commits: type(scope): subject — types: feat, fix, refactor, test, docs, chore, perf, ci
- Worktrees: use `git worktree add .claude/worktrees/<branch> -b <branch>` for isolated work
- Work tracking: GitHub Issues for all bugs, features, tech debt. Every TODO/FIXME references an issue.
- One task = one branch = one worktree = one PR. Work is not done until a PR exists.
- Never modify the root checkout from an automated agent session.

## How to Work

- Read relevant code before modifying. Understand existing patterns first.
- Prefer editing existing files over creating new ones.
- Keep changes minimal and focused. Do not refactor surrounding code unless asked.
- Run tests after every change. Do not claim success without passing tests.
- When blocked, explain what you tried and ask — do not retry the same approach.
```

- [ ] **Step 2: Commit**

```bash
git add standards/agents/claude-code/base-claude-code.md
git commit -m "feat(agents): add Claude Code base template

Replaces CLAUDE.md.template with a leaner base for block assembly."
```

### Task 5: Create Cursor base template

**Files:**

- Create: `standards/agents/cursor/base-cursor.md`
- Reference: `/Users/donaldalbrecht/Projects/coding_standards/.cursorrules` (current live config)
- Reference: `standards/architecture/arch-03_cursor_automation_standards.md` (interaction modes to absorb)

- [ ] **Step 1: Write `base-cursor.md` (~35 lines)**

Absorb interaction modes from arch-03. Condense `\address_feedback` from 183 lines to ~15 lines.

```markdown
# Cursor AI Standards

## Behavior

- Code-focused responses. No conversational filler.
- Output interface/structure first, confirm, then implement details.
- Always reference specific file paths when discussing code.
- Check standards before writing code. Apply language-specific conventions.
- Run tests after every change.

## Interaction Modes

Use these keywords at the start of a prompt to trigger specific workflows:

- **@new-feature**: Scaffold a vertical slice. Create Domain entity first → Repository interface → DTO → wait for approval before Infrastructure/UI.
- **@refactor**: Improve code without changing behavior. Apply SOLID, extract methods, fix naming, remove magic values.
- **@debug**: Analyze error → hypothesize → write reproduction test → implement fix.
- **@review**: Audit for architecture violations, missing error handling, testing gaps, security issues.

## Custom Commands

- `\pr` — Generate PR description from current changes. See `.cursor/commands/pr.md` for details.
- `\review` — Review current changes against standards. See `.cursor/commands/review.md` for details.
- `\address_feedback` — Process unresolved PR comments:
  1. Verify gh CLI installed, get current branch, check for open PR
  2. Fetch comments via `.standards/scripts/fetch-pr-comments.sh` (or `.cursor/commands/address_feedback.md`)
  3. For each comment: Ignore (explain why) | Analyze (investigate) | Apply Fix (implement + test) | Respond (comment back) | Skip
  4. Track progress, show summary at completion

## Context Handling

When a conversation spans multiple architectural layers, summarize changes in current context before moving to the next layer.
```

- [ ] **Step 2: Commit**

```bash
git add standards/agents/cursor/base-cursor.md
git commit -m "feat(agents): add Cursor base template

New template absorbs arch-03 interaction modes and condenses
address_feedback from 183 to ~15 lines."
```

### Task 6: Create Copilot base template

**Files:**

- Create: `standards/agents/copilot/base-copilot.md`
- Reference: `/Users/donaldalbrecht/Projects/coding_standards/.github/copilot-instructions.md` (current)

- [ ] **Step 1: Write `base-copilot.md` (~30 lines)**

```markdown
# GitHub Copilot Instructions

## Behavior

- Follow project standards for all code suggestions and reviews.
- Detect the language of the file being edited and apply language-specific conventions.
- Prefer simple, readable code over clever solutions.

## Code Suggestions

- Complete functions following existing patterns in the codebase.
- Include type annotations in suggestions (TypeScript, Python, etc.).
- Add error handling for all I/O operations and external calls.
- Respect existing import style and module organization.
- Do not suggest commented-out code or TODO placeholders.

## Chat & Slash Commands

- `/explain` — When explaining code, focus on the "why" behind design choices, not line-by-line narration.
- `/fix` — Diagnose root cause before suggesting fixes. Include a test that reproduces the issue.
- `/tests` — Generate tests following project conventions: descriptive names, Arrange-Act-Assert, one concept per test.

## Code Review (Copilot Review)

When reviewing pull requests:
- Check for standards compliance: naming, architecture layers, error handling, test coverage.
- Flag P0/P1 security issues as blocking. Flag P2 as suggestions.
- Verify test coverage for changed code paths.
- Check for breaking changes to public APIs.

## Workspace Context

- Read CLAUDE.md or project README for project-specific conventions before making suggestions.
- Respect .gitignore patterns — do not suggest changes to generated or vendored files.
```

- [ ] **Step 2: Commit**

```bash
git add standards/agents/copilot/base-copilot.md
git commit -m "feat(agents): add Copilot base template

Adds Copilot-specific slash command guidance, code review behavior,
and workspace context strategy."
```

### Task 7: Create Gemini base template

**Files:**

- Create: `standards/agents/gemini/base-gemini.md`
- Reference: `/Users/donaldalbrecht/Projects/coding_standards/.gemini/GEMINI.md` (current)

- [ ] **Step 1: Write `base-gemini.md` (~30 lines)**

```markdown
# Gemini CLI Instructions

## Workflow: Analyze → Plan → Execute (A-P-E)

For every task, follow this protocol:
1. **Analyze:** Read relevant files, understand current state, identify constraints.
2. **Plan:** State what you will do, which files you will touch, and expected outcome. Wait for confirmation on non-trivial changes.
3. **Execute:** Implement the plan. Run tests. Verify results match expectations.

## Checkpointing

- For multi-step tasks, checkpoint progress in `active_mission.log` at project root.
- Format: `[YYYY-MM-DD HH:MM] Step N: <description> — <status>`
- On resumption, read `active_mission.log` to restore context.

## Safety Constraints

- Never modify files in: .git/, node_modules/, .standards_tmp/, .secret, .tfstate
- Always preserve existing file numbering in standards directories.
- Run tests before and after changes. Do not claim success without passing tests.
- When uncertain, ask rather than guess. Incorrect changes are worse than no changes.
- Create a new branch for non-trivial work. Do not commit directly to main.

## Tool Usage

- Use shell commands for file operations, git, and running tests.
- Prefer reading files before modifying them.
- Use `git diff` to verify changes before committing.
- Keep commits atomic: one logical change per commit.
```

- [ ] **Step 2: Commit**

```bash
git add standards/agents/gemini/base-gemini.md
git commit -m "feat(agents): add Gemini base template

A-P-E workflow, checkpointing, safety constraints."
```

### Task 8: Create Aider base template

**Files:**

- Create: `standards/agents/aider/base-aider.md`
- Reference: `/Users/donaldalbrecht/Projects/coding_standards/.aiderrc` (current)

The Aider base template is special — it produces TWO files: `.aiderrc` (native config) and the instructions go into the assembled Markdown file.

- [ ] **Step 1: Write `base-aider.md` (~25 lines)**

This is the Markdown instructions portion (goes into `.aider-instructions.md`):

```markdown
# Aider Instructions

## Behavior

- Read relevant files before modifying. Use /add to include files in context.
- Prefer /edit for targeted changes to specific functions or sections.
- Use /ask when you need to understand code without modifying it.
- Apply diff mode for surgical edits. Avoid rewriting entire files.
- Run tests after every change. Verify with the project's test command before committing.

## Workflow

- One logical change per commit. Use conventional commit messages.
- Write tests first (TDD): create failing test → implement → verify pass → commit.
- Keep context window lean: /add only the files you need, /drop when done.
- For multi-file changes, plan the order: interfaces first, then implementations, then tests.

## Constraints

- Do not modify generated files, lock files, or vendored dependencies.
- Do not commit secrets, credentials, or .env files.
- When a change affects a public API, check all callers before modifying.
- If unsure about a change, explain your reasoning and ask for confirmation.
```

- [ ] **Step 2: Create Aider native config template**

Create `standards/agents/aider/aiderrc.template` — the `.aiderrc` file:

```yaml
# Aider configuration — generated by coding-standards setup
# See .aider-instructions.md for coding standards

model = claude-sonnet-4-20250514

read = .aider-instructions.md

# File exclusions
auto-lint = true
show-diffs = true

[file-ignore]
*.pyc
__pycache__
.git
node_modules
.standards_tmp
coverage
dist
build
.pytest_cache
.ruff_cache
.mypy_cache
```

- [ ] **Step 3: Commit**

```bash
git add standards/agents/aider/base-aider.md standards/agents/aider/aiderrc.template
git commit -m "feat(agents): add Aider base template (two-file model)

Aider uses .aiderrc for native config + .aider-instructions.md for
standards content, respecting Aider's key-value config format."
```

### Task 9: Create Codex base template (AGENTS.md format)

**Files:**

- Create: `standards/agents/codex/base-codex.md`
- Reference: `/Users/donaldalbrecht/Projects/coding_standards/.codexrc` (old format)

- [ ] **Step 1: Write `base-codex.md` (~25 lines)**

```markdown
# AGENTS.md

Instructions for OpenAI Codex CLI.

## Environment

- You are running in a sandboxed container. File system changes are isolated.
- Network access may be restricted. Prefer local operations.
- Interactive commands (prompts, TUIs) are not supported. Use non-interactive flags.

## Behavior

- Read project structure before making changes. Understand existing patterns first.
- Apply language-specific conventions for the file being edited.
- Run tests after every change using the project's test command.
- Write tests first when fixing bugs or adding features.

## Approval Mode

- In suggest mode: explain what you would change and why before making edits.
- In auto mode: make changes directly but keep commits atomic and well-described.
- Always use conventional commit messages: type(scope): subject.

## Constraints

- Do not modify generated files, lock files, or CI configuration without explicit request.
- Do not install new dependencies without explaining why they are needed.
- Keep changes minimal. Do not refactor surrounding code unless asked.
```

- [ ] **Step 2: Commit**

```bash
git add standards/agents/codex/base-codex.md
git commit -m "feat(agents): add Codex base template in AGENTS.md format

Replaces obsolete .codexrc with current OpenAI Codex CLI format.
Includes sandbox awareness, approval mode guidance."
```

---

## Task Group C: Setup Script & Language Detection (Depends on Groups A and B being complete)

### Task 10: Update `detect-languages.sh` with sub-detection

**Files:**

- Modify: `scripts/detect-languages.sh`

- [ ] **Step 1: Add TypeScript sub-detection**

After the existing `javascript` detection block (lines 33-38), add TypeScript sub-detection:

```bash
# typescript (sub-detection within javascript projects)
if [ -f "$PROJECT_ROOT/tsconfig.json" ] || find "$PROJECT_ROOT" -maxdepth 2 -name "*.ts" -o -name "*.tsx" 2>/dev/null | head -1 | grep -q .; then
    echo "typescript"
fi
```

- [ ] **Step 2: Add Rails sub-detection**

After the existing `ruby` detection block (lines 25-31), add Rails sub-detection:

```bash
# rails (sub-detection within ruby projects)
if [ -f "$PROJECT_ROOT/config/routes.rb" ] || ([ -f "$PROJECT_ROOT/Gemfile" ] && grep -q "rails" "$PROJECT_ROOT/Gemfile" 2>/dev/null); then
    echo "rails"
fi
```

- [ ] **Step 3: Add JVM sub-detection for Java vs Kotlin**

After the existing `jvm` detection block (lines 41-47), add sub-detection:

```bash
# java/kotlin sub-detection
if [ -f "$PROJECT_ROOT/build.gradle" ] || [ -f "$PROJECT_ROOT/build.gradle.kts" ] || [ -f "$PROJECT_ROOT/pom.xml" ]; then
    if find "$PROJECT_ROOT/src" -name "*.java" 2>/dev/null | head -1 | grep -q .; then
        echo "java"
    fi
    if find "$PROJECT_ROOT/src" -name "*.kt" -o -name "*.kts" 2>/dev/null | head -1 | grep -q .; then
        echo "kotlin"
    fi
fi
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n scripts/detect-languages.sh`
Expected: No output (valid syntax)

- [ ] **Step 5: Commit**

```bash
git add scripts/detect-languages.sh
git commit -m "feat(detect): add TypeScript, Rails, Java/Kotlin sub-detection

detect-languages.sh now outputs typescript, rails, java, kotlin as
separate keys alongside the parent language detection."
```

### Task 11: Create `assemble-config.sh` assembly script

**Files:**

- Create: `scripts/assemble-config.sh`

This is the core new script that assembles an agent config from base template + blocks.

- [ ] **Step 1: Write the assembly script**

```bash
#!/bin/bash
# Assemble an agent config from base template + content blocks.
#
# Usage: assemble-config.sh <agent> <blocks-dir> <base-template> <output-file> [block1 block2 ...]
#
# Arguments:
#   agent         - Agent name (claude-code, cursor, copilot, gemini, aider, codex)
#   blocks-dir    - Path to standards/shared/blocks/
#   base-template - Path to the base template file
#   output-file   - Path to write the assembled config
#   block1...     - Block filenames to include (e.g., architecture-core.md lang-python.md)

set -e

AGENT="$1"
BLOCKS_DIR="$2"
BASE_TEMPLATE="$3"
OUTPUT_FILE="$4"
shift 4
BLOCKS=("$@")

if [ -z "$AGENT" ] || [ -z "$BLOCKS_DIR" ] || [ -z "$BASE_TEMPLATE" ] || [ -z "$OUTPUT_FILE" ]; then
    echo "Usage: assemble-config.sh <agent> <blocks-dir> <base-template> <output-file> [blocks...]" >&2
    exit 1
fi

if [ ! -f "$BASE_TEMPLATE" ]; then
    echo "Error: Base template not found: $BASE_TEMPLATE" >&2
    exit 1
fi

if [ ! -d "$BLOCKS_DIR" ]; then
    echo "Error: Blocks directory not found: $BLOCKS_DIR" >&2
    exit 1
fi

# Extract project-specific section from existing file if present
PROJECT_SPECIFIC=""
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
if [ -f "$OUTPUT_FILE" ]; then
    if grep -qF "$SENTINEL" "$OUTPUT_FILE" 2>/dev/null; then
        PROJECT_SPECIFIC=$(sed -n "/$SENTINEL/,\$p" "$OUTPUT_FILE")
    elif ! grep -q "^# Assembled by coding-standards" "$OUTPUT_FILE" 2>/dev/null; then
        # File exists, was not assembled, has no sentinel — back it up
        BACKUP="${OUTPUT_FILE}.pre-standards-setup"
        cp "$OUTPUT_FILE" "$BACKUP"
        echo "⚠️  Backed up existing $OUTPUT_FILE to $BACKUP"
    fi
fi

# Start assembly
{
    echo "<!-- Assembled by coding-standards setup.sh — do not edit above the PROJECT-SPECIFIC marker -->"
    echo ""
    cat "$BASE_TEMPLATE"

    # Common blocks (in standard order)
    COMMON_BLOCKS=("architecture-core.md" "testing-policy.md" "security-summary.md" "naming-conventions.md" "git-workflow.md" "documentation-policy.md")
    for block in "${COMMON_BLOCKS[@]}"; do
        if [ -f "$BLOCKS_DIR/$block" ]; then
            SECTION_NAME=$(echo "$block" | sed 's/\.md$//' | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1')
            echo ""
            echo "## $SECTION_NAME"
            echo ""
            cat "$BLOCKS_DIR/$block"
        fi
    done

    # Language and role blocks (from arguments)
    LANG_HEADER_WRITTEN=false
    ROLE_HEADER_WRITTEN=false
    for block in "${BLOCKS[@]}"; do
        BLOCK_FILE="$BLOCKS_DIR/$block"
        if [ ! -f "$BLOCK_FILE" ]; then
            echo "Warning: Block not found: $BLOCK_FILE" >&2
            continue
        fi
        if [[ "$block" == lang-* ]] && [ "$LANG_HEADER_WRITTEN" = false ]; then
            echo ""
            echo "## Language Standards"
            echo ""
            LANG_HEADER_WRITTEN=true
        elif [[ "$block" == lang-* ]]; then
            echo ""
        fi
        if [[ "$block" == role-* ]] && [ "$ROLE_HEADER_WRITTEN" = false ]; then
            echo ""
            echo "## Project Type"
            echo ""
            ROLE_HEADER_WRITTEN=true
        fi
        LANG_NAME=$(echo "$block" | sed 's/^lang-//' | sed 's/^role-//' | sed 's/\.md$//' | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
        if [[ "$block" == lang-* ]]; then
            echo "### $LANG_NAME"
            echo ""
        fi
        cat "$BLOCK_FILE"
    done

    # Project-specific section
    echo ""
    if [ -n "$PROJECT_SPECIFIC" ]; then
        echo "$PROJECT_SPECIFIC"
    else
        echo "$SENTINEL — DO NOT EDIT THIS LINE -->"
        echo ""
        echo "<!-- Add project-specific instructions below this line. This section is preserved across re-assembly. -->"
    fi
} > "$OUTPUT_FILE"

echo "✅ Assembled $OUTPUT_FILE ($AGENT)"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/assemble-config.sh`

- [ ] **Step 3: Verify syntax**

Run: `bash -n scripts/assemble-config.sh`
Expected: No output (valid syntax)

- [ ] **Step 4: Commit**

```bash
git add scripts/assemble-config.sh
git commit -m "feat(scripts): add assemble-config.sh for block-based agent config assembly

Core assembly script: reads base template + content blocks, concatenates
with section headers, preserves project-specific sections via sentinel markers."
```

### Task 12: Rewrite `setup.sh` for block assembly

**Files:**

- Modify: `scripts/setup.sh`

This is the most complex task. The existing setup.sh (362 lines) needs significant restructuring to use block assembly instead of file copying.

- [ ] **Step 1: Add argument parsing for --role, --agents, --languages**

Add after the existing `set -e` and variable declarations (line 8):

```bash
# Parse arguments
ROLE="service"
AGENTS_OVERRIDE=""
LANGUAGES_OVERRIDE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --role)
            ROLE="$2"
            shift 2
            ;;
        --agents)
            AGENTS_OVERRIDE="$2"
            shift 2
            ;;
        --languages)
            LANGUAGES_OVERRIDE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done
```

- [ ] **Step 2: Add language-to-block mapping function**

```bash
# Map detected languages to block filenames
map_languages_to_blocks() {
    local DETECTED_LANGS="$1"
    local BLOCKS=()

    for lang in $DETECTED_LANGS; do
        case "$lang" in
            python)     BLOCKS+=("lang-python.md") ;;
            javascript) BLOCKS+=("lang-javascript.md") ;;
            typescript) BLOCKS+=("lang-typescript.md") ;;
            jvm)        BLOCKS+=("lang-java.md" "lang-kotlin.md") ;;
            java)       BLOCKS+=("lang-java.md") ;;
            kotlin)     BLOCKS+=("lang-kotlin.md") ;;
            ruby)       BLOCKS+=("lang-ruby.md") ;;
            rails)      BLOCKS+=("lang-rails.md" "lang-ruby.md") ;;
            rust)       BLOCKS+=("lang-rust.md") ;;
            swift)      BLOCKS+=("lang-swift.md") ;;
            dart)       BLOCKS+=("lang-dart.md") ;;
            zig)        BLOCKS+=("lang-zig.md") ;;
        esac
    done

    # Deduplicate
    printf '%s\n' "${BLOCKS[@]}" | sort -u | tr '\n' ' '
}
```

- [ ] **Step 3: Replace `setup_ai_agents` function with block assembly**

Rewrite the function to use `assemble-config.sh` instead of file copying. For each agent, call the assembly script with the appropriate base template and blocks (common + language + role).

The key change: instead of `cp "$AGENTS_DIR/copilot/..." "$PROJECT_ROOT/.github/..."`, call:

```bash
"$SCRIPT_DIR/assemble-config.sh" "copilot" "$BLOCKS_DIR" "$BASE" "$OUTPUT" $LANG_BLOCKS "role-${ROLE}.md"
```

Handle Aider specially: assemble `.aider-instructions.md` via blocks, and copy `aiderrc.template` to `.aiderrc`.
Handle Codex: output to `AGENTS.md` instead of `.codexrc`.

- [ ] **Step 4: Add `.standards-config` persistence**

After assembly, write the config file:

```bash
cat > "$PROJECT_ROOT/.standards-config" << EOF
# Generated by coding-standards setup.sh — used by sync-standards.sh
STANDARDS_ROLE=$ROLE
STANDARDS_LANGUAGES=$(echo $DETECTED_LANGS | tr ' ' ',')
STANDARDS_AGENTS=$(echo $ASSEMBLED_AGENTS | tr ' ' ',')
STANDARDS_VERSION=2.0.0
EOF
```

- [ ] **Step 5: Update .gitignore additions**

Add `.pre-standards-setup` backup files and `.standards-config` to the gitignore additions:

```bash
if ! grep -q ".pre-standards-setup" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    echo "*.pre-standards-setup" >> "$PROJECT_ROOT/.gitignore"
fi
if ! grep -q ".aider-instructions.md" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    # Don't ignore — this should be committed
    :
fi
```

- [ ] **Step 6: Verify syntax**

Run: `bash -n scripts/setup.sh`
Expected: No output

- [ ] **Step 7: Commit**

```bash
git add scripts/setup.sh
git commit -m "feat(setup): rewrite setup.sh for block-based config assembly

Setup now accepts --role, --agents, --languages flags. Uses
assemble-config.sh to build self-contained agent configs from
base templates + content blocks. Writes .standards-config for
reproducible sync."
```

### Task 13: Update `sync-standards.sh` for assembly-based sync

**Files:**

- Modify: `scripts/sync-standards.sh`

- [ ] **Step 1: Add `.standards-config` reading**

At the top of the sync function, read the config file if it exists:

```bash
if [ -f "$PROJECT_ROOT/.standards-config" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.standards-config"
    ROLE="${STANDARDS_ROLE:-service}"
    LANGS="${STANDARDS_LANGUAGES}"
    AGENTS="${STANDARDS_AGENTS}"
else
    echo "⚠️  No .standards-config found. Running auto-detection (default role: service)."
    echo "   Review .standards-config after sync and re-run if needed."
    ROLE="service"
    LANGS=""
    AGENTS=""
fi
```

- [ ] **Step 2: Replace `sync_ai_agents` with assembly-based sync**

Instead of copying files with `cmp -s` checks, re-run assembly using the same logic as `setup.sh`. Call `assemble-config.sh` for each agent.

- [ ] **Step 3: Add `.codexrc` deprecation warning**

```bash
if [ -f "$PROJECT_ROOT/.codexrc" ]; then
    echo "⚠️  .codexrc is deprecated. Codex now uses AGENTS.md."
    echo "   Your .codexrc has been preserved. Remove it when ready."
fi
```

- [ ] **Step 4: Verify syntax**

Run: `bash -n scripts/sync-standards.sh`
Expected: No output

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-standards.sh
git commit -m "feat(sync): update sync-standards.sh for assembly-based config sync

Reads .standards-config for role/language/agent selections.
Re-runs assemble-config.sh to rebuild agent configs from latest blocks.
Warns about deprecated .codexrc."
```

### Task 14: Update Makefile test targets

**Files:**

- Modify: `Makefile`

- [ ] **Step 1: Add assemble-config.sh to test-scripts target**

Add after line 63 (`bash -n scripts/build-claude-settings.sh`):

```makefile
	@echo "Testing assemble-config.sh..."
	@bash -n scripts/assemble-config.sh && echo "✅ assemble-config.sh syntax valid"
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "chore(makefile): add assemble-config.sh to test-scripts target"
```

---

## Task Group D: Standards Deduplication & Repo Cleanup (Independent — can run in parallel with C)

### Task 15: Deduplicate arch-01

**Files:**

- Modify: `standards/architecture/arch-01_project_standards_and_architecture.md`
- Reference: `standards/shared/core-standards.md`

- [ ] **Step 1: Read the full file to identify section boundaries**

Run: Read `standards/architecture/arch-01_project_standards_and_architecture.md` in full.

- [ ] **Step 2: Keep Section 1 (AI Behavior Guidelines), replace Sections 2-10 with cross-references**

Replace everything after Section 1 with:

```markdown
## 2–10. Core Standards

The following sections are maintained in [core-standards.md](../shared/core-standards.md) as the single source of truth:

- **Architecture** — Clean Architecture, layer responsibilities, dependency rule (Section 1)
- **Coding Standards** — SOLID, naming conventions, code style (Section 2)
- **Error Handling** — exception hierarchy, error types (Section 3)
- **Testing** — TDD, coverage targets, test structure (Section 4)
- **Dependencies** — management, pinning, auditing (Section 5)
- **Environment** — isolation, configuration (Section 6)
- **Version Control** — commits, branching, PRs (Section 7)
- **Documentation** — docstrings, ADRs, changelogs (Section 8)
- **Security** — P0-P2 severity model, banned patterns (Section 9)
- **Work Tracking** — GitHub Issues, TODO references (Section 10)
```

- [ ] **Step 3: Commit**

```bash
git add standards/architecture/arch-01_project_standards_and_architecture.md
git commit -m "refactor(standards): deduplicate arch-01 by referencing core-standards

Keep AI Behavior Guidelines (unique). Replace Sections 2-10 with
cross-references to core-standards.md. Reduces 253→~40 lines."
```

### Task 16: Delete arch-03 and distribute its content

**Files:**

- Delete: `standards/architecture/arch-03_cursor_automation_standards.md`
- Verify: Content is already absorbed into `standards/agents/cursor/base-cursor.md` (Task 5)
- Modify: `standards/process/proc-04_agent_workflow_standards.md` (merge context handling)

- [ ] **Step 1: Add context handling section to proc-04**

Append to proc-04 after the existing content:

```markdown
## Context Handling Across Layers

When agent work spans multiple architectural layers:
- Reference specific file paths when discussing code (e.g., `packages/domain/user.py`).
- Summarize changes in the current layer's context before moving to the next layer.
- Keep conversation context focused: avoid loading full files when only a section is relevant.
```

- [ ] **Step 2: Delete arch-03**

```bash
git rm standards/architecture/arch-03_cursor_automation_standards.md
```

- [ ] **Step 3: Commit**

```bash
git add standards/process/proc-04_agent_workflow_standards.md
git commit -m "refactor(standards): remove arch-03, distribute content

Cursor interaction modes → cursor base template (Task 5).
Context handling → proc-04 agent workflow standards."
```

### Task 17: Trim arch-05 duplicated sections

**Files:**

- Modify: `standards/architecture/arch-05_resilient_architecture_patterns.md`

- [ ] **Step 1: Read the full file**

Identify Section 1 (coverage gates — duplicates arch-02/core) and Section 6 (naming — duplicates arch-01/core).

- [ ] **Step 2: Replace duplicated sections with cross-references**

Section 1: Replace with "See [core-standards.md](../shared/core-standards.md) Section 4 for coverage requirements."
Section 6: Replace with "See [core-standards.md](../shared/core-standards.md) Section 2 for naming conventions."

Keep Sections 2-5 intact (pure render logic, semantic state, error layering, centralized paths — these are unique).

- [ ] **Step 3: Commit**

```bash
git add standards/architecture/arch-05_resilient_architecture_patterns.md
git commit -m "refactor(standards): remove duplicated sections from arch-05

Replace coverage gates (Section 1) and naming conventions (Section 6)
with cross-references to core-standards.md. Keep unique patterns."
```

### Task 18: Extract git aliases from proc-02

**Files:**

- Create: `docs/reference/git-aliases.md`
- Modify: `standards/process/proc-02_git_version_control_standards.md`

- [ ] **Step 1: Read proc-02 to find the aliases section**

Identify the git aliases catalog (expected around Section 6.4, ~60 lines).

- [ ] **Step 2: Extract aliases to `docs/reference/git-aliases.md`**

Move the alias catalog content to the new file with a title header.

- [ ] **Step 3: Replace in proc-02 with cross-reference**

Replace the extracted section with:

```markdown
### Git Aliases

See [Git Aliases Reference](../../docs/reference/git-aliases.md) for the full alias catalog. Run `scripts/setup-git-aliases.sh` to install.
```

- [ ] **Step 4: Commit**

```bash
git add docs/reference/git-aliases.md standards/process/proc-02_git_version_control_standards.md
git commit -m "refactor(standards): extract git aliases from proc-02 to reference doc

Moves 60-line alias catalog to docs/reference/git-aliases.md.
proc-02 links to it."
```

### Task 19: Remove banned-functions lists from language docs

**Files:**

- Modify: `standards/languages/lang-01_python_standards.md`
- Modify: `standards/languages/lang-06_typescript_standards.md`
- Modify: `standards/languages/lang-08_rust_standards.md`
- (Check other language docs for similar lists)

- [ ] **Step 1: Read security sections of each language doc**

Identify inline banned-functions lists in each file.

- [ ] **Step 2: Replace with cross-references**

Replace each banned-functions list with:

```markdown
See [sec-01_security_standards.md](../security/sec-01_security_standards.md) Section 4 for the complete banned-functions list with language-specific examples.
```

- [ ] **Step 3: Commit**

```bash
git add standards/languages/lang-01_python_standards.md standards/languages/lang-06_typescript_standards.md standards/languages/lang-08_rust_standards.md
git commit -m "refactor(standards): replace inline banned-functions with sec-01 references

Language docs now link to sec-01 for banned functions instead of
duplicating the lists."
```

### Task 20: Update this repo's own agent configs

**Files:**

- Delete: `.codexrc` (replace with `AGENTS.md`)
- Create: `AGENTS.md` at repo root (Codex format for this repo)
- Modify: `standards/README.md` (update to reflect new structure)

- [ ] **Step 1: Create `AGENTS.md` for this repo**

This is the repo's own Codex config (not a template — the actual config for this codebase):

```markdown
# AGENTS.md

Instructions for OpenAI Codex CLI working in this coding standards repository.

## Environment

Sandboxed container. No interactive commands. Use non-interactive flags.

## This Repository

This is a **coding standards repository** — Markdown docs, bash scripts, and agent configs. Not an application.

## Key Commands

- `make test-scripts` — Validate bash script syntax
- `make test` — Run all tests
- `make lint` — Lint markdown files
- `bash -n scripts/<name>.sh` — Check individual script syntax

## Conventions

- Conventional Commits: type(scope): subject
- Standards numbering: category-based prefixes (arch-XX, lang-XX, proc-XX, sec-XX)
- Shell scripts must pass `bash -n` syntax validation
- When modifying shared standards in core-standards.md, verify agent configs stay aligned
```

- [ ] **Step 2: Remove `.codexrc`**

```bash
git rm .codexrc
```

- [ ] **Step 3: Update `standards/README.md` to document new blocks/ directory**

Add a section describing the blocks system and assembly process.

- [ ] **Step 4: Commit**

```bash
git add AGENTS.md standards/README.md
git commit -m "feat(codex): migrate from .codexrc to AGENTS.md, update standards README

Replace obsolete .codexrc with AGENTS.md for current OpenAI Codex CLI.
Document new blocks/ directory and assembly system in standards README."
```

---

## Task Group E: Validation & Integration Testing

### Task 21: Run full test suite

**Files:**

- Reference: `Makefile`

- [ ] **Step 1: Run `make test-scripts`**

Run: `make test-scripts`
Expected: All scripts pass `bash -n` syntax validation, including new `assemble-config.sh`.

- [ ] **Step 2: Run `make test`**

Run: `make test`
Expected: All tests pass (test-scripts + test-bootstrap + test-gh-task).

- [ ] **Step 3: Manual assembly test**

Test the assembly script end-to-end by assembling a Claude Code config for a hypothetical Python/TypeScript service:

```bash
./scripts/assemble-config.sh claude-code \
    standards/shared/blocks \
    standards/agents/claude-code/base-claude-code.md \
    /tmp/test-claude-md.md \
    lang-python.md lang-typescript.md role-service.md
```

Verify:

- Output file exists and is <150 lines
- Contains base template content
- Contains all 6 common blocks
- Contains Python and TypeScript language blocks
- Contains service role block
- Contains project-specific sentinel marker
- No broken references or missing sections

```bash
wc -l /tmp/test-claude-md.md
grep -c "^## " /tmp/test-claude-md.md
grep "PROJECT-SPECIFIC" /tmp/test-claude-md.md
```

- [ ] **Step 4: Test idempotency**

Run the same assembly command again:

```bash
./scripts/assemble-config.sh claude-code \
    standards/shared/blocks \
    standards/agents/claude-code/base-claude-code.md \
    /tmp/test-claude-md.md \
    lang-python.md lang-typescript.md role-service.md
```

Verify output is identical:

```bash
diff /tmp/test-claude-md.md /tmp/test-claude-md-2.md
```

- [ ] **Step 5: Test project-specific preservation**

Add custom content after the sentinel in the test file, then re-run assembly:

```bash
echo "## My Custom Section" >> /tmp/test-claude-md.md
echo "Project-specific rule here" >> /tmp/test-claude-md.md
```

Re-run assembly, verify custom content is preserved.

### Task 22: Final commit and summary

- [ ] **Step 1: Verify no broken references**

```bash
# Check that all block files exist
ls standards/shared/blocks/*.md | wc -l
# Expected: 21 (6 common + 11 language + 4 role)

# Check that all base templates exist
ls standards/agents/*/base-*.md | wc -l
# Expected: 6

# Check arch-03 is deleted
ls standards/architecture/arch-03* 2>/dev/null
# Expected: no output

# Check .codexrc is gone, AGENTS.md exists
ls .codexrc 2>/dev/null
# Expected: no output
ls AGENTS.md
# Expected: AGENTS.md
```

- [ ] **Step 2: Final `make test`**

Run: `make test`
Expected: All pass.

---

## Execution Order Summary

| Group | Tasks | Dependencies | Can Parallelize? |
|---|---|---|---|
| A (Blocks) | 1, 2, 3 | None | Yes — all 3 tasks within group are independent |
| B (Templates) | 4, 5, 6, 7, 8, 9 | None | Yes — all 6 tasks are independent |
| C (Scripts) | 10, 11, 12, 13, 14 | Groups A + B complete | Sequential within group (10→11→12→13→14) |
| D (Dedup) | 15, 16, 17, 18, 19, 20 | None | Yes — all 6 tasks are independent |
| E (Validation) | 21, 22 | Groups A + B + C + D complete | Sequential (21→22) |

**Maximum parallelism:** Groups A, B, and D can all run simultaneously. Group C starts when A+B finish. Group E runs last.
