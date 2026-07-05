---
title: "Standards 1.5: The Audit Sweep"
date: 2026-07-05
authors:
  - name: C65 LLC
---

Every few releases we stop shipping features and turn the audit on ourselves. This is one of those releases. We ran a full-repo sweep — scripts, CI, docs, and the standards documents themselves — and it surfaced about thirty distinct issues. 1.5 lands the fixes.

The interesting part isn't the count. It's what the count was made of: not one big broken thing, but thirty small ones, each individually easy to wave off, that together added up to a repo quietly drifting from the standards it publishes.

## The shape of the drift

A few themes ran through almost everything we found.

**Portability assumptions that only held on Linux.** The compliance linter (`lint-standards.sh`) crashed on `--format json` and `--format sarif` when there were zero findings — but only under bash 3.2, which is exactly what ships on macOS, and exactly the path the PR-review action runs. `gh-task` used `grep -oP`, a GNU-only flag that silently returns empty on a Mac. Both had lived in the tree for months because CI runs on Ubuntu and nobody hit them locally until they did.

**Docs describing a repo that no longer existed.** The agent configs still told assistants to "strictly follow" `arch-03` — a standard we had deleted. Go and Elixir shipped as full language standards but were missing from every agent config's detection map. The README said the standards-review workflow was "installed automatically by `make setup`" when in fact it required an explicit `--workflow` flag. None of these break a build. All of them mislead a reader — or an agent — at exactly the moment they're trying to trust the document.

**Gates that didn't gate.** The Definition-of-Done workflow ran linting, coverage, and security scans and then swallowed every failure with `|| true`. It looked like a quality gate and enforced almost nothing. The lifecycle-sync automation queried the first 100 project items and quietly stopped working past that. A "green" pipeline that proves nothing is worse than no pipeline, because it manufactures false confidence.

**A `source` that would run anything.** `gh-task` read its state file with `source .gh-task-state` — executing whatever a tampered or mis-merged file put there, with your shell's privileges. That one we treated as a security fix, not a cleanup.

## Batching the fix

Thirty issues is too many for one pull request and too many to merge one-at-a-time without losing the plot. We grouped them by kind — script bugs, doc consistency, CI hardening, chores, dependency triage, standards enrichment — and shipped each as its own reviewable PR that closed a handful of issues at once. Each batch stated what it fixed, how it was verified, and what it deliberately left for later.

That structure paid off when the batches started depending on each other. The new "dogfood" CI job — which runs our own linter against our own repo and asserts the JSON and SARIF output is valid — is a direct regression guard for the zero-findings crash. It literally cannot pass until the crash fix is present. So the batches had a merge order, and the order was part of the plan, not an afterthought.

## What actually shipped

The headline items:

- **The linter now dogfoods.** CI runs `lint-standards.sh` against this repo on every push and fails if the tool crashes or emits malformed output. The bug that would have shipped a broken SARIF file to every consumer is now caught here first.
- **Secret scanning that teams won't turn off.** We ship a TruffleHog config with a documented allowlist, verification off by default, and merge-blocking on real findings. Noisy scanners get disabled; a scanner with good false-positive hygiene stays on.
- **Release automation.** A release-drafter workflow keeps a categorized draft release current from merged PRs and auto-labels them from their commit type. The changelog stops being a manual chore.
- **Actions pinned to SHAs, Dependabot grouped.** Every workflow now pins actions to an exact commit, and Dependabot batches the updates so they stop piling up as one-PR-per-bump.
- **Standards enrichment** from real cross-platform work — the subject of [the companion post](/blog/a-green-pipeline-is-not-proof/).

There's a satisfying symmetry to fixing your own linter's crash by making your CI run your own linter. The repo is a little more like the thing it tells everyone else to build. That's the whole point of doing this on a schedule.
