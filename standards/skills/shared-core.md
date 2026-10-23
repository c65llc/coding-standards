---
name: shared-core
description: Use when adding or changing a platform shell, touching the core↔shell boundary (FFI, WASM, facade types, golden vectors), deciding whether a new feature's logic belongs in the core or a shell, or asking whether a product should be a web app, an installed PWA, or native shells over a shared core. Do NOT use for projects that have not declared the shared-core profile.
profiles: shared-core
---

# Shared Core

Advise and build under `arch-07` (Cross-Platform Shared-Core Standards): one
logic core, thin native shells, a coarse facade between them. This runbook
routes to the right section; it does not restate the standard.

## When to Use

- A new platform shell is being added, or an existing one is being changed
- A change touches the core↔shell boundary: FFI or WASM bindings, facade types,
  conformance vectors, generated artifacts
- A feature's logic could live in the core or in a shell and someone must decide
- Someone asks whether a product should be a web app, an installed PWA, native
  shells over a shared core, or single-platform native
- A UI change is being scoped to one platform

## Workflow

1. **Read the tenets first.** `arch-07` §7 names the ten tensions every rule in
   the standard resolves. Cite them by short name (`T3 — inject ambient inputs`)
   in findings and recommendations.
2. **Route the question** to the matching section rather than reading the whole
   standard:
   - "Where does this logic live?" → §1 (shared core, per-platform shells) and
     T1/T2
   - "How do we know every platform agrees?" → §2 (golden vectors) and §3 (FFI
     boundary coverage), T5
   - "Why did CI's drift gate go red?" → §3, cold-rebuild drift gate, T6
   - "Can this change ship on one platform only?" → §4, T7; narrowing is written
     into the issue or PR with the reason, never implied
   - "What shape should this product take?" → §8, the decision tree
   - "Is this shell done?" → §9, the native-shell ship audit
3. **Before recommending a product shape, run the §8 decision tree** and report
   the answer at each question. Be willing to conclude that this profile does
   not apply: a tab web app, an installed PWA or a single-platform native app is
   often the right answer, and saying so is the useful outcome.
4. **Before calling a shell done, walk the §9 audit** on the running app, not
   the source. Mark each item observed, failed or not applicable. Items the
   toolkit gives for free stay on the list because refactors silently undo them.
5. **Keep the boundary coarse** (T4): values in, values out; no live handles;
   ambient inputs (clock, ids, locale, timezone) injected by the shell (T3).
6. **Where the project keeps its own ADRs** on platform shape or the boundary,
   read them before advising and cite them; a recorded decision beats this
   runbook's defaults.

## Output style

- Cite the tenet by number and short name, and the section (`arch-07` §3), not
  the whole standard.
- For every recommendation, name what it gives up (T10). There are no free wins
  in this architecture, only trades.
- When the decision tree says the profile does not apply, say so plainly and
  name the shape that does.
- Report the audit as a list of item → observed result, so the next reviewer
  can re-check it without re-deriving it.
