# Monorepo & Workspace Standards

These standards apply to repositories that host multiple packages, apps, or
toolchains in a single tree (pnpm/npm workspaces, Cargo workspaces, Gradle
multi-project builds, Go modules, etc.). They complement the Clean Architecture
layering in [core-standards.md](../shared/core-standards.md) — that describes how
*layers* depend on each other; this describes how *workspace members* are built,
checked, and kept from drifting apart.

## 1. Workspace Layout

* A single repository MAY contain multiple workspace members: shared libraries,
  deployable apps, and tools. Group them by kind (`packages/`, `apps/`,
  `crates/`, `tools/`) so the dependency direction is visible from the path.
* Each member owns its manifest (`package.json`, `Cargo.toml`, `build.gradle`)
  and its own build/test/lint pipeline. The root orchestrates members; it does
  not reach inside them.
* Shared business logic lives in inner members (libraries); deployable apps are
  outer members that compose libraries. Apps MUST NOT import from one another —
  extract the shared part into a library instead.

## 2. Multiple Toolchains Are Kept Separate

A repo may host more than one language toolchain (e.g. a JS/TS workspace built
with pnpm + a task runner, and a Rust workspace built with cargo).

* **Keep the toolchains deliberately separate.** Do not make one task runner
  orchestrate another language's build. A JS task graph should not invoke
  `cargo`, and vice versa — each has its own dependency graph, cache, and CI gate.
* Provide one `make` entry point per toolchain gate (`make ci-js`, `make ci-rust`)
  and a top-level `make ci` that runs both, so a contributor never has to know
  which toolchain a change touched.
* Document the split in `CONTRIBUTING.md`: which directories belong to which
  toolchain, and which command gates each.

## 3. Per-Member Pipeline Ownership

* **Each member owns its scope, not its own style.** Shared style/config
  (formatter options, lint rules, TS compiler options) lives in a single root
  config that members inherit or *extend* — never fork. A member may extend the
  root config to add a member-specific plugin (e.g. an Astro or Vue parser) but
  MUST NOT override shared options, or the options silently drift between members.
* A member MAY own its own *ignore* set (e.g. `.prettierignore`,
  `.eslintignore`) because the generated/vendored paths it excludes are genuinely
  member-specific. When adding one, copy the closest sibling's list rather than
  inventing a new shape, so the only differences are the ones that member needs.
* CI runs each member's own check over its own tree. A repo-wide check at the
  root covers shared config and any member without its own gate. Together they
  must leave no file unchecked.

### Verify with the member's own gate

A passing root-level or aggregated check is **not** sufficient evidence that a
member is green. Before pushing a change to a member, run that member's full
local gate (`make ci` from inside the member, or `<runner> --filter <member> ci`)
— the member's gate is the authoritative one CI reproduces.

## 4. Run the Build, Not Just the Typecheck

In many workspaces the per-member `typecheck` (e.g. `tsc --noEmit`) and the CI
`build` (e.g. `tsc -b` with project references) check **different file sets**.
The build is usually the stricter of the two:

* `typecheck` configs commonly **exclude test files**; the project-reference
  build **includes** them.
* Therefore a change that widens a shared interface can pass `typecheck` locally
  yet fail CI `build`, because every test double / inline fake of that interface
  now fails to compile.

**Rules:**

* When you widen or change a shared interface (a port, a trait, a public type),
  grep the *whole* workspace for every implementer — including object-literal
  fakes annotated `: TheInterface`, not just `class X implements Y` — and update
  them all.
* Run the member's `build` (or `make ci`), not just `typecheck`, before pushing.
  Treat "typecheck + lint + test all pass" as insufficient until the build is green.

## 5. Path & Alias Resolution Must Be Complete

When a member maps a package to a path alias (in `tsconfig`, a bundler config, a
test-runner config, etc.), a **bare-package alias shadows unlisted subpaths**.
Mapping `@scope/pkg` does not automatically map `@scope/pkg/sub` — the subpath
silently resolves somewhere else (or fails only in one tool).

**Rules:**

* List **every** subpath alias a member imports, in **every** resolver that
  member uses (the bundler config, the test-runner config, and the typechecker
  config must agree). A subpath that resolves in the bundler but not the
  typechecker is a latent break.
