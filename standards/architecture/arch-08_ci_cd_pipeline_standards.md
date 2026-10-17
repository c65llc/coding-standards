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
* `make ci` runs every lane in the committed routing table (§3.2); `make ci-<lane>`
  runs one. Both default to the same parallelism caps the runners use (§6.2), so
  local timings and flakes predict CI's.

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

The PR lane is **affected + fast**. Everything below is a requirement, not
advice: a repo with 40 workflows where half have no path filter and half have
no timeout is paying for CI minutes nobody asked for and waiting on wall-clock
nobody needs.

### 3.1 Every `pull_request` workflow bounds its cost

Every workflow triggered on `pull_request` (or `pull_request_target`) MUST
declare all three of:

* **`concurrency` with `cancel-in-progress`** — declared at workflow level (or
  on every job), with a group keyed on workflow + ref
  (`${{ github.workflow }}-${{ github.ref }}`), so a new push cancels the
  superseded run instead of paying for both. On `pull_request_target`,
  `github.ref` is the *base* branch, so key on the PR instead
  (`${{ github.event.pull_request.number }}`) or every PR targeting `main` shares
  one group and a push to one cancels its neighbours. Workflows that write shared
  state (release drafting, project sync) may set `cancel-in-progress: false`, but
  they still declare the group.
* **`timeout-minutes` on every job that runs steps** — a hung step must not burn
  the runner for the six-hour default. Pick a bound a little above the job's p95;
  a job that trips it has a problem worth seeing. A job that calls a reusable
  workflow (job-level `uses:`) cannot declare one; the called workflow's jobs
  declare theirs.
* **Path scoping** — one of:
  * a `paths:` / `paths-ignore:` filter on the trigger, for a workflow that is
    *not* a required check; or
  * a **paths-filter + always-run gate job**: a `changes` job classifies the
    diff (e.g. `dorny/paths-filter`), each lane runs `if:` its filter matched,
    and a single `ci-gate` job with `needs: [all lanes]` and `if: always()`
    fails only when a lane that *ran* failed. The gate is the only job listed as a
    required status check, so the PR resolves even when every lane was skipped. (A
    workflow-level `paths:` on a required check leaves the PR stuck "expected"
    when nothing matched — that is why the gate idiom exists.) See
    `templates/ci-gate.yml.example`; or
  * an explicit `# ci-hygiene: paths-exempt <reason>` comment, for the few
    workflows whose work genuinely does not depend on which paths changed
    (auto-labelers, Dependabot auto-merge, secret scans). The reason is
    mandatory; the marker is a declaration, not an opt-out.

Document each lane's filter (and why it is what it is) next to the filter. The
`common/ci-workflow-hygiene` lint check warns on any `pull_request` workflow that
is missing one of the three.

### 3.2 Commit the routing table

The "which checks does this change need?" mapping MUST be a committed artifact,
`.github/ci/routing.yml` (see `templates/ci-routing.yml.example`), consumed by
**both** the workflow (`dorny/paths-filter` reads it as its `filters` file) and
the agents/humans deciding what to run locally (agent configs point at it; lane
`<name>` ⇒ `make ci-<name>`). A routing table that lives only in `AGENTS.md`
prose, next to workflows that filter on their own copies of the globs, drifts the
first time someone adds a directory. One file, two consumers, no drift.

### 3.3 Tier the heavy suites

* **PR lane = affected + fast.** Expensive matrices — full cross-browser E2E,
  visual-regression across themes, multi-OS builds, every simulator — run on a
  reduced set per PR (e.g. one browser, one OS) and the **full** matrix on the
  **merge queue** and/or a **nightly** schedule plus manual dispatch. State the
  reduction explicitly; never let "we only test one browser on PRs" be a silent
  gap.
* **Build once, reuse.** A PR run builds each artifact once and hands it to
  downstream jobs as an artifact or via the task-runner cache (§2); lanes do not
  rebuild shared packages independently.
* **Remote cache is required for monorepos.** A workspace with a task graph
  (turbo, nx, bazel, gradle) or a Rust workspace of any size MUST run CI with a
  remote/task cache (turbo remote cache, `sccache`/`cargo` cache, gradle build
  cache) so unchanged units of work are restored, not rebuilt. Give it the bounded
  budget and eviction described in §4.

### 3.4 Budget the minutes

Every PR run reports what it cost. The gate job (or the last job) writes the
run's **total CI minutes** — the sum of its jobs' wall-clock — to the step
summary, next to a **soft per-PR budget** declared in the workflow (an `env` such
as `CI_BUDGET_MINUTES`). Exceeding the budget emits a warning annotation; it does
not fail the run. The point is that the cost is visible on every PR, so a lane
that quietly doubled is noticed the week it happens, not at the invoice.

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
* **Isolate every runner on a shared host.** Each runner MUST get its own `HOME`,
  tool-cache, and `_work` directory. Never share package-manager setup dirs (e.g.
  `~/setup-pnpm`) across runners on one machine — sharing causes duplicate-listener
  `_diag` collisions and `pnpm/action-setup` races (`ENOTEMPTY`/reflink) on large
  fan-out.
