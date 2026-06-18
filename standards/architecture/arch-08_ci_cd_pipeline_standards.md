# CI/CD Pipeline Standards

These standards govern how continuous-integration pipelines are structured so they
stay **fast, cheap, and trustworthy** as a repository grows. They assume the
`make`-based automation in
[arch-02_automation_standards.md](./arch-02_automation_standards.md) and the
workspace model in
[arch-06_monorepo_workspace_standards.md](./arch-06_monorepo_workspace_standards.md).

CI minutes cost real money, and per-job setup overhead is itself a cost. Treat the
pipeline as something to be measured and optimized, not left to sprawl.

## 1. Local Gate Mirrors CI Exactly

* The local gate (`make ci`) MUST run the same checks as the required CI gate —
  same linters, same coverage thresholds, same build. "Green locally, red in CI"
  (or the reverse) means the gate has drifted; fix the drift, don't paper over it.
* CI SHOULD invoke the same `make` targets a developer runs, so there is one
  definition of "passing" and no CI-only logic to keep in sync.

## 2. Consolidate the Required Gate; Build Once

* Prefer **one consolidated required gate** over a sprawl of overlapping per-member
  workflows that each cold-install dependencies and rebuild shared packages. A
  task runner with a dependency graph (turbo, nx, bazel, gradle) runs each unit of
  work once across the workspace.
* **Build each artifact exactly once per run.** Two jobs building the same output
  in parallel waste minutes and can race on a shared output directory. Produce the
  build once and let dependent jobs consume it.
* Keep the **required** gate minimal and fast. Move advisory checks (dependency
  CVE audit, license scan, link-checking) into **separate** jobs that do not block
  merge — a transitive advisory should not wedge the required gate.

## 3. Don't Run Everything on Every PR

* **Cancel superseded runs.** Set a concurrency group keyed on
  workflow + ref with cancel-in-progress, so a new push cancels the previous run
  instead of paying for both.
* **Path filters / affected-only.** Only run a member's gate when files in its
  dependency closure changed. Document each member's filter (and why it is what it
  is) next to the filter.
* **Tier the heavy suites.** Expensive matrices — full cross-browser E2E,
  visual-regression across themes, multi-OS builds — run on a reduced set per PR
  (e.g. one browser) and the **full** matrix on a nightly schedule plus manual
  dispatch. State the reduction explicitly; never let "we only test one browser on
  PRs" be a silent gap.

## 4. Caching

* Cache the expensive, deterministic inputs: dependency stores, compiled
  artifacts, browser binaries, task-runner outputs.
* **Pin cache-action and tool versions to an exact version** — never a floating
  major tag — so a cache key or action upgrade can't silently change behavior
  mid-stream.
* Key caches precisely (OS + tool version + lockfile hash + browser set). Use
  `restore-keys` to fall back from a narrow set to a superset, never the reverse.
* Give remote/task caches a **bounded budget with eviction** (LRU to a size cap on
  a schedule). An unbounded cache grows until it costs more than it saves.
* On a **persistent self-hosted runner**, prefer the runner's local on-disk store
  over re-downloading a cache tarball every job — the redundant fetch can dominate
  setup time.

## 5. Artifacts & Retention

* Set an explicit short retention on build/test artifacts (screenshots, logs,
  coverage reports) — they accumulate storage cost. A week is a reasonable default
  unless a longer window is needed for a specific audit.
* Upload diagnostic artifacts (failing screenshots, logs) on failure so a red run
  is debuggable without re-running.

## 6. Self-Hosted Runners

Self-hosted runners trade per-minute cost for operational responsibility. If used:

* A job pinned to a self-hosted label **queues indefinitely if no matching runner
  is online** — there is no hosted fallback. A check stuck "queued/pending" on a
  self-hosted job means the runner is down, not that the code is slow. Document the
  runner's labels and who owns it.
* `runs-on` labels must match the runner's actual auto-labels (a macOS runner has
  no `linux` label). A mismatch means the job never schedules.
* Pin the toolchain the runner self-provisions (e.g. via a `rust-toolchain.toml`,
  `.nvmrc`, `.tool-versions`) so a fresh runner reproduces the gate deterministically.
* **Avoid shared mutable state between concurrent runners on one host.** Two
  runners self-installing into the same shared tool directory will race and corrupt
  it (e.g. `ENOTEMPTY` during a parallel dependency-manager install). Give each
  runner its own home/work directory, or reduce concurrency, or move the
  self-install into per-runner scope.

## 7. Deploy Channels & Promotion

For products that deploy from CI, separate **staging** from **production** by
channel and gate promotion explicitly:

* Pushes to the integration branch deploy to a **staging/preview** channel; production
  deploys are gated on an explicit promotion (a long-lived `release` branch, a tag,
  or a manual approval). **Never deploy production off arbitrary feature branches.**
* If the platform's branch controls take no wildcard, use a single long-lived
  promotion branch (`release`), not a pattern (`release/*`), and promote by
  fast-forwarding into it.
* See [proc-02_git_version_control_standards.md](../process/proc-02_git_version_control_standards.md)
  §5 for the release-version vs build-version model and the scripted release PR
  that drives promotion.