* When you add a new subpath import, add its alias to all resolvers in the same
  change. When copying a member's alias map to a new member, copy it whole.
* Prefer the package manager's native workspace resolution over hand-maintained
  alias maps where possible; reserve aliases for cases the resolver can't cover.

### Alias ordering & config parity

* **Register specific subpath aliases before any catch-all/prefix alias.** A
  greedy `@pkg/core` catch-all that resolves ahead of `@pkg/core/<subpath>`
  shadows the subpath — it resolves to the package `index.ts` or a
  dir-not-found. Order matters: most-specific first, prefix last.
* **Keep the alias map in sync across the bundler *and* the test-runner config**
  (e.g. `vite.config.ts` and `vitest.config.ts`). Drift between them produces
  "works in the app, fails in tests" (or the reverse) — a trap CI can mask
  behind a misleading, unrelated error.
* Prefer package `exports` subpath maps over hand-rolled aliases where possible;
  a single `exports` map is honored by every resolver, so it can't drift.

## 6. Generated & Committed Artifacts

Some workspaces commit build outputs that are derived from source (e.g.
WASM/`.d.ts` bundles, generated clients, protobuf stubs) and gate CI on
"the committed artifact matches a fresh rebuild" (`git diff --exit-code` after
regenerating).

* These artifacts MUST be regenerated and committed whenever their source — or a
  **dependency that affects codegen output** — changes. A dependency bump can
  change generated bytes even with no source edit.
* **An incremental rebuild over a warm cache can reproduce stale output** and
  show no drift locally, then fail the CI gate. Reproduce the gate with a *clean*
  build (`cargo clean`, clear the codegen cache) before trusting a "no drift"
  result.
* Pin the codegen toolchain (compiler version, codegen plugin version) so the
  output is deterministic across machines and matches the CI runner.

### A failing drift gate MUST offer an auto-fix path

"Artifact is stale — regenerate and commit" is a diagnosis, not a remediation.
A gate that stops there pushes the regeneration onto a human who has to find the
right machine, the right toolchain and the right command, and it is exactly that
hand-off where the determinism bugs below hide. Every drift gate (committed
bundles, generated bindings, visual/snapshot baselines, golden vectors) MUST
provide at least one of:

* **(a) Label-triggered bot commit.** When the PR carries an opt-in label (e.g.
  `regen`), the *pinned platform runner* regenerates the artifact and pushes it
  to the PR branch as a bot commit. Opt-in keeps the default fast-fail and makes
  the regeneration an explicit, reviewable action; running it on the pinned
  runner — never a laptop — is what makes the result reproducible.
* **(b) Uploaded artifact + patch + one-line apply.** The failing job uploads
  the regenerated artifact *and* a `git diff` patch as a workflow artifact and
  prints the single command that applies it, e.g.
  `gh run download <run-id> -n regen-patch && git apply regen.patch`. The
  developer never has to reproduce the runner's environment.

A manual `workflow_dispatch` that re-renders baselines and then tells the
developer to "download the snapshot artifacts and commit them" satisfies neither
option: it is a second pipeline the developer has to know about, not a fix path
attached to the failure.

Two companion rules keep the gate from firing for predictable reasons:

* **Regenerate before compare when declared inputs change.** Each committed
  artifact declares its inputs (design tokens, schema, emitter/generator
  source, the lock file for the codegen toolchain). When a PR touches a declared
  input, the gate regenerates *first* and then compares, so downstream tests see
  fresh output and the only possible failure is "regeneration is not
  committed", not "the test ran against a stale artifact".
* **Cache baselines by input hash.** Key the cached baseline (rendered snapshot,
  generated binding, built bundle) on a hash of its declared inputs plus the
  pinned toolchain version. Unchanged inputs MUST never re-render; a cache miss
  is the signal that regeneration is required.

### Determinism-inputs checklist

A cold rebuild is only a meaningful comparison when every input that reaches the
bytes is pinned. Before committing a generated artifact, and whenever a drift
gate fails with no source change, check:

