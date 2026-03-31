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

2. For each detected language, scan for **banned functions** (P0 violations). These are defined in `standards/security/sec-01_security_standards.md` §4:

   | Language | Banned Functions |
   |----------|-----------------|
   | Python | `eval()`, `exec()`, `pickle.loads()` (untrusted), `yaml.load()` (without SafeLoader), `os.system()`, `subprocess.call(..., shell=True)` |
   | JavaScript/TypeScript | `eval()`, `Function()`, `setTimeout(string)`, `setInterval(string)`, `document.write()` |
   | Ruby | `eval()`, `send()` with user input, `system()` with interpolation, `exec()` with interpolation |
   | Java/Kotlin | `Runtime.exec()` with string concat, `ProcessBuilder` with unsanitized input |
   | Rust | `std::process::Command` with unsanitized input in `unsafe` blocks |

   Use `grep -rn` or language-specific AST tools to find violations. Exclude test files and vendored dependencies.

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
