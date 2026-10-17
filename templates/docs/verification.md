# [Feature] — Verification

- **Status:** Historical (point-in-time record; do not edit after the PR merges)
- **Date:** YYYY-MM-DD
- **PR:** #[pr]
- **Related:** #[issue], `docs/specs/YYYY-MM-DD-[topic]-design.md`, `docs/plans/YYYY-MM-DD-[topic]-plan.md`
- **Commit verified:** `[sha]`

A verification doc records what was actually proven before merge — not what
the plan intended. A green pipeline is evidence, not proof; this document says
what the evidence covers and, just as importantly, what it does not.

## Summary

[Two or three sentences: what shipped, how it was verified, and the one
residual risk a reader should know about.]

## Tests run

[Every command that was executed, where, and the result. Paste counts from the
tool output; do not round.]

| Suite | Command | Where | Result |
|-------|---------|-------|--------|
| Unit | `[e.g. pytest tests/unit -q]` | [local / CI run id] | [e.g. 212 passed, 0 failed, 3 skipped] |
| Integration | `[command]` | [local / CI] | [count] |
| End-to-end | `[command]` | [CI] | [count] |
| Lint / types | `[e.g. make lint && mypy --strict src]` | [local / CI] | [clean / N warnings] |

**Total:** [N] tests run, [N] passed, [N] failed, [N] skipped.

## Coverage per module

[One row per module the change touched. The target is 95% unless an ADR
grants an exception — cite it in the Notes column.]

| Module | Lines | Branches | Target | Notes |
|--------|-------|----------|--------|-------|
| `[package/module]` | [97.2%] | [91.0%] | 95% | [—] |
| `[package/module]` | [88.4%] | [80.1%] | 95% | [Below target: ADR NNNN — untestable boundary; manual check below] |

## Manually verified

[Things proven by a human or an agent driving the real system, with enough
detail to repeat. Attach screenshots for UI changes (proc-04 §7).]

- [Flow — environment — who — what was observed]

## What was NOT verified

[The most important section. Name each gap plainly, say why it was not
verified, and what would close it. "Nothing" is almost never true.]

- [Gap — e.g. "Behaviour under sync-paused state: no fixture exists for a
  paused sync; tracked in #NNN"]
- [Gap — e.g. "Windows path handling: CI matrix is Linux + macOS only"]
- [Gap — e.g. "Load above 10k concurrent sessions: not exercised"]

## Residual risk

[Given the gaps above, what could still go wrong in production, how it would
show up, and the rollback or mitigation. One to three bullets.]

- [Risk — detection signal — mitigation / rollback]
