# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it through GitHub's private security advisory feature:

1. Go to [github.com/c65llc/coding-standards](https://github.com/c65llc/coding-standards)
2. Navigate to **Settings > Security > Advisories**
3. Click **New draft security advisory**
4. Provide a clear description of the vulnerability, steps to reproduce, and any potential impact

**Do not open a public issue for security vulnerabilities.**

## Scope

The following are considered security issues:

- **`install.sh` and the `curl | bash` pattern** — any vulnerability that allows `install.sh` to execute arbitrary or unintended code when run via `curl | bash`
- **Script injection in setup scripts** — any input handling flaw in setup or configuration scripts that could lead to code injection
- **Unauthorized file modification** — any script behavior that modifies user files outside the documented and expected scope

## Response Timeline

- **Acknowledgment** — we will acknowledge receipt of your report within **48 hours**
- **Fix timeline** — we will provide an assessment and expected fix timeline within **7 days**
- **Disclosure** — we will coordinate with you on public disclosure after a fix is available

## What is NOT a Security Issue

The following do not qualify as security vulnerabilities:

- Disagreements with coding standard content or recommendations
- Documentation typos or formatting issues
- Feature requests or general feedback

For these, please open a regular [GitHub issue](https://github.com/c65llc/coding-standards/issues).
