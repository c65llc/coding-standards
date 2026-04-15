---
title: "Standards 1.1: Reliability and Agent Coverage"
date: 2026-04-15
authors:
  - name: C65 LLC
---

Standards 1.1 is a maintenance-and-maturity release. Most prior posts have been about *adding* something — a new linter, a new skill, a new framework. This release is about the layer underneath: the governance, infrastructure, and drift-prevention that make the project trustworthy as a long-running dependency. It also closes a gap that was overdue: cross-agent coordination conventions for [Google Antigravity](https://antigravity.google.com), so Missions and design-fidelity reviews work the same way whether the agent in front of you is Antigravity, Claude Code, Cursor, Aider, or Codex.

## Project governance you can grep

Three files most projects don't notice until they're missing:

- **`.github/CODEOWNERS`** — default code ownership for review routing. Aligns with [proc-03 code review expectations](/standards/process/proc-03_code_review_expectations/).
- **`.github/dependabot.yml`** — automated dependency updates for npm and GitHub Actions. This is distinct from the [72-hour age gate](/blog/dependency-age-gate/): dependabot *proposes* upgrades, the age gate *decides* whether they're old enough to install.
- **A P0/P1/P2 checklist in the PR template.** The [security framework](/blog/security-standards/) defined the severity model; the PR template is where reviewers and authors actually use it. One short checklist beats a 200-line standards doc no one re-reads per PR.

## Why decisions are written down

`docs/adr/0001-unified-standards-repository.md` is the first Architecture Decision Record in the repo. It captures *why* the standards live in one repo per organization (rather than per-language or per-team) and what the alternatives were. ADRs aren't documentation in the usual sense; they're the trail of receipts for choices that later look obvious.

Two new READMEs join it: `standards/README.md` (a map of the directory layout and naming conventions) and `bin/README.md` (an overview of the `gh-task` CLI with links to its full guide). Neither adds anything functionally new; both compress the time-to-orient for someone landing in the repo cold.

## Drift detection for the .aiderrc file

When the [block-based agent config assembly](/blog/token-efficient-agent-configs/) shipped, every agent config file *except one* was migrated to it. The exception was `.aiderrc` — `sync-standards.sh` treats it as customized (its checksum diverged from the canonical template) and skipped it on every sync. The result: that file carried a 97-line inline P0/P1 security list that the rest of the project had stopped using six weeks earlier ([#34](https://github.com/c65llc/coding-standards/issues/34)).

1.1 resyncs `.aiderrc` to its canonical template and adds a new `make doctor` check — `check_aiderrc_template_sync` — that `cmp -s` compares the two files and surfaces drift before another six weeks pass. Fix is small; the generalizable lesson is bigger: when you build an assembly system, audit the files that *aren't* in it.

The default Aider model also moves from `claude-sonnet-4-20250514` (a dated Sonnet 4.0 preview) to the family alias `claude-sonnet-4-6`, which auto-tracks point releases without requiring further template churn.

## Reliability fix: the standards-review action

The [standards-review composite action](/blog/pr-review-bot/) failed to load in consumer repos with:

```
while scanning a simple key
could not find expected ':' (line 91, col 1)
```

Root cause: a Python heredoc inside a `run: |` block was indented at column 0. YAML's literal block scalar terminates the moment a content line has less indentation than the block, so the parser ended the scalar at the first heredoc line and tried to interpret Python as YAML. It choked on the colon in `if len(sys.argv) > 1 else "{}"`.

The fix moves the formatter to a sibling `format-results.py` invoked via `${{ github.action_path }}`. The YAML stays trivial, and the Python is independently testable. Two-file change ([#64](https://github.com/c65llc/coding-standards/issues/64)).

## Website surface area

The website itself caught up in this release:

- A **"How It Works"** page covering the architecture and the standards-sync pipeline end-to-end — useful for anyone evaluating the project before adopting it.
- A **Security section in the sidebar**, surfacing `sec-01` rather than burying it under "Standards".
- The build pipeline now **syncs security standards into the rendered docs automatically**, so the website can't drift from the canonical files.
- The blog backfilled posts covering release history back to 0.1.

## Antigravity Mission isolation

[Google Antigravity](https://antigravity.google.com) groups work into Missions — long-running, agent-driven tasks scoped to a feature or fix. The problem when multiple agents touch the same project: Claude Code, Cursor, and Aider have no native concept of an active Mission, so they don't know whether their work is in scope or scope creep.

1.1 ships a cross-agent advisory mechanism — `.gemini/active_mission.log` — and two helper scripts:

```bash
./scripts/mission-set.sh https://antigravity.google.com/missions/<id>   # at start
./scripts/mission-clear.sh                                              # on completion
```

Other agents check the log before starting work; if a Mission is active, they reference it in commits and avoid expanding scope. The full convention (feature bracketing, lifecycle, what "stale" looks like — i.e. a non-empty log more than ~7 days old) lives in `proc-04 § 5`, with the read protocol mirrored in `GEMINI.md` so every agent that consumes the standards picks it up automatically.

Alongside it, `.gemini/settings.json` ships a Postgres MCP entry — opt-in via `POSTGRES_MCP_DATABASE_URL` env var. When set, Gemini gets live schema introspection for migration and query work; when unset, the server fails to start gracefully and Gemini continues without it. `make doctor` warns when the entry is present but the env var is missing.

## Browser-agent UI validation

Antigravity, Claude Code (via Playwright MCP), and Cursor all have browser tools that can render and screenshot a UI. Until now there was no convention for *what to compare it against* — agents would render, agree it looked "fine", and merge. 1.1 introduces `assets/designs/` as a per-project reference directory, plus `proc-04 § 7: UI Change Validation` defining the protocol:

1. **Render** via dev server or the project's [Devloop](/standards/process/proc-04_agent_workflow_standards/#4-devloop-pattern-ui-projects) `/rebuild` endpoint.
2. **Capture** the rendered output with the agent's browser tool.
3. **Compare** against `assets/designs/<route-or-component>/<state>.png`.

The deliberate non-default: **pixel-diff is not the gate.** Font rendering, anti-aliasing, and sub-pixel layout drift swamp real changes. The agent surfaces the diff (side-by-side, overlay, or per-region delta) and a written summary; a human approves whether the change matches design intent. Pixel-diff gating is opt-in for projects that want to enforce it, with thresholds documented in `assets/designs/NOTES.md`.

The `assets/designs/` directory is **opt-in per project** — `setup.sh` doesn't auto-create it. Projects taking on UI work add it manually and copy in `templates/assets-designs-README.md.example`, which documents naming conventions, common state vocabulary (`default`, `loading`, `error`, `mobile`, `dark`, etc.), and the cross-agent invocation table.

For agents without native browser tools (Aider, Codex), the protocol relies on the project's [Devloop](/standards/process/proc-04_agent_workflow_standards/#4-devloop-pattern-ui-projects) `GET /snapshot` HTTP endpoint to normalize capture across all agents.
