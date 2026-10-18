---
name: security-gate
description: Scan code for P0/P1 security violations using banned function lists and pattern detection
---

# Security Gate

Scan the current project for security violations defined in `sec-01_security_standards.md`, focusing on merge-blocking P0 and P1 rules.

## When to Use

- Before opening a PR that touches application logic
- During code review when security-sensitive files are modified
- When auditing an existing codebase for security compliance
- When a user asks "are there any security issues?"

## Workflow

1. Detect the project's languages. Use `.standards.yml` if present, otherwise run:

   ```bash
   .standards/scripts/detect-languages.sh
   ```

2. For each detected language, scan for **banned functions** (P0 violations).

   - Treat `standards/security/sec-01_security_standards.md` §4 as the **single source of truth** for banned functions and insecure APIs.
   - Open `sec-01` and locate the banned-function table; use that table (not this skill file) to determine which functions/APIs to search for in each language.
   - Where available, also consult or run the language-specific checks in `scripts/lint-checks/*/banned-functions.sh` to understand the exact patterns enforced by automation.

   Using the canonical lists from `sec-01` and the `banned-functions.sh` scripts, search the codebase (for example, with `grep -rn` or language-specific AST tools) for these banned functions and patterns. Include tests in the scan; exclude vendored/third-party dependencies and generated code.

3. Scan for **P1 patterns**:
   - **XSS**: `innerHTML`, `dangerouslySetInnerHTML`, `v-html` with dynamic data
   - **SQL injection**: String concatenation in SQL queries (not parameterized)
   - **SSRF**: Unvalidated URL construction from user input
   - **Hardcoded secrets** (P0): Strings matching `password=`, `secret=`, `api_key=`, `token=` patterns
   - **Weak randomness**: `Math.random()`, `random.random()`, `rand()` in security contexts

4. Scan for **dependency age gate** compliance (P1):
   - Check if any lockfile dependency version was published less than 72 hours ago
   - See the `dependency-age-gate` skill for detailed registry checks

5. Present results grouped by severity:
   - **P0 (Critical)** — Must fix before merge. Include file, line number, and the specific violation.
   - **P1 (High)** — Must fix before merge. Include file, line number, and the specific violation.
   - **P2 (Medium)** — Flag as warnings. Include file and recommendation.

## Severity Reference

From `sec-01`:

- **P0**: SQL injection, command injection, hardcoded credentials, authentication bypass, default credentials
- **P1**: XSS, CSRF, SSRF, template injection, weak randomness, insecure deserialization, missing auth checks, dependency age gate
- **P2**: Missing rate limiting, verbose error messages, unpinned dependencies, weak TLS config

## After Scan

Report: "Security scan: X P0 critical, Y P1 high, Z P2 warnings across N files."

If P0 or P1 violations exist, these are **merge-blocking** — clearly state that the PR should not be merged until they are resolved. Provide specific remediation for each violation.
