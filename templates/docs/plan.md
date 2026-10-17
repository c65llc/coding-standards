# [Topic] — Implementation Plan

- **Status:** Active (Active | Done | Abandoned)
- **Date:** YYYY-MM-DD
- **Spec:** `docs/specs/YYYY-MM-DD-[topic]-design.md`
- **Related:** #[issue]

A plan turns an agreed spec into ordered, checkable work. It is a *historical*
document from its first commit (proc-01 §9): tick the boxes as work lands, do
not rewrite the history.

## Goal

[One paragraph restating the spec's purpose in terms of what will exist when
the plan is done. Link the spec's Success list; do not duplicate it.]

## Architecture

[Only what an implementer needs that the spec does not say: file layout, module
names, the order in which seams appear. Reference the spec's diagram instead of
redrawing it.]

### Created

- `path/to/new/file` — [responsibility]

### Modified

- `path/to/existing/file` — [what changes]

## Global Constraints

[Rules that apply to every task below. Reviewers check each PR against this
list, so keep it to the ones that actually bite.]

- TDD: failing test first, then the minimum implementation. Coverage ≥ 95% on
  every touched module.
- Conventional Commits; one logical change per commit; one PR per phase unless
  the PR map says otherwise.
- [Project-specific constraint — e.g. "bash 3.2 compatible", "no new Domain deps"]
- Error copy states the next step. Late async responses never overwrite newer
  state.

## Review Focus

[What a reviewer should spend their attention on, in priority order. This is
how the author tells the reviewer where the risk is.]

1. [Highest-risk area — e.g. "migration is reversible on partial failure"]
2. [Second — e.g. "stale-response guard in the search controller"]
3. [Third]

## Phases

[Each phase is independently shippable. Tasks are checkboxes with the file(s)
they touch and the test that proves them. Tick as you go; never delete.]

### Phase 1: [Name — e.g. "Prep: baseline, failing tests"]

- [ ] **Task 1.1:** [action] — `path/to/file` — test: `[test name or command]`
- [ ] **Task 1.2:** [action] — `path/to/file` — test: `[test name or command]`

### Phase 2: [Name]

- [ ] **Task 2.1:** [action] — `path/to/file` — test: `[test name or command]`

### Phase 3: [Name — e.g. "Docs, cleanup, verification doc"]

- [ ] **Task 3.1:** Write `docs/[feature]-verification.md` from `.standards/templates/docs/verification.md` (`templates/docs/verification.md` in the standards repo itself)
- [ ] **Task 3.2:** Set the spec's `- **Status:**` to Implemented and flip its docs-index row to `historical`; add the verification doc to the index as `historical`. The plan's row has been `historical` since its first commit — leave it.

## PR Map

[Which phases land in which PRs, and in what order. A reviewer uses this to
know what is intentionally missing from an early PR.]

| PR | Phases | Title (Conventional Commit) | Depends on |
|----|--------|-----------------------------|------------|
| 1 | 1 | `feat([scope]): [subject]` | — |
| 2 | 2 | `feat([scope]): [subject]` | PR 1 |
| 3 | 3 | `docs([scope]): [subject]` | PR 2 |

## Execution

[How the plan is run: who or which agent executes, in which worktree, how
progress is reported, and what triggers a re-plan.]

- **Executor:** [person / agent / "subagent per phase"]
- **Workspace:** `git worktree add [agent-dir]/worktrees/[branch] -b [branch]`
  where `[agent-dir]` is the agent's directory per proc-04 (`.claude` for Claude
  Code, `.cursor` for Cursor, or the equivalent)
- **Progress:** tick tasks in this file in the same commit as the work; post a
  one-line status on the issue at each phase boundary.
- **Re-plan trigger:** any task that needs a change to the spec's Architecture or
  hits an Anti-goal — stop, update the spec, then resume.
