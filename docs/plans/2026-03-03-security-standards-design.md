# Security Guidelines Framework — Design

## Date: 2026-03-03

## Motivation

AI coding agents in this repository have no security-specific guidance. The existing security coverage in `core-standards.md` is 9 bullets with no examples, no severity model, and no tooling specifics beyond three audit commands. Agent configs (`.cursorrules`, `copilot-instructions.md`, `.aiderrc`, `.codexrc`, `GEMINI.md`) contain zero security violation detection rules.

This design creates a security standards framework inspired by [Omar Gate](https://github.com/marketplace/actions/omar-gate)'s P0-P3 severity model, ensuring AI agents prevent critical vulnerabilities during code generation and catch them during automated code review.

## Scope

- Code-level vulnerability prevention (injection, RCE, auth bypass, XSS, CSRF, dangerous functions, hardcoded secrets)
- Supply chain and configuration security (dependency CVEs, insecure configs, HTTP dependencies, workflow injection)
- P0-P3 severity classification with clear merge-blocking semantics

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| File placement | New `standards/security/` category | Cross-cutting concern deserves its own category, parallel to architecture/, languages/, process/ |
| Document structure | Single `sec-01_security_standards.md` | Matches existing one-doc-per-topic pattern; severity tags provide enforcement clarity |
| Severity model | P0-P3 (Omar Gate aligned) | P0/P1 block merge, P2 warning, P3 informational. Gives agents unambiguous enforcement guidance |
| Language integration | Central doc + language addenda | One cross-cutting doc for rules; brief security sections added to language standards for language-specific tooling |

## Design

### 1. New Standards Document

**File:** `standards/security/sec-01_security_standards.md`

Eight sections, each rule tagged with severity:

#### 1.1 Injection Prevention

- SQL Injection — parameterized queries only `[P0]`
- Command Injection — no eval/exec/system with user input `[P0]`
- XSS — output encoding, CSP headers `[P1]`
- SSRF — allowlist outbound URLs `[P1]`
- Template Injection — no user input in template expressions `[P1]`

#### 1.2 Authentication & Authorization

- Auth bypass patterns `[P0]`
- Session management requirements `[P1]`
- RBAC/authorization on every endpoint `[P1]`
- CSRF protection on state-changing endpoints `[P1]`

#### 1.3 Secrets Management

- Hardcoded credentials detection `[P0]`
- Secret scanning tooling per language `[P1]`
- Credential rotation policy `[P2]`
- .env file handling `[P1]`

#### 1.4 Dangerous Functions & Patterns

- Language-specific banned function lists `[P0]`
- Insecure deserialization `[P0]`
- Insecure random for security contexts `[P1]`

#### 1.5 Dependency & Supply Chain Security

- Known CVE scanning per language `[P1]`
- Lock file requirements `[P1]`
- HTTP dependency prohibition `[P2]`
- Dependency pinning `[P2]`

#### 1.6 Configuration Security

- TLS/HTTPS requirements `[P1]`
- Security headers (CSP, HSTS, X-Frame-Options) `[P1]`
- Debug mode / verbose error exposure `[P2]`
- Default credentials `[P0]`

#### 1.7 Data Protection

- Sensitive data logging prevention `[P1]`
- PII handling `[P2]`
- Encryption at rest / in transit `[P2]`

Each rule includes: severity tag, description, bad/good code example, tooling reference.

### 2. Agent Config Updates

All five agent configs get a new **Security Violation Detection** section:

```text
P0 (Critical — must block):
- Hardcoded secrets, API keys, or credentials
- SQL injection via string concatenation
- Command injection via eval/exec/system with untrusted input
- Insecure deserialization of untrusted data
- Authentication bypass patterns
- Default credentials in production configs

P1 (High — must block):
- Missing CSRF protection on state-changing endpoints
- XSS via unsanitized user input in HTML output
- SSRF via unvalidated URL inputs
- Missing authorization checks on endpoints
- Sensitive data in logs or error messages
- HTTP dependencies (non-HTTPS)
- Missing security headers (CSP, HSTS)
- Insecure random for security contexts

P2/P3 (Advisory — flag in review):
- Missing rate limiting on public endpoints
- Verbose error messages exposing internals
- Unpinned dependencies
- Missing encryption at rest for sensitive data
```

### 3. Integration with Existing Standards

**`core-standards.md`:** Replace sparse 9-bullet security section with summary referencing sec-01, keeping P0/P1 rules inline.

**`proc-03_code_review_expectations.md`:** Expand security checklist to reference P0-P3 model. P0/P1 findings explicitly block approval.

**Language standards addenda:** Add "Security" sections to standards lacking them, referencing the central doc plus language-specific tooling:

- Python: bandit, safety
- Java/Kotlin: SpotBugs, OWASP dependency-check
- TypeScript/JavaScript: eslint-plugin-security, npm audit
- Swift: general patterns (no major SAST)
- Dart: dart analyze security rules
- Rust: cargo audit, cargo deny
- Zig: general patterns
- Ruby/Rails: already covered (Brakeman in lang-11)

**`STRUCTURE.md`:** Add security/ directory.

**Agent config reference lists:** Add sec-01 to all standards file listings.

## Out of Scope

- Running Omar Gate as a GitHub Action (user explicitly does not want this)
- CI/CD pipeline configuration
- Penetration testing procedures
- Compliance frameworks (SOC2, HIPAA, PCI-DSS)
