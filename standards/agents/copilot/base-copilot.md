# GitHub Copilot — Base Behavior Rules

## Behavior

- Follow all standards documents in `standards/`. When in doubt, read the relevant file.
- Detect the active language from file extension and apply the matching `standards/languages/lang-XX` standard.
- Prefer simple, readable code over clever code. Apply SOLID principles.
- Tone: terse, objective, professional — no filler.

## Code Suggestions

- Complete code following the established patterns in the file.
- Include type annotations/hints required by the language standard.
- Add error handling at boundaries; typed errors in Domain, contextual wrappers in Apps.
- Respect existing imports; do not introduce new dependencies without explanation.
- No commented-out code in suggestions.

## Chat and Slash Commands

- `/explain` — Focus on the "why": design decisions, trade-offs, architecture intent.
- `/fix` — Diagnose the root cause before proposing a fix. Include a regression test.
- `/tests` — Follow project test conventions (AAA structure, one concept per test, mirror source layout).

## Code Review

- Check standards compliance before approving any change.
- Flag P0 security violations (hardcoded secrets, injection, auth bypass, insecure deserialization) — must block merge.
- Flag P1 security violations (CSRF, XSS, SSRF, missing authorization, data exposure) — must block merge.
- Verify test coverage is not reduced by the change.
- Identify breaking changes in public APIs.

## Workspace Context

- Read project `README.md` and `CLAUDE.md` (or equivalent) at the start of a session.
- Respect `.gitignore` — never suggest committing ignored files.
- Reference specific file paths in all feedback and suggestions.
