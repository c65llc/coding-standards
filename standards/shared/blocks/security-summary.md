# Security Summary

P0/P1 block merge. P2 are warnings.

P0 (Critical): Never build SQL from user input — use parameterized queries. Never pass user input to `eval()`, `exec()`, `system()`. Never commit credentials. Never deserialize untrusted data via native serialization. Never ship default credentials. Verify auth on every request.

P1 (High): Encode all HTML output. No `innerHTML` with untrusted data. Validate URLs; block SSRF to internal IPs. Enable CSRF on state-changing endpoints. Secure cookie attributes (`Secure`, `HttpOnly`, `SameSite`). Regenerate session IDs after login. Use cryptographically secure random for tokens. Run dependency CVE scanning in CI. Enforce HTTPS/TLS. Configure CSP, HSTS, X-Content-Type-Options, X-Frame-Options. Never log passwords, tokens, or PII.

P2 (Warning): Missing rate limiting. Verbose errors in production. Unpinned dependencies. Missing encryption at rest.

Secrets scanning: run `git-secrets`, `truffleHog`, or `detect-secrets` in CI.
Add `.env` to `.gitignore`. Provide `.env.example` with placeholder values only.
