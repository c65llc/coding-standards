# [Topic] — Design Spec

- **Status:** Draft (Draft | Agreed | Implemented | Superseded)
- **Date:** YYYY-MM-DD
- **Related:** #[issue], ADR NNNN, `docs/plans/YYYY-MM-DD-[topic]-plan.md`

A spec answers *what* and *why* so the plan can answer *how* and *in what
order*. Keep it short enough to read in ten minutes; push phase-level detail to
the plan.

## Purpose

[The problem in two or three sentences. Who hits it, how often, what it costs.
Quote the evidence: bug ids, support tickets, metrics, review findings.]

## Success

[Observable outcomes that let a reviewer say "done" without asking the author.
Each line is testable.]

- [ ] [Outcome 1 — e.g. "p95 search latency under 200 ms on the 50k-row fixture"]
- [ ] [Outcome 2]
- [ ] [Outcome 3]

## Non-goals

[Things this work deliberately does not do, so reviewers do not ask for them
and implementers do not drift into them. Each gets a one-line reason.]

- [Non-goal — why it is out of scope]

## Anti-goals

[Outcomes that would make this work a net negative even if every success
criterion passed. Anti-goals are stronger than non-goals: hitting one is a
reason to stop and re-plan.]

- [Anti-goal — e.g. "No new required runtime dependency in the Domain layer"]

## Architecture

[Where the change lives and what it touches. One diagram (Mermaid or text) plus
the module/interface list. Name the layer for each piece (Domain / Application /
Infrastructure / Apps) and any new port or seam.]

```text
[input]  →  [new or changed component]  →  [output]
```

- **New:** [module/file — responsibility]
- **Changed:** [module/file — what changes and why]
- **Unchanged but relied on:** [module/file — the contract we depend on]

## Errors

[Every failure path a user or operator can see. For each: the condition, what
the user sees (copy states the next step), what is logged, and whether the
failure is retried, degraded, or surfaced. Late/stale async responses must not
overwrite newer state — say how that is prevented if the design has any
asynchrony.]

| Condition | User sees | Logged | Recovery |
|-----------|-----------|--------|----------|
| [e.g. network timeout] | [e.g. "Could not save. Check your connection and retry; your draft is kept locally."] | [event + request id] | [retry with backoff; keep local draft] |

## Testing

[How success will be proven, by layer. Name the fixtures and the coverage
target: the floor configured for each touched module's scope in
`.standards.yml` (`coverage.scopes`) — 95% by default, 100% for Domain/Core,
lower only where the scope entry states a `reason` (proc-05 §6); an ADR does
not change it. List anything that can only be verified manually and who
signs it off.]

- **Unit:** [modules, key cases]
- **Integration:** [boundaries exercised]
- **End-to-end / manual:** [flows, who verifies]

## Left to the plan

[Decisions the spec intentionally defers to the implementation plan: phase
ordering, PR boundaries, migration sequencing, flag rollout, exact file names.
Listing them here keeps the spec stable while the plan evolves.]

- [Deferred decision]
