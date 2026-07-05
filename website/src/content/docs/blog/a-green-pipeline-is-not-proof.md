---
title: "A Green Pipeline Is Not Proof"
date: 2026-07-05
authors:
  - name: C65 LLC
---

Alongside the [audit sweep](/blog/standards-1-5-audit-sweep/), 1.5 folds a batch of hard-won lessons into the architecture and process standards. They came out of real development on a TypeScript / Rust / Swift local-first monorepo — the kind of project these standards are meant for. Each one is a bug that a reasonable person would not have predicted, and that a green checkmark actively hid.

## A green release that never reached production

Twice, a release was cut, promoted, and reported green — while production never changed.

The first time, the deploy platform's build token had been silently rolled. Every in-repo check passed because the failure lived entirely outside the repo: the git host had no idea the token was dead. The second time, a force-push protection on the `release` branch blocked the fast-forward promote. Same symptom: pipeline exits zero, nothing ships.

The lesson is uncomfortable because it undercuts the thing we most want to believe: that a passing pipeline means the work is done. It doesn't. A pipeline proves the steps it ran exited zero. It cannot prove that a system it doesn't control — the deploy platform, its credentials, its branch rules — did what you asked. So `arch-08` and `proc-02` now require the release to **end by fetching the live deployment and asserting the new version is actually serving.** Necessary is not sufficient; the only proof that production updated is production.

## A stale tab that bricked every new one

The local-first app used a shared-worker leader/follower model — one tab owns the database, the rest coordinate through it. After a deploy, a browser tab left open from the *previous* version still held the leader lock. Every freshly loaded tab became a follower, probed the incompatible old leader, timed out, and retried the same doomed probe forever. The app was wedged, and nothing in the running code knew how to recover.

Two fixes, now in `arch-05`. **Version the coordination protocol**, so a new follower recognizes an incompatible leader and triggers takeover instead of trusting it. And **distinguish transient failure from persistent failure** — retry is for hiccups; a persistent leader timeout means re-elect, not retry. A follower that retries a permanent condition forever isn't resilient, it's stuck.

## Drift a warm build refused to show

This one is subtle. The repo commits generated cross-platform artifacts — wasm blobs, UniFFI bindings. To catch drift, CI regenerates them and diffs against what's committed. Straightforward, except it kept passing while the artifacts were genuinely stale.

The culprit was the warm build cache. An incremental `target/` directory happily produced the already-committed output from stale intermediate state; the drift only reproduced after a `cargo clean`. So the "regenerate and diff" gate was diffing against a lie. `arch-07` now requires the drift gate to **rebuild from a cold state** — clean first, or run in a fresh checkout — because a warm target masks exactly the drift the gate exists to catch.

## The one that fails in seconds vs. the one that waits

A smaller, sharper one for `arch-08`: two self-hosted runners sharing a machine produced collisions — duplicate listener stacks fighting over `_diag` paths, package-manager setup dirs racing on big fan-out PRs. The fix is isolation (each runner gets its own `HOME`, tool-cache, and work directory). But the lesson worth writing down was diagnostic: **an offline runner leaves a job queued and waiting; a misconfigured one fails at "Set up job" in seconds.** Same red check, opposite cause. Knowing which you're looking at saves an hour of debugging the wrong thing.

## Why these belong in the standards

None of these are exotic. They're the failure modes you only meet once you ship something real across more than one platform — and once you've met them, they're obvious. The point of a standards repo is to let the next team meet them as a paragraph in a document instead of as a production incident.

That's the trade every entry in this batch makes: someone already paid for the lesson. The standard is just the receipt, filed where the next person will look.