* **Diagnose by failure mode.** An *offline* runner yields a run that stays
  **queued/waiting** (nothing schedules it). A *collision/misconfig* yields a run
  that **fails at "Set up job" within seconds**. Same-looking red check, opposite
  cause — read which one before touching the code.

### 6.1 Every step passes on a locked, headless, interchangeable runner

Self-hosted runners are remote machines with the screen locked and no human in
front of them. A job MUST succeed on **any** runner in the pool under exactly
those conditions. Concretely:

* **No login keychain, no `store-credentials`, no GUI prompts.** On a locked
  Mac, `security` "cannot write to a locked keychain and has no UI to prompt
  into", so anything that touches the login keychain — `notarytool
  store-credentials`, `security unlock-keychain` on `login.keychain-db`,
  `security import` into it — fails with "User interaction is not allowed" on
  every runner except the one someone happened to leave unlocked. The same goes
  for `osascript`/AppleScript, `open -a`, and any tool that pops a dialog.
* **Secrets go from the secret store to the consuming command.** Pass them
  straight to the command that needs them (`notarytool submit --apple-id …
  --team-id … --password "$PW"`, `codesign` against an explicit keychain), or
  into a **job-scoped ephemeral keychain** created with `security
  create-keychain` under `$RUNNER_TEMP`, unlocked by path, and deleted on exit.
  Nothing lands in the runner's login keychain.
* **Simulators and emulators are booted headless inside the job** (`xcrun
  simctl boot` / `emulator -no-window`) and shut down after. GUI/UI tests run
  offscreen, or on a dedicated interactive lane that is **never a required
  check**.
* **Runner interchangeability.** Nothing persisted on one machine (a keychain
  entry, a logged-in simulator, a tool installed by hand) may be required by a
  later job. If the job cannot be re-run on the other runner in the pool, it is
  not done.
* **A `runner-canary` workflow** exercises the lane on a schedule with the
  screen locked and no user session, so a runner that drifts into needing a
  desktop is caught by the canary, not by the release.

The `common/headless-ci` lint check warns on workflows that contain
`store-credentials`, `unlock-keychain … login`, `osascript`, or `open -a`.

### 6.2 Load caps when a runner shares a development machine

A dedicated runner box is the recommendation. When a runner shares a laptop or
desktop with a developer, a single CI job can pin every core and stall the
person at the keyboard. Shared boxes MUST apply all of the following and
document them (e.g. in `docs/ci-releases.md`):

* **Cap parallelism at the runner level, not per workflow.** Set the caps in
  the runner service's environment so every job inherits them and no workflow
  can forget: `CARGO_BUILD_JOBS`, `MAKEFLAGS=-j<n>`, turbo `--concurrency` /
  `TURBO_CONCURRENCY`, `xcodebuild -parallel-testing-worker-count <n>`,
  `pnpm --workspace-concurrency <n>`, pytest `-n <n>`. Target **at most half
  the cores** on a shared box.
* **Run the runner service at reduced priority** — `nice` and
  `taskpolicy -c background` on macOS, a cgroup CPU weight on Linux — and with
  an IO class below interactive, so the developer's editor and browser win every
  contention.
* **One lane per runner.** Serialize heavy jobs onto a runner with a
  concurrency group keyed on something known *before* dispatch — the runner
  label or a matrix value (`group: apple-lane-${{ matrix.target }}`); the
  `runner` context is not available in job-level `concurrency`, so
  `runner.name` cannot form the group — or give each heavy lane its own runner
  label. Heavy matrices go to the merge queue or nightly (§3.3), never fan out
  across a shared box on every PR.
* **`make ci` defaults to the same caps** so the local gate and the runner
  behave alike (§1): a developer who runs `make ci` before pushing sees the same
  parallelism, the same timings, and the same flakes the runner will.

## 7. Deploy Channels & Promotion

For products that deploy from CI, separate **staging** from **production** by
channel and gate promotion explicitly:

* Pushes to the integration branch deploy to a **staging/preview** channel; production
  deploys are gated on an explicit promotion (a long-lived `release` branch, a tag,
  or a manual approval). **Never deploy production off arbitrary feature branches.**
* If the platform's branch controls take no wildcard, use a single long-lived
  promotion branch (`release`), not a pattern (`release/*`), and promote by
  fast-forwarding into it.
* **A green pipeline is not proof production updated.** The release job MUST end
  with an automated production smoke check — fetch the live deployment and assert
  the new version/build — not merely trust that the promote step exited 0. Deploy
  credentials and branch protections live *outside* the repo and fail invisibly (a
  rolled/deleted build token, a force-push-protected `release` branch blocking a
  fast-forward promote). An in-repo green is necessary but **not** sufficient.
* See [proc-02_git_version_control_standards.md](../process/proc-02_git_version_control_standards.md)
  §5 for the release-version vs build-version model and the scripted release PR
  that drives promotion.
