---
title: "Standards 1.2: Safe Setup"
date: 2026-04-16
authors:
  - name: C65 LLC
---

Last release was about governance and drift. This one is about a quieter promise we were breaking: **installing the standards into your project should never destroy the work you've already done there.**

The feedback that kicked off 1.2 came from a real adoption. Someone ran `setup.sh` against a repo that already had an `AGENTS.md`, a `CLAUDE.md`, and a CI workflow. When the dust settled, their `AGENTS.md` had been overwritten, the new `CLAUDE.md` was full of literal `{{PROJECT_NAME}}` tokens, configs for five agents they don't use had been dropped into the root, and a `standards-review.yml` workflow had appeared without anyone asking for it. They cherry-picked out what they wanted and sent back a note: *here's what we rejected, and why.*

Four problems. One underlying mistake — **defaults that assumed more than they should**. This release fixes all four and ties them together around a single idea: **stage, don't clobber.**

## One rule, applied four ways

`setup.sh` now routes every file it wants to write through the same gate that `sync-standards` has used for months: `should_assemble()`. If the target doesn't exist, write it. If it exists and still matches the last assembled hash, overwrite it. If it exists and has been customized, write the new version to `.standards-pending/<file>` instead and leave the original alone.

The infrastructure for this wasn't new — we'd built it for re-syncs. What was new was pointing `setup.sh` at it. The assembly loop is now a single function in `scripts/lib/assembly.sh`, shared by both scripts. First-run and re-sync are the same flow. That one change closes the "clobbered AGENTS.md" complaint completely.

## Only the agents you actually use

`--agents` now defaults to `detect`. When you run `setup.sh`, it probes for `CLAUDE.md`, `.cursorrules`, `.github/copilot-instructions.md`, `.gemini/GEMINI.md`, `AGENTS.md`, `.aiderrc` — and only installs configs for the agents it finds. A greenfield project gets a short message listing what's available, not six unused dotfiles.

The old "install everything, let the user delete what they don't need" default was well-intentioned but wrong. The escape hatch is still there — `--agents all` if you really do want everything, or `--agents claude-code,cursor` for an explicit list — but the default respects what's already in your tree.

## Template variables that don't ship

The base `CLAUDE.md` template has three placeholders: `{{PROJECT_NAME}}`, `{{PROJECT_OVERVIEW}}`, `{{KEY_COMMANDS}}`. Until this release, the assembler wrote them through as literal `{{...}}` tokens. If you weren't paying attention, your repo ended up with a `CLAUDE.md` that greeted the next agent with `# {{PROJECT_NAME}} — Claude Code Guide`.

Now: `{{PROJECT_NAME}}` resolves from `package.json`, `Cargo.toml`, `pyproject.toml`, or the directory name — whichever comes first. The two content placeholders become `<!-- TODO(standards): -->` markers that the merge skill fills in. The shipped file never contains `{{`.

## The workflow is opt-in

The `standards-review.yml` workflow is useful, but it's also opinionated — it can conflict with a project's existing CI. 1.2 gates its install behind `--workflow`. When you skip it, setup prints the one-liner to install it later. No more workflow showing up unannounced.

## The handoff: MERGE_PLAN.md

Here's where it gets interesting. When `setup.sh` stages anything to `.standards-pending/`, it also writes a `MERGE_PLAN.md` alongside it — a short briefing that lists the files to reconcile, the agents detected in the project, any unresolved `<!-- TODO -->` markers, and three ways to finish the job:

- `/merge-standards` in Claude Code
- the `merge-standards` command in Cursor
- `make merge-standards` at the CLI

All three read the same MERGE_PLAN.md. The design goal is that `setup.sh` doesn't *finish* the install — it hands a complete, agent-agnostic briefing to whichever LLM the user prefers, and that agent finishes the install against the user's actual preferences. You pick the tool; we give it the context.

## What this didn't require

This release isn't a rewrite. The pending-mode infrastructure already existed — `sync-standards.sh` had been using it for months. The 1.2 change lifts that loop into `scripts/lib/assembly.sh` and points `setup.sh` at it. Most of the new code is in four small libs (one per concern: assembly, detection, template vars, merge plan), the 17 functional tests that enforce each fix, and the docs that explain it.

Four rejections from one adoption. Four commits. Four test groups that will keep them from regressing. That's the whole release.
