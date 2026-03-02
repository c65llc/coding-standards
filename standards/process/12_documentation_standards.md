# Documentation Standards

## 1. Architecture Decision Records (ADR)

### Purpose

Document significant architectural decisions, their context, and consequences.

### Format

Use Markdown files in `docs/adr/` directory. Number sequentially: `0001-decision-title.md`.

### Template

```markdown
# [Number]. [Title]

Date: YYYY-MM-DD

## Status

[Proposed | Accepted | Deprecated | Superseded]

## Context

[Describe the issue motivating this decision]

## Decision

[Describe the change that we're proposing or have agreed to implement]

## Consequences

[Describe the resulting context, after applying the decision]

## Alternatives Considered

[Describe alternative approaches and why they were rejected]
```

### Guidelines

* **When to Create:** For decisions that affect structure, dependencies, or significant technical choices.
* **Status Updates:** Update status when decisions are implemented, deprecated, or superseded.
* **Cross-References:** Link related ADRs. Reference issues/PRs when applicable.

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

* **Every PR:** Update changelog for user-facing changes
* **Categories:** Use standard categories. Be specific about changes
* **Links:** Link to issues and PRs: `[#123](https://github.com/user/repo/issues/123)`
* **Versioning:** Follow semantic versioning. Tag releases with version numbers

### Automated Changelog

* **Tool:** Use `conventional-changelog` or similar for automated generation
* **Source:** Generate from conventional commit messages
* **Review:** Always review and edit generated changelogs before release

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
* **Current vs. Historical:** Clearly distinguish current and historical documentation
* **Migration Guides:** Provide guides for breaking changes

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
* **Link Checking:** Validate internal and external links
* **Spell Checking:** Use automated spell checkers
* **Format Validation:** Ensure consistent formatting across documentation
