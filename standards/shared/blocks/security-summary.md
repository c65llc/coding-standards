P0/P1 block merge. P2 are warnings.

P0 (Critical): Never build SQL from user input — use parameterized queries. Never pass user input to `eval()`, `exec()`, `system()`. Never commit credentials. Never deserialize untrusted data via native serialization. Never ship default credentials. Verify auth on every request.

P1 (High): Encode all HTML output. No `innerHTML` with untrusted data. Validate URLs; block SSRF to internal IPs. Enable CSRF on state-changing endpoints. Secure cookie attributes (`Secure`, `HttpOnly`, `SameSite`). Regenerate session IDs after login. Use cryptographically secure random for tokens. Run dependency CVE scanning in CI. Enforce HTTPS/TLS. Configure CSP, HSTS, X-Content-Type-Options, X-Frame-Options. Never log passwords, tokens, or PII. Fence external content returned to an AI agent in `<untrusted-data>`. Gate agent tool writes behind `writes` flag + `preview` + approval; audit-log every tool call.

P2 (Warning): Missing rate limiting. Verbose errors in production. Unpinned dependencies. Missing encryption at rest.

Secrets scanning: run `git-secrets`, `truffleHog`, or `detect-secrets` in CI. Suppress fixture false positives by shape (inline `trufflehog:ignore` / `gitleaks:allow`, or a shape regex in `.gitleaks.toml`), never by excluding `tests/`.
Add `.env` to `.gitignore`. Provide `.env.example` with placeholder values only.
Dependencies: bot updates are grouped per ecosystem (`.github/dependabot.yml` `groups:`); versions younger than 72 hours wait unless a listed approver applies the `dep-age-override` label and the PR body carries a matching `Approved-by:` block, which opens a 24-hour follow-up issue at merge; every package patch is listed in `patches/README.md` with its reason, regression test and removal criterion.
