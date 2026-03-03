# Security Guidelines Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a P0-P3 severity-based security standards framework that prevents critical vulnerabilities in AI-generated code and catches them during automated code review.

**Architecture:** One central security standards document (`standards/security/sec-01_security_standards.md`) with P0-P3 tagged rules covering injection, auth, secrets, dangerous functions, supply chain, config, and data protection. All agent configs get security violation detection rules. Core-standards and code review expectations are updated to reference the new framework. Language standards get brief security addenda with language-specific tooling.

**Tech Stack:** Markdown standards documents, agent config files (INI-style for aider/codex, Markdown for cursorrules/copilot/gemini)

---

### Task 1: Create feature branch

**Files:**

- None (git operation only)

**Step 1: Create and switch to feature branch**

Run: `git checkout -b feat/security-standards`
Expected: `Switched to a new branch 'feat/security-standards'`

---

### Task 2: Create the security standards document

**Files:**

- Create: `standards/security/sec-01_security_standards.md`

**Step 1: Create the security directory and standards file**

````markdown
# Security Standards

> **Severity Model:** Rules are tagged P0 (Critical), P1 (High), P2 (Medium), or P3 (Low).
> P0 and P1 findings **must block merge**. P2 findings should be flagged as warnings. P3 findings are informational.
>
> This framework is inspired by [Omar Gate](https://github.com/marketplace/actions/omar-gate)'s multi-layer security analysis model.

## 1. Injection Prevention

### SQL Injection `[P0]`

- **Use parameterized queries exclusively.** Never construct SQL via string concatenation or interpolation with user input.
- ORMs and query builders are preferred. Raw SQL must use bind parameters.

```python
# BAD — P0 violation
query = f"SELECT * FROM users WHERE id = {user_input}"
cursor.execute(query)

# GOOD
cursor.execute("SELECT * FROM users WHERE id = %s", (user_input,))
```

```ruby
# BAD — P0 violation
User.where("name = '#{params[:name]}'")

# GOOD
User.where(name: params[:name])
```

```typescript
// BAD — P0 violation
const query = `SELECT * FROM users WHERE id = ${userId}`;

// GOOD
const result = await db.query("SELECT * FROM users WHERE id = $1", [userId]);
```

### Command Injection `[P0]`

- **Never pass unsanitized user input to shell commands, `eval()`, `exec()`, or `system()`.**
- Use language-specific safe APIs instead of shell invocation.
- If shell execution is unavoidable, use allowlists for permitted commands and arguments.

```python
# BAD — P0 violation
os.system(f"convert {user_filename} output.png")
subprocess.call(user_input, shell=True)

# GOOD
subprocess.run(["convert", validated_filename, "output.png"], shell=False)
```

```javascript
// BAD — P0 violation
eval(userInput);
require("child_process").exec(userCommand);

// GOOD
require("child_process").execFile("convert", [validatedFilename, "output.png"]);
```

### Cross-Site Scripting (XSS) `[P1]`

- **Encode all output rendered in HTML contexts.** Use framework-provided escaping by default.
- Never use `innerHTML`, `dangerouslySetInnerHTML`, or `v-html` with untrusted data.
- Configure Content Security Policy (CSP) headers to restrict inline scripts.

```javascript
// BAD — P1 violation
element.innerHTML = userInput;

// GOOD
element.textContent = userInput;
```

```jsx
// BAD — P1 violation
<div dangerouslySetInnerHTML={{ __html: userInput }} />

// GOOD
<div>{userInput}</div>
```

### Server-Side Request Forgery (SSRF) `[P1]`

- **Validate and sanitize all URL inputs.** Allowlist permitted domains and protocols.
- Block requests to internal/private IP ranges (`10.x`, `172.16-31.x`, `192.168.x`, `127.x`, `169.254.x`).
- Do not allow user input to control the full URL of outbound HTTP requests.

### Template Injection `[P1]`

- **Never pass user input directly into template expressions or template strings that are evaluated server-side.**
- Use sandboxed template engines. Separate data from template logic.

## 2. Authentication & Authorization

### Authentication Bypass `[P0]`

- **Never implement custom authentication logic when framework/library solutions exist.**
- Verify authentication on every request — do not rely on client-side checks alone.
- Token validation must check expiration, signature, and issuer.
- Never compare secrets or tokens with `==` — use constant-time comparison functions.

```python
# BAD — P0 violation (timing attack)
if provided_token == stored_token:
    grant_access()

# GOOD
import hmac
if hmac.compare_digest(provided_token, stored_token):
    grant_access()
```

### Authorization Checks `[P1]`

- **Every endpoint must enforce authorization.** Verify the authenticated user has permission for the specific resource and action.
- Never rely solely on hiding UI elements for access control.
- Use RBAC or policy-based authorization. Check permissions server-side on every request.

### CSRF Protection `[P1]`

- **Enable CSRF protection on all state-changing endpoints** (POST, PUT, PATCH, DELETE).
- Use framework-provided CSRF mechanisms (Rails `protect_from_forgery`, Django CSRF middleware, etc.).
- API endpoints using token-based auth (Bearer tokens) are exempt but must validate the token on every request.

### Session Management `[P1]`

- Set secure cookie attributes: `Secure`, `HttpOnly`, `SameSite=Strict` (or `Lax`).
- Regenerate session IDs after authentication.
- Implement session expiration and idle timeouts.

## 3. Secrets Management

### Hardcoded Credentials `[P0]`

- **Never commit secrets, API keys, passwords, tokens, or credentials to source code.**
- Use environment variables, secret management services (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager), or framework credential systems (Rails credentials).
- Scan for secrets in CI with tools like `git-secrets`, `truffleHog`, or `detect-secrets`.

Common patterns to detect and reject:

```text
# BAD — P0 violations (any of these patterns in source code)
API_KEY = "sk-abc123..."
password = "hardcoded_password"
aws_secret_access_key = "AKIA..."
DATABASE_URL = "postgres://user:pass@host/db"
private_key = "-----BEGIN RSA PRIVATE KEY-----"
```

### .env File Handling `[P1]`

- **Never commit `.env` files to version control.** Add `.env` to `.gitignore`.
- Provide `.env.example` with placeholder values (never real credentials).
- In production, use secret management services — not `.env` files.

### Credential Rotation `[P2]`

- Rotate credentials on a regular schedule.
- Implement credential rotation without downtime.
- Log credential access for audit purposes.

## 4. Dangerous Functions & Patterns

### Banned Functions `[P0]`

Never use these functions with untrusted input. If used with trusted input, add a comment explaining why.

| Language | Banned Functions |
|----------|-----------------|
| Python | `eval()`, `exec()`, `pickle.loads()` (untrusted), `yaml.load()` (use `safe_load`), `os.system()`, `subprocess.call(..., shell=True)` |
| JavaScript/TypeScript | `eval()`, `Function()`, `setTimeout(string)`, `setInterval(string)`, `document.write()` |
| Ruby | `eval()`, `send()` with user input, `system()` with interpolation, `Marshal.load()` (untrusted), `YAML.load()` (use `safe_load`) |
| Java/Kotlin | `Runtime.exec()` with string, `ObjectInputStream.readObject()` (untrusted), `ScriptEngine.eval()` |
| Rust | `std::process::Command` with unsanitized input |
| Swift | `NSExpression` with user input, `Process` with unsanitized args |

### Insecure Deserialization `[P0]`

- **Never deserialize untrusted data using native serialization formats** (Python pickle, Java ObjectInputStream, Ruby Marshal, PHP unserialize).
- Use safe data formats (JSON, Protocol Buffers) for untrusted data exchange.
- If native deserialization is required, validate and sanitize before deserializing.

### Insecure Randomness `[P1]`

- **Use cryptographically secure random number generators for security contexts** (tokens, keys, session IDs, nonces).

| Language | Insecure (avoid for security) | Secure (use for security) |
|----------|-------------------------------|---------------------------|
| Python | `random.random()` | `secrets.token_urlsafe()`, `secrets.token_hex()` |
| JavaScript | `Math.random()` | `crypto.randomUUID()`, `crypto.getRandomValues()` |
| Ruby | `rand()` | `SecureRandom.hex()`, `SecureRandom.uuid()` |
| Java/Kotlin | `java.util.Random` | `java.security.SecureRandom` |
| Rust | — | `rand::rngs::OsRng` (already secure by default) |

## 5. Dependency & Supply Chain Security

### Known CVE Scanning `[P1]`

- **Run dependency vulnerability scanning in CI/CD.** Block merges on critical/high CVEs.

| Language | Tool |
|----------|------|
| Python | `pip-audit`, `safety` |
| JavaScript/TypeScript | `npm audit`, `yarn audit` |
| Ruby | `bundle-audit`, `bundler-audit` |
| Java/Kotlin | OWASP Dependency-Check, `gradle dependencyCheckAnalyze` |
| Rust | `cargo audit`, `cargo deny` |
| Swift | — (use GitHub Dependabot) |
| Dart | — (use GitHub Dependabot) |
| Zig | — (manual review) |

### Lock File Requirements `[P1]`

- **Always commit lock files** (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `poetry.lock`, etc.).
- CI must install from lock files (`npm ci`, `bundle install --frozen`, etc.).

### HTTP Dependency Prohibition `[P2]`

- **Never use HTTP (non-HTTPS) URLs for package registries or dependency sources.**
- All dependency sources must use HTTPS.

### Dependency Pinning `[P2]`

- Pin major and minor versions in production dependencies.
- Review and test dependency updates before merging.

## 6. Configuration Security

### Default Credentials `[P0]`

- **Never ship or deploy with default credentials.** All default passwords, API keys, and admin accounts must be changed before deployment.
- Fail loudly if default credentials are detected at startup.

### TLS/HTTPS `[P1]`

- **Enforce HTTPS for all external communication.** Redirect HTTP to HTTPS.
- Use TLS 1.2+ for all connections. Disable older TLS/SSL versions.

### Security Headers `[P1]`

- **Configure security headers on all HTTP responses:**

| Header | Value | Purpose |
|--------|-------|---------|
| `Content-Security-Policy` | Restrict sources | Prevents XSS |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Forces HTTPS |
| `X-Content-Type-Options` | `nosniff` | Prevents MIME sniffing |
| `X-Frame-Options` | `DENY` or `SAMEORIGIN` | Prevents clickjacking |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer leakage |

### Debug Mode `[P2]`

- **Never enable debug mode or verbose error messages in production.**
- Log detailed errors server-side; return generic error messages to clients.
- Ensure framework debug flags are off: `DEBUG=False` (Django), `config.consider_all_requests_local = false` (Rails), `NODE_ENV=production`.

## 7. Data Protection

### Sensitive Data in Logs `[P1]`

- **Never log passwords, tokens, API keys, credit card numbers, or PII.**
- Use structured logging with field-level redaction.
- Review log output for accidental sensitive data exposure.

```python
# BAD — P1 violation
logger.info(f"User login: {username}, password: {password}")

# GOOD
logger.info("User login", extra={"username": username})
```

### PII Handling `[P2]`

- Minimize PII collection — only collect what is necessary.
- Encrypt PII at rest and in transit.
- Implement data retention policies and deletion capabilities.

### Encryption `[P2]`

- Use established encryption libraries — never implement custom cryptography.
- Encrypt sensitive data at rest (database-level or application-level encryption).
- All data in transit must use TLS.

## 8. Security Tooling Reference

### Static Analysis Security Testing (SAST)

| Language | Tool | Usage |
|----------|------|-------|
| Python | `bandit` | `bandit -r src/` |
| JavaScript/TypeScript | `eslint-plugin-security` | Add to ESLint config |
| Ruby | `brakeman` | `brakeman --no-pager` |
| Java/Kotlin | SpotBugs + Find Security Bugs | Gradle/Maven plugin |
| Rust | `cargo audit` | `cargo audit` |
| Swift | — | Use Xcode static analyzer |
| Dart | `dart analyze` | Built-in security rules |

### Secrets Scanning

| Tool | Scope |
|------|-------|
| `git-secrets` | Pre-commit hook |
| `truffleHog` | Full repo history scan |
| `detect-secrets` | Pre-commit + CI |
| GitHub Secret Scanning | Automatic (GitHub repos) |

````

**Step 2: Commit**

Run:

```bash
mkdir -p standards/security
# (write file)
git add standards/security/sec-01_security_standards.md
git commit -m "feat(security): add sec-01 security standards with P0-P3 severity model"
```

---

### Task 3: Update core-standards.md security section

**Files:**

- Modify: `standards/shared/core-standards.md` (lines 196-214, and add reference after line 281)

**Step 1: Replace the security section (lines 196-214) with an expanded version**

Replace the current 9-bullet security section with:

```markdown
## Security

> Full security standards with code examples: `standards/security/sec-01_security_standards.md`
>
> Severity model: **P0** (Critical) and **P1** (High) findings block merge. **P2** (Medium) are warnings. **P3** (Low) are informational.

### P0 — Critical (Must Block Merge)

- Never construct SQL via string concatenation with user input. Use parameterized queries.
- Never pass unsanitized user input to `eval()`, `exec()`, `system()`, or shell commands.
- Never commit secrets, API keys, passwords, or credentials to source code.
- Never deserialize untrusted data using native serialization (pickle, Marshal, ObjectInputStream).
- Never ship default credentials in production.
- Verify authentication on every request. Never bypass auth checks.

### P1 — High (Must Block Merge)

- Encode all output in HTML contexts. Never use `innerHTML` with untrusted data.
- Validate and sanitize URL inputs. Block SSRF to internal IP ranges.
- Enable CSRF protection on all state-changing endpoints.
- Enforce authorization checks on every endpoint.
- Use cryptographically secure random for tokens, keys, and session IDs.
- Run dependency vulnerability scanning in CI/CD. Commit lock files.
- Enforce HTTPS/TLS for all external communication.
- Configure security headers (CSP, HSTS, X-Content-Type-Options, X-Frame-Options).
- Never log passwords, tokens, API keys, or PII.
- Add `.env` to `.gitignore`. Never commit `.env` files.

### Secrets Management

- Use secret management services (AWS Secrets Manager, Vault, GCP Secret Manager).
- Rotate credentials regularly.
- Scan for secrets with `git-secrets`, `truffleHog`, or `detect-secrets`.

### Dependency Security

- Regular security audits (`npm audit`, `cargo audit`, `pip-audit`, `bundle-audit`).
- Automated vulnerability scanning in CI/CD.
- Patch critical vulnerabilities immediately.
```

**Step 2: Add security standards reference**

After the Process Standards reference section (line 281), add:

```markdown

## Security Standards

Reference detailed security standards in:

- `standards/security/sec-01_security_standards.md`
```

**Step 3: Commit**

Run:

```bash
git add standards/shared/core-standards.md
git commit -m "feat(security): expand core-standards security section with P0-P3 model"
```

---

### Task 4: Update code review expectations

**Files:**

- Modify: `standards/process/proc-03_code_review_expectations.md`

**Step 1: Expand the security checklist items (around lines 57, 60)**

Replace lines 57 and 60:

```text
- [ ] No security vulnerabilities introduced
```

and

```text
- [ ] No secrets or sensitive data committed
```

With:

```markdown
- [ ] No P0/P1 security violations (see `standards/security/sec-01_security_standards.md`)
- [ ] No hardcoded secrets, API keys, or credentials in source code
- [ ] No SQL injection, command injection, or XSS vulnerabilities
- [ ] No use of banned dangerous functions with untrusted input
```

**Step 2: Expand the approval criteria security line (line 157)**

Replace:

```text
- **Security:** No security concerns
```

With:

```markdown
- **Security:** No P0 or P1 security findings (per `standards/security/sec-01_security_standards.md`). P0/P1 findings block approval.
```

**Step 3: Expand the CI/CD security check (line 207)**

Replace:

```text
- **Security:** Dependency vulnerability scanning
```

With:

```markdown
- **Security:** Dependency vulnerability scanning, SAST (language-appropriate: bandit, eslint-plugin-security, brakeman, SpotBugs), secrets scanning
```

**Step 4: Commit**

Run:

```bash
git add standards/process/proc-03_code_review_expectations.md
git commit -m "feat(security): update code review expectations with P0-P3 security checks"
```

---

### Task 5: Update .cursorrules (root + template)

**Files:**

- Modify: `.cursorrules` (lines 31, 108)
- Modify: `standards/agents/cursor/.cursorrules` (if it exists — check first; if not, only modify root)

**Step 1: Add security standards to reference list (after line 31)**

After the Process Standards section, add:

```markdown

4. **Security Standards:**
   - `standards/security/sec-01_security_standards.md` - Security guidelines with P0-P3 severity model
```

**Step 2: Add security violation detection (after line 108)**

After `- Git commit message format issues`, add:

```markdown
- **P0 Security violations** — hardcoded secrets, SQL injection, command injection, insecure deserialization, auth bypass, default credentials
- **P1 Security violations** — missing CSRF protection, XSS, SSRF, missing authorization, sensitive data in logs, HTTP dependencies, missing security headers, insecure random
```

**Step 3: Commit**

Run:

```bash
git add .cursorrules
git commit -m "feat(security): add security violation detection to .cursorrules"
```

---

### Task 6: Update copilot-instructions.md (root + template)

**Files:**

- Modify: `.github/copilot-instructions.md` (lines 31, 102)
- Modify: `standards/agents/copilot/.github/copilot-instructions.md` (same edits)

**Step 1: Add security standards to reference list (after line 31)**

After the Process Standards section, add:

```markdown

### Security Standards
- `standards/security/sec-01_security_standards.md` - Security guidelines with P0-P3 severity model
```

**Step 2: Add security violation detection (after line 102)**

After `- Git commit message format issues`, add:

```markdown
- **P0 Security violations** — hardcoded secrets, SQL injection, command injection, insecure deserialization, auth bypass, default credentials
- **P1 Security violations** — missing CSRF protection, XSS, SSRF, missing authorization, sensitive data in logs, HTTP dependencies, missing security headers, insecure random
```

**Step 3: Commit both files**

Run:

```bash
git add .github/copilot-instructions.md standards/agents/copilot/.github/copilot-instructions.md
git commit -m "feat(security): add security violation detection to copilot instructions"
```

---

### Task 7: Update .aiderrc (root + template)

**Files:**

- Modify: `.aiderrc` (insert new block after line 86)
- Modify: `standards/agents/aider/.aiderrc` (same edit)

**Step 1: Add security_standards block**

After the `error_handling` block (ending with `"""`), add:

```ini

security_standards = """
P0 (Critical — must block merge):
- Hardcoded secrets, API keys, or credentials in source code
- SQL injection via string concatenation
- Command injection via eval/exec/system with untrusted input
- Insecure deserialization of untrusted data
- Authentication bypass patterns
- Default credentials in production configs

P1 (High — must block merge):
- Missing CSRF protection on state-changing endpoints
- XSS via unsanitized user input in HTML output
- SSRF via unvalidated URL inputs
- Missing authorization checks on endpoints
- Sensitive data in logs or error messages
- HTTP dependencies (non-HTTPS)
- Missing security headers (CSP, HSTS)
- Insecure random for security contexts (tokens, keys)

Reference: standards/security/sec-01_security_standards.md
"""
```

**Step 2: Commit both files**

Run:

```bash
git add .aiderrc standards/agents/aider/.aiderrc
git commit -m "feat(security): add security standards block to aider config"
```

---

### Task 8: Update .codexrc (root + template)

**Files:**

- Modify: `.codexrc` (after line 44, and after line 67)
- Modify: `standards/agents/codex/.codexrc` (same edits)

**Step 1: Add Security Standards section (after Process Standards)**

After `## Process Standards`, add:

```ini

## Security Standards
# Reference: standards/security/sec-01_security_standards.md
# P0 (Critical — block merge): hardcoded secrets, SQL injection, command injection,
#   insecure deserialization, auth bypass, default credentials
# P1 (High — block merge): CSRF, XSS, SSRF, missing authorization,
#   sensitive data in logs, HTTP deps, missing security headers, insecure random
```

**Step 2: Add security violation detection (after line 67)**

After `# - Documentation gaps`, add:

```ini
# - P0 Security violations (secrets, injection, deserialization, auth bypass)
# - P1 Security violations (CSRF, XSS, SSRF, authorization, data exposure)
```

**Step 3: Commit both files**

Run:

```bash
git add .codexrc standards/agents/codex/.codexrc
git commit -m "feat(security): add security standards to codex config"
```

---

### Task 9: Update GEMINI.md

**Files:**

- Modify: `.gemini/GEMINI.md` (lines 64, 109)

**Step 1: Add security/ to repository structure tree (after line 64)**

Change `│   ├── process/` and add security before agents:

```text
│   ├── process/
│   ├── security/
│   └── agents/
```

**Step 2: Add security standards to Key Standards Files (after line 109)**

After `- **Process Standards:**...`, add:

```markdown
- **Security Standards:** `standards/security/sec-01_security_standards.md` - P0-P3 security guidelines
```

**Step 3: Add security to Non-Negotiables (after line 33)**

After the Safety block, add:

```markdown
- **Security:** Follow P0-P3 severity model in `standards/security/sec-01_security_standards.md`. P0/P1 violations block merge.
```

**Step 4: Commit**

Run:

```bash
git add .gemini/GEMINI.md
git commit -m "feat(security): add security standards to Gemini config"
```

---

### Task 10: Update STRUCTURE.md

**Files:**

- Modify: `STRUCTURE.md` (lines 40-44, line 98, line 119)

**Step 1: Add security/ directory to tree (between process/ and agents/)**

After `proc-04_agent_workflow_standards.md` (line 39), add:

```text
│   │
│   ├── security/                  # Security standards
│   │   └── sec-01_security_standards.md
```

**Step 2: Add security row to File Locations table (after line 98)**

After `| Process | ... |`, add:

```text
| Security | `standards/security/` | sec-01 |
```

**Step 3: Update Path References (line 119)**

Change:

```text
- **`.cursorrules`** - References `standards/architecture/`, `standards/languages/`, `standards/process/`
```

To:

```text
- **`.cursorrules`** - References `standards/architecture/`, `standards/languages/`, `standards/process/`, `standards/security/`
```

**Step 4: Commit**

Run:

```bash
git add STRUCTURE.md
git commit -m "docs: add security/ directory to STRUCTURE.md"
```

---

### Task 11: Add security sections to language standards

**Files:**

- Modify: `standards/languages/lang-01_python_standards.md` (append)
- Modify: `standards/languages/lang-02_java_standards.md` (append)
- Modify: `standards/languages/lang-03_kotlin_standards.md` (append)
- Modify: `standards/languages/lang-04_swift_standards.md` (append)
- Modify: `standards/languages/lang-05_dart_standards.md` (append)
- Modify: `standards/languages/lang-06_typescript_standards.md` (append)
- Modify: `standards/languages/lang-07_javascript_standards.md` (append)
- Modify: `standards/languages/lang-08_rust_standards.md` (append)
- Modify: `standards/languages/lang-09_zig_standards.md` (append)
- Modify: `standards/languages/lang-10_ruby_standards.md` (append)
- Skip: `standards/languages/lang-11_ruby_on_rails_standards.md` (already has Security section at line 495)

**Step 1: Append security section to each file**

Each language gets a section following this template, customized with language-specific tools:

**Python (lang-01):**

```markdown

## 11. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Run `bandit -r src/` in CI. Configure with `.bandit` or `pyproject.toml`.
- **Dependency scanning:** Run `pip-audit` and `safety check` in CI.
- **Secrets scanning:** Use `detect-secrets` as a pre-commit hook.
- **Banned functions:** `eval()`, `exec()`, `pickle.loads()` (untrusted), `yaml.load()` (use `safe_load`), `os.system()`, `subprocess.call(..., shell=True)`.
- **Secure random:** Use `secrets` module for tokens and keys, not `random`.
```

**Java (lang-02):**

```markdown

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use SpotBugs with Find Security Bugs plugin in CI.
- **Dependency scanning:** Run OWASP Dependency-Check (`gradle dependencyCheckAnalyze`).
- **Banned functions:** `Runtime.exec()` with unsanitized string, `ObjectInputStream.readObject()` on untrusted data, `ScriptEngine.eval()`.
- **Secure random:** Use `java.security.SecureRandom`, not `java.util.Random`, for security contexts.
```

**Kotlin (lang-03):**

```markdown

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use SpotBugs with Find Security Bugs plugin or detekt security ruleset in CI.
- **Dependency scanning:** Run OWASP Dependency-Check (`gradle dependencyCheckAnalyze`).
- **Banned functions:** `Runtime.exec()` with unsanitized string, `ObjectInputStream.readObject()` on untrusted data, `ScriptEngine.eval()`.
- **Secure random:** Use `java.security.SecureRandom`, not `java.util.Random`, for security contexts.
```

**Swift (lang-04):**

```markdown

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use Xcode's built-in static analyzer. No major third-party SAST tool for Swift.
- **Dependency scanning:** Enable GitHub Dependabot for SPM dependencies.
- **Banned functions:** `NSExpression` with user input, `Process`/`NSTask` with unsanitized arguments.
- **Secure random:** Use `SystemRandomNumberGenerator` or `SecRandomCopyBytes` for security contexts.
```

**Dart (lang-05):**

```markdown

## 14. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Run `dart analyze` with security-relevant lint rules enabled.
- **Dependency scanning:** Enable GitHub Dependabot for pub dependencies.
- **Secure random:** Use `dart:math Random.secure()` for security contexts, not `Random()`.
```

**TypeScript (lang-06):**

```markdown

## 13. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use `eslint-plugin-security` in ESLint config.
- **Dependency scanning:** Run `npm audit` or `yarn audit` in CI.
- **Secrets scanning:** Use `detect-secrets` as a pre-commit hook.
- **Banned functions:** `eval()`, `Function()`, `setTimeout(string)`, `setInterval(string)`, `document.write()`.
- **Secure random:** Use `crypto.randomUUID()` or `crypto.getRandomValues()`, not `Math.random()`, for security contexts.
```

**JavaScript (lang-07):**

```markdown

## 14. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Use `eslint-plugin-security` in ESLint config.
- **Dependency scanning:** Run `npm audit` or `yarn audit` in CI.
- **Secrets scanning:** Use `detect-secrets` as a pre-commit hook.
- **Banned functions:** `eval()`, `Function()`, `setTimeout(string)`, `setInterval(string)`, `document.write()`.
- **Secure random:** Use `crypto.randomUUID()` or `crypto.getRandomValues()`, not `Math.random()`, for security contexts.
```

**Rust (lang-08):**

```markdown

## 20. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **Dependency scanning:** Run `cargo audit` and `cargo deny check` in CI.
- **Unsafe code:** Minimize `unsafe` blocks. Document safety invariants for every `unsafe` usage. Prefer safe abstractions.
- **Secure random:** Use `rand::rngs::OsRng` or `getrandom` crate for cryptographic randomness.
```

**Zig (lang-09):**

```markdown

## 14. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** No major SAST tool for Zig yet. Rely on compiler warnings and manual review.
- **Memory safety:** Zig has no hidden control flow. Use `@panic` only for programming errors. Validate all external inputs at system boundaries.
- **Secure random:** Use `std.crypto.random` for security contexts.
```

**Ruby (lang-10):**

```markdown

## 11. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Run `brakeman --no-pager` in CI for Rails apps. Use `rubocop-security` rules.
- **Dependency scanning:** Run `bundle-audit check --update` in CI.
- **Secrets scanning:** Use `detect-secrets` as a pre-commit hook.
- **Banned functions:** `eval()`, `send()` with user input, `system()` with interpolation, `Marshal.load()` (untrusted), `YAML.load()` (use `YAML.safe_load`).
- **Secure random:** Use `SecureRandom.hex()` or `SecureRandom.uuid()`, not `rand()`, for security contexts.
```

**Step 2: Update lang-11 (Rails) to reference central doc**

Add a reference blockquote at the top of the existing Security section (line 495):

```markdown
## 9. Security

> Full security standards: `standards/security/sec-01_security_standards.md`
```

**Step 3: Commit**

Run:

```bash
git add standards/languages/
git commit -m "feat(security): add security sections to all language standards"
```

---

### Task 12: Update CLAUDE.md

**Files:**

- Modify: `CLAUDE.md`

**Step 1: Add security/ to the Architecture section**

In the "Standards Documents" subsection, add after the process/ description:

```markdown
- `security/` (sec-01): Security guidelines with P0-P3 severity model
```

**Step 2: Commit**

Run:

```bash
git add CLAUDE.md
git commit -m "docs: add security standards reference to CLAUDE.md"
```

---

### Task 13: Final verification

**Step 1: Verify all files reference sec-01**

Run: `grep -r "sec-01" standards/ .cursorrules .github/ .aiderrc .codexrc .gemini/ STRUCTURE.md CLAUDE.md`

Expected: References in all updated files.

**Step 2: Verify no broken references**

Run: `ls standards/security/sec-01_security_standards.md`

Expected: File exists.

**Step 3: Verify markdown lint passes**

Run: `make lint` (if markdownlint is available, otherwise skip)

**Step 4: Verify shell scripts still pass**

Run: `make test-scripts`

Expected: All scripts pass `bash -n` validation.
