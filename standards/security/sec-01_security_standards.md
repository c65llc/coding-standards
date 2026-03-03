# Security Standards

> **Severity Model:** Rules are tagged P0 (Critical), P1 (High), or P2 (Medium).
> P0 and P1 findings **must block merge**. P2 findings should be flagged as warnings.
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
| Ruby | `eval()`, `send()` with user input, `system()` with interpolation, `Marshal.load()` (untrusted), `YAML.load()` (use `YAML.safe_load`) |
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
| JavaScript/TypeScript | `pnpm audit`, `npm audit`, `yarn audit` |
| Ruby | `bundler-audit` (`bundle-audit` command) |
| Java/Kotlin | OWASP Dependency-Check, `gradle dependencyCheckAnalyze` |
| Rust | `cargo audit`, `cargo deny` |
| Swift | — (use GitHub Dependabot) |
| Dart | — (use GitHub Dependabot) |
| Zig | — (manual review) |

### Lock File Requirements `[P1]`

- **Always commit lock files** (`package-lock.json`, `Gemfile.lock`, `Cargo.lock`, `poetry.lock`, etc.).
- CI must install from lock files (`npm ci`, `BUNDLE_FROZEN=1 bundle install`, etc.).

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
| Rust | `cargo-geiger` (unsafe audit), `clippy` | `cargo geiger`, `cargo clippy --all-targets --all-features -- -D warnings` |
| Swift | — | Use Xcode static analyzer |
| Dart | `dart analyze` | Built-in security rules |

### Secrets Scanning

| Tool | Scope |
|------|-------|
| `git-secrets` | Pre-commit hook |
| `truffleHog` | Full repo history scan |
| `detect-secrets` | Pre-commit + CI |
| GitHub Secret Scanning | Automatic (GitHub repos) |
