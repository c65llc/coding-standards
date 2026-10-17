# [Surface / Feature] — Design Pass

- **Status:** Draft (Draft | Agreed | Built | Superseded)
- **Date:** YYYY-MM-DD
- **Related:** #[issue], `docs/specs/YYYY-MM-DD-[topic]-design.md`
- **Reference designs:** `assets/designs/[route-or-component]/`

A design pass happens *before* UI code is written. It forces the questions that
otherwise surface as review churn: who the surface is for, what it must never
do, and which states exist. It complements the post-build validation in
proc-04 §7, which checks that the build matches this pass.

## Identity prompts

[Answer each in one or two sentences. If an answer is "not sure", the pass is
not done.]

- **Who is standing in front of this?** [Primary user, their context, their
  device. Name a secondary user only if the design must serve them too.]
- **What are they trying to finish?** [The job, not the feature. "Get the
  invoice out before 5 pm", not "use the export dialog".]
- **What does it feel like when it works?** [Three adjectives, and the one
  thing the user should notice first.]
- **What does it feel like when it fails?** [How the surface behaves under
  error so the user keeps trust — copy states the next step.]
- **What existing surface is this most like?** [Internal precedent to reuse, or
  "none — new pattern" with the reason.]

## Hard constraints

[Non-negotiables the design must satisfy. Each one is checkable by a reviewer
and should map to a standard, an ADR or an accessibility rule.]

- [Accessibility — e.g. "WCAG 2.1 AA; every action reachable by keyboard"]
- [Layout — e.g. "Compact mode under 600 px uses the drawer, not a sidebar
  (arch-05 §3)"]
- [Data — e.g. "Never render partial results as if complete; show the
  streaming indicator"]
- [Copy — e.g. "Error messages name the next step (core-standards, Error
  Handling)"]
- [Performance — e.g. "First meaningful paint under 1 s on the mid-tier device"]

## Deliverables

[What this pass produces and where it lands. The table is the hand-off
contract between design and build.]

| Deliverable | Location | Owner | Done when |
|-------------|----------|-------|-----------|
| Reference design per state | `assets/designs/[route]/[state].png` | [designer / agent] | Every row in the state inventory has an image or an explicit "n/a" |
| Copy deck | [doc or section] | [owner] | Every visible string, including errors and empty states |
| Component / token list | [doc or section] | [owner] | New tokens named; existing components reused where possible |
| Accessibility notes | [doc or section] | [owner] | Focus order, labels, announcements for live regions |
| Open questions resolved | this file, section below | [owner] | Section is empty |

## State inventory

[Every state the surface can be in. A state without a row does not exist to
the reviewer. Add project-specific rows; do not delete the common ones — mark
them "n/a" with a reason instead.]

| State | Trigger | What the user sees | Copy / next step | Reference |
|-------|---------|--------------------|------------------|-----------|
| Empty | No data yet | [illustration + primary action] | [e.g. "No projects yet. Create your first project."] | `empty.png` |
| Loading | Initial fetch in flight | [skeleton / spinner; layout stable] | [none, or "Loading…"] | `loading.png` |
| Error | Fetch or action failed | [inline error, content preserved] | [what happened + what to do: "Could not load. Retry, or check your connection."] | `error.png` |
| Streaming | Partial results arriving | [progressive render + indicator] | [e.g. "Receiving results…"] | `streaming.png` |
| Sync paused | Background sync intentionally stopped | [badge / banner; local edits allowed] | [e.g. "Sync paused. Changes are saved on this device and will sync when resumed."] | `sync-paused.png` |
| Runner unavailable | Required backend or worker is down | [disabled actions explained, not hidden] | [e.g. "The build runner is offline. Your changes are saved; try again in a few minutes."] | `runner-unavailable.png` |
| Pending write | Local change not yet confirmed | [optimistic update + pending marker] | [e.g. "Saving…"; on failure, revert and explain] | `pending-write.png` |
| [Project-specific state] | [trigger] | [what the user sees] | [copy] | `[state].png` |

## Open questions

[Anything unresolved. The pass is "Agreed" only when this list is empty or
every item has an owner and a date.]

- [ ] [Question — owner — due date]
