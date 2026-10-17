# Documentation Standards

## 1. Architecture Decision Records (ADR)

### Purpose

Document significant architectural decisions, their context, and consequences.

### Format

Use Markdown files in `docs/adr/` directory. Number sequentially: `0001-decision-title.md`.

Metadata is a **bullet list directly under the title** — not a `## Status` heading or a bare `Date:` line — so humans and the `doc-lint` check find it without parsing section structure. Legacy ADRs that use `## Status` / `## Date` headings still pass the lint; convert them when you next touch them.

### Template

Copy [`templates/docs/adr.md`](https://github.com/c65llc/coding-standards/blob/main/templates/docs/adr.md):

```markdown
# ADR NNNN: [Title]

- **Status:** Proposed
- **Date:** YYYY-MM-DD
- **Related:** #123, `docs/specs/YYYY-MM-DD-topic-design.md`
- **Supersedes:** —
- **Extends:** —

## Context

[The issue motivating this decision, with evidence]

## Decision

[The change we are making. Name a rejected alternative inline when it matters]

## Consequences

[The resulting context: what gets easier, harder, or impossible; follow-ups spawned]
```

### Required Fields

| Field | Form | Values |
|-------|------|--------|
| Status | `- **Status:**` | `Proposed`, `Accepted`, `Deprecated`, `Superseded by ADR NNNN` |
| Date | `- **Date:**` | ISO `YYYY-MM-DD` — the date the status last changed |
| Related | `- **Related:**` | Issues, PRs, specs, review-finding ids (`R17`, `M-3`) |
| Supersedes / Extends | `- **Supersedes:**`, `- **Extends:**` | ADR numbers or `—`. *Supersedes* retires the older ADR (set its status to `Superseded by ADR NNNN`); *Extends* refines it and leaves it Accepted |
| Context, Decision, Consequences | `##` headings | Required sections. An `Alternatives Considered` section is optional — prefer one inline sentence in Decision |

### Guidelines

* **When to Create:** For decisions that affect structure, dependencies, or significant technical choices.
* **Status Updates:** Update status (and Date) when decisions are implemented, deprecated, or superseded.
* **Cross-References:** Link related ADRs. Reference issues/PRs when applicable.
* **Root-Cause Classes:** When an ADR closes a recurring class of defect (e.g. "UI feedback loop — late async response overwrote newer state"), name the class in Consequences. Over time `docs/adr/` doubles as a design-decision ledger that reviewers cite by number.
* **Lint:** `make lint-standards` runs `doc-lint`, which fails an ADR missing Status, Date, Context, Decision, or Consequences, and fails any relative Markdown link that does not resolve (§10).

## 2. Code Documentation

### Inline Comments

* **Purpose:** Explain "why", not "what". Code should be self-documenting.
* **Style:** Use language-specific comment syntax. Keep comments concise.
* **Complex Logic:** Document non-obvious algorithms, business rules, and workarounds.

### API Documentation

* **Public APIs:** All public functions, classes, methods, and interfaces must be documented.
* **Format:** Use language-standard documentation format (JSDoc, docstrings, JavaDoc, rustdoc).
* **Required Tags:** Include parameters, return values, exceptions/errors, and examples.

### Example Standards

**TypeScript/JavaScript:**

```typescript
/**
 * Creates a new user with validated email address.
 *
 * @param email - Valid email address (must match RFC 5322)
 * @param name - User's full name (non-null, non-empty)
 * @returns New User entity instance
 * @throws {InvalidEmailError} If email format is invalid
 */
```

**Python:**

```python
def create_user(email: str, name: str) -> User:
    """Create a new user with validated email address.

    Args:
        email: Valid email address (must match RFC 5322)
        name: User's full name (non-null, non-empty)

    Returns:
        User entity instance.

    Raises:
        InvalidEmailError: If email format is invalid.
    """
```

## 3. Usage Documentation

### README Files

Every package and application must include a `README.md` with:

* **Purpose:** What the component does
* **Installation:** Setup instructions
* **Usage:** Basic usage examples
* **Configuration:** Required environment variables and settings
* **Development:** How to contribute or extend

### API Usage Guides

* **Location:** `docs/usage/` directory
* **Format:** Markdown with code examples
* **Sections:** Quick start, common patterns, advanced usage, troubleshooting

### CLI Documentation

* **Help Text:** Comprehensive `--help` output for all commands
* **Man Pages:** Generate man pages for complex CLIs
* **Examples:** Include practical examples in help text

## 4. Changelog Management

### Format

Use [Keep a Changelog](https://keepachangelog.com/) format in `CHANGELOG.md` at project root.

### Structure

```markdown
# Changelog

## [Unreleased]

### Added
- New features

### Changed
- Changes to existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Removed features

### Fixed
- Bug fixes

### Security
- Security vulnerability fixes
```

### Guidelines

* **Every PR (manual mode only):** When the project has no release automation, update the changelog for user-facing changes. Do NOT hand-edit a shared `## [Unreleased]` block when releases are automated — see "Automated Releases" below.
* **Categories:** Use standard categories. Be specific about changes
* **Links:** Link to issues and PRs: `[#123](https://github.com/user/repo/issues/123)`
* **Versioning:** Follow semantic versioning. Tag releases with version numbers

### Automated Changelog

* **Tool:** Use `conventional-changelog` or similar for automated generation
* **Source:** Generate from conventional commit messages
* **Review:** Always review and edit generated changelogs before release

### Automated Releases

When a project uses an automated release tool (`semantic-release`, `release-please`, Changesets, etc.), the changelog and release notes are **generated** — contributors MUST NOT hand-maintain a shared `## [Unreleased]` block per PR.

* **Why:** Under parallel development, every PR editing the same first line of `### Added`/`### Changed`/`### Fixed` produces a predictable `CHANGELOG.md` merge conflict on each batch. Generated notes (or per-PR fragments) eliminate it.
* **Preferred approaches:**
  * **Commit-message-driven** (`semantic-release`, `release-please`): notes are generated from the git history. Keep `CHANGELOG.md` either generated at release time (`@semantic-release/changelog`) or omit the per-PR manual section entirely.
  * **Fragment-driven** (Changesets): one changeset file per PR under `.changeset/`, collected at release. Notes derive from the fragments, not from commit messages.
* **Match enforcement to the model:** for commit-message-driven automation, Conventional Commits become load-bearing — enforce the commit convention (commitlint / hook). For fragment-driven automation, the gate is instead that each user-facing PR includes a changeset fragment (enforce via a `changeset` status check).

## 5. Project Documentation

### Project Overview

* **Location:** `docs/README.md` or root `README.md`
* **Contents:** Project purpose, architecture overview, getting started guide
* **Audience:** New contributors and users

### Architecture Documentation

* **Location:** `docs/architecture/`
* **Contents:** System design, component diagrams, data flow, deployment architecture
* **Format:** Markdown with diagrams (Mermaid, PlantUML, or images)

### Development Guides

* **Location:** `docs/development/`
* **Contents:** Setup instructions, development workflow, testing guidelines, contribution guide
* **Audience:** Developers working on the project

### Deployment Documentation

* **Location:** `docs/deployment/`
* **Contents:** Deployment procedures, environment configuration, rollback procedures
* **Security:** Never include secrets or credentials

## 6. User Documentation

### User Guides

* **Location:** `docs/user-guide/` or separate documentation site
* **Contents:** Feature documentation, tutorials, FAQs
* **Format:** Markdown, HTML, or documentation framework (MkDocs, Docusaurus)

### Tutorials

* **Structure:** Step-by-step guides with clear outcomes
* **Examples:** Include working code examples
* **Prerequisites:** Clearly state required knowledge and setup

### API Reference

* **Generation:** Auto-generate from code documentation
* **Tools:** Use language-specific tools (Sphinx, JSDoc, rustdoc, JavaDoc)
* **Hosting:** Publish to documentation site or include in repository

## 7. Project Blog

### Purpose

* **Announcements:** Release notes, major feature announcements
* **Technical Deep Dives:** Architecture decisions, implementation details
* **Community:** Team updates, community highlights

### Content Guidelines

* **Frequency:** Regular but not mandatory (monthly or per major release)
* **Style:** Technical but accessible. Include code examples and diagrams
* **Format:** Markdown in `docs/blog/` or separate blog repository
* **Metadata:** Include author, date, tags, and categories

### Blog Structure

```text
docs/blog/
├── 2024/
│   ├── 01-15-release-1.0.0.md
│   └── 02-20-architecture-deep-dive.md
└── index.md
```

## 8. Project Website

### Purpose

* **Landing Page:** Project overview, key features, quick start
* **Documentation:** Hosted user and developer documentation
* **Community:** Links to resources, contribution guide, code of conduct

### Technology

* **Static Site:** Use static site generators (Hugo, Jekyll, Docusaurus, MkDocs)
* **Hosting:** GitHub Pages, Netlify, Vercel, or custom hosting
* **CI/CD:** Auto-deploy from documentation changes

### Content

* **Homepage:** Clear value proposition, installation instructions, examples
* **Documentation:** Full user and developer documentation
* **Blog:** Project blog posts and announcements
* **Community:** Contribution guidelines, code of conduct, contact information

## 9. Documentation Maintenance

### Review Process

* **Code Reviews:** Documentation changes reviewed alongside code
* **Regular Audits:** Quarterly review of documentation accuracy
* **Outdated Content:** Mark deprecated content clearly. Remove after deprecation period

### Versioning

* **Documentation Versions:** Tag documentation with project versions
* **Current vs. Historical:** Clearly distinguish current and historical documentation (see below)
* **Migration Guides:** Provide guides for breaking changes

### Docs Index: Live vs. Historical

Every `docs/` tree with more than a handful of documents keeps an index (`docs/README.md` or `docs/index.md`) listing each document with a **Status** column:

| Status | Meaning | Edit policy |
|--------|---------|-------------|
| `live` | Describes current behavior; maintained alongside the code | Edit in the PR that changes the behavior |
| `historical` | Point-in-time record: implemented specs, plans, verification docs, superseded ADRs | Never rewritten. Add a dated note at the top if context is needed ("Superseded by …") |

Rules:

* A new document is added to the index **in the PR that creates it**, with its status.
* Changing a document's status (spec `Draft` → `Implemented`, plan `Active` → `Done`) flips its index row to `historical` in the same PR.
* Agents and readers take current truth from `live` documents only; `historical` documents are provenance. A document that is neither is deleted or moved.

### Accessibility

* **Language:** Clear, concise language. Avoid jargon when possible
* **Structure:** Use headings, lists, and formatting for readability
* **Examples:** Include diverse, realistic examples
* **Search:** Implement search functionality for large documentation sites

## 10. Documentation Tools

### Recommended Tools

* **Markdown Editors:** VS Code, Typora, or any Markdown-capable editor
* **Diagram Tools:** Mermaid (text-based), PlantUML, or draw.io
* **Documentation Generators:**
  * Python: Sphinx
  * TypeScript/JavaScript: TypeDoc, JSDoc
  * Rust: rustdoc
  * Java: JavaDoc
* **Static Site Generators:** MkDocs, Docusaurus, Hugo, Jekyll

### Automation

* **CI/CD:** Generate and deploy documentation automatically
* **Link Checking:** Validate internal and external links. `make lint-standards` runs `doc-lint` (`scripts/lint-checks/common/doc-lint.sh`), which fails on relative Markdown links that do not resolve and on ADRs missing required fields (§1); fenced code and inline code are ignored
* **Spell Checking:** Use automated spell checkers
* **Format Validation:** Ensure consistent formatting across documentation

## 11. Spec, Plan, Design-Pass and Verification Documents

Non-trivial work leaves a paper trail a reader can follow from "why" to "what shipped". Templates live in [`templates/docs/`](https://github.com/c65llc/coding-standards/tree/main/templates/docs) (`.standards/templates/docs/` when installed as a submodule); copy, fill, and add each document to the docs index (§9).

| Document | Location | Required sections | Lifecycle |
|----------|----------|-------------------|-----------|
| Design spec — [`spec.md`](https://github.com/c65llc/coding-standards/blob/main/templates/docs/spec.md) | `docs/specs/YYYY-MM-DD-<topic>-design.md` | Purpose, Success, Non-goals, Anti-goals, Architecture, Errors, Testing, Left to the plan | `live` while Draft/Agreed → `historical` once Implemented |
| Implementation plan — [`plan.md`](https://github.com/c65llc/coding-standards/blob/main/templates/docs/plan.md) | `docs/plans/YYYY-MM-DD-<topic>-plan.md` | Goal, Architecture, Global Constraints, Review Focus, phased checkbox tasks, PR map, Execution | `historical` from the first commit: tick boxes, never rewrite |
| Design pass (UI) — [`design-pass.md`](https://github.com/c65llc/coding-standards/blob/main/templates/docs/design-pass.md) | `docs/design/YYYY-MM-DD-<surface>.md` | Identity prompts, Hard constraints, Deliverables table, State inventory | `live` until Built → `historical` |
| Verification — [`verification.md`](https://github.com/c65llc/coding-standards/blob/main/templates/docs/verification.md) | `docs/<feature>-verification.md` | Tests run (counts), Coverage per module, What was NOT verified, Residual risk | `historical`; one per feature PR |

### Rules

* **Spec before plan, plan before code** for non-trivial work: a new feature, a change that crosses architectural layers, a migration. Trivial fixes go straight from issue to PR.
* **"Left to the plan" is the explicit hand-off.** The plan may decide ordering, PR boundaries and file names; it may not silently change the spec's Architecture or cross an Anti-goal. If it must, reopen the spec first.
* **Design pass precedes UI code.** The state inventory (empty / loading / error / streaming / sync paused / runner unavailable / pending write) is the checklist that [proc-04 §7](./proc-04_agent_workflow_standards.md#7-ui-change-validation) later validates the build against.
* **Verification docs say what was NOT verified.** A green pipeline is evidence, not proof. Record test counts and per-module coverage from tool output, then name every gap and its residual risk.
* **Reference review-finding ids.** When a review tool or reviewer assigns ids (`R17`, `M-3`), cite them in the commit body and in the ADR/spec `Related` field so a fix can be traced to the finding that prompted it.
* **Projects on the `superpowers` workflow** keep specs in `docs/superpowers/specs/` and plans in `docs/superpowers/plans/`; the template content is identical.