| Input | What goes wrong | Pin it with |
| --- | --- | --- |
| **Source paths** | The compiler embeds absolute paths (`/Users/<user>/...`, `/home/<user>/...`) in debug info and panic strings; two developers produce different bytes from identical source | `--remap-path-prefix=$PWD=/src` (Rust, via `RUSTFLAGS` or `.cargo/config.toml` *in the repo*), `-ffile-prefix-map` / `-fdebug-prefix-map` (C/C++), `-trimpath` (Go) |
| **`producers` section** | wasm toolchains record exact compiler/linker versions and feature flags in a custom `producers` section; a patch-level toolchain difference changes the bytes | Strip it on output: `wasm-opt --strip-producers`, `wasm-strip`, `wasm-bindgen --remove-producers-section` |
| **User-level toolchain profiles** | `~/.cargo/config.toml` `[profile.release]`, a global `~/.gradle/gradle.properties`, user `npmrc`/`yarnrc` or `~/.config/...` flags silently override the repo's build profile | Forbid them in the regeneration path: the gate runs with `CARGO_HOME`/`GRADLE_USER_HOME` pointed at a clean directory, *and* a lint refuses to proceed if a user-level profile section is present |
| **Host triple** | The host's target triple (`aarch64-apple-darwin` vs `x86_64-unknown-linux-gnu`) reaches the artifact via build scripts, `cfg` evaluation and linker defaults | Regenerate only on the pinned platform runner; record the expected host triple next to the artifact and fail fast when it differs |
| **Generator versions** | `wasm-pack`, `wasm-bindgen`, `uniffi-bindgen`, `protoc`, design-token emitters: an unpinned `latest` changes output on the next install | Pin the exact version in the repo (lock file, `rust-toolchain.toml`, `.tool-versions`, `package.json` `devDependencies` with an exact version) and assert it in the gate before regenerating |

`lint-standards.sh` ships the `artifact-hygiene` common check, which scans
committed `*.wasm`, `*.a`, `*.so`, `*.dylib` and `*.jar` files for embedded
`/Users/` and `/home/` paths and WARNs with the offending artifact (username
redacted). A WARN there means the first row of this table has been missed.

### Worked example: one wasm drift gate, five commits

A shared-core workspace committed its `pkg/*_bg.wasm` bundle and gated CI on a
cold rebuild. The gate went red on `main` with no source change, and it took five
commits to make it trustworthy (paths anonymised):

1. **Gate red on `main`.** The committed bundle no longer matched the runner's
   rebuild. The committed bytes were correct for the laptop that built them.
2. **"Compared laptops, not source."** The diff was entirely
   `/Users/<user>/src/core/...` strings embedded in panic messages and debug
   info. Fix: `--remap-path-prefix` in the repo's `.cargo/config.toml` so every
   machine emits `/src/...`.
3. **Host-agnostic hygiene.** The `producers` section still recorded the local
   toolchain; strip it on output and build from the pinned runner only.
4. **Regenerate.** With inputs pinned, regenerate once on the runner and commit
   the result — the first artifact that any other machine could reproduce.
5. **"A personal cargo profile can no longer drift the committed wasm."** A
   developer's `~/.cargo/config.toml` `[profile.release]` had been overriding
   `opt-level`. A pre-regeneration check now refuses to run when a user-level
   profile section is present.

Every one of those failures was predictable from the checklist above, and none
of them was a bug in the source. With the auto-fix path in place the first
commit would have been a bot regeneration from the pinned runner, and the
remaining four would have surfaced as a single, reviewable diff rather than as
days of a red `main`.

## 7. Workspace Dependency Hygiene

* No circular dependencies between members. Enforce with a tool
  (`madge`, `cargo-deny`/`cargo tree`, `dependency-cruiser`) in CI.
* Align shared dependency versions across members — a single version of each
  third-party library per workspace, hoisted where the package manager supports
  it. Divergent versions cause duplicate bundles and subtle behavior differences.
* Commit a single lock file per toolchain at the workspace root. Install from the
  lock in CI and in fresh worktrees (see
  [proc-04_agent_workflow_standards.md](../process/proc-04_agent_workflow_standards.md)
  § Worktree Hygiene).
