# Cross-Platform Shared-Core Standards

These standards apply to products that ship the same experience across multiple
platforms (web, native desktop, mobile) from one codebase. They build on the
"pure render logic" pattern in
[arch-05_resilient_architecture_patterns.md](./arch-05_resilient_architecture_patterns.md)
§2 and the workspace rules in
[arch-06_monorepo_workspace_standards.md](./arch-06_monorepo_workspace_standards.md).

The governing principle: **logic is shared and written once; rendering is
per-platform.** A behavior difference between platforms is a bug, not a platform
characteristic.

## 1. Shared Core, Per-Platform Shells

* Put all platform-agnostic logic — domain rules, data model, parsing,
  serialization, reconciliation, business calculations — in a **single shared
  core** (e.g. a Rust crate compiled to WASM for web and exposed via FFI for
  native; a TS package consumed by every web app). The core has no UI and no
  platform imports.
* Each platform has a **thin shell** that renders the core's output using native
  primitives (SwiftUI on Apple, Compose on Android, the DOM on web). Shells
  contain rendering and platform glue only — no business logic.
* **Prefer a native shell over wrapping a web view** when platform-native feel is
  a product goal. A web view embedded in a native app is acceptable as an interim
  step (document it as such in an ADR), but the target is a native rendering of
  the shared core.

### Single source of truth for shared data/logic

Data and logic consumed by more than one shell live in the core, exposed through
one API that every shell calls. Do not reimplement a rule (a permission check, a
mapping, an ordering) in each shell — when it changes, the shells silently
diverge. Example: a "which app owns this folder" mapping belongs in the shared
core and is consumed identically by the web component and the native component.

## 2. Conformance / Golden-Vector Testing Is the Parity Gate

A shared core is only trustworthy if every binding produces identical results.
Enforce this with **conformance testing**: a single, language-neutral set of
input→expected-output vectors that every platform binding runs.

* Maintain the vectors as data (JSON/CSV/binary fixtures) in one place, with a
  documented schema. Each binding (the Rust unit tests, the WASM harness, the
  Swift FFI tests, the Android JNI tests) loads the *same* vectors and asserts
  the same outputs.
* A change to core behavior updates the vectors once; every binding's conformance
  test then re-verifies against the new expectation. Diverging output on any
  platform fails CI.
* Golden vectors are especially important for serialization round-trips, text
  diffing/merging, and any algorithm where a one-byte difference across platforms
  corrupts data.

## 3. FFI Boundary Coverage

When the core crosses a foreign-function boundary (WASM, UniFFI, JNI, C ABI),
the boundary itself is a tested surface, not an afterthought.

* **Export smoke tests:** assert every exported symbol is reachable from the host
  language and round-trips a basic value. A binding that fails to generate or
  link is caught here, not at runtime on a device.
* **Golden parity at the boundary:** run the conformance vectors *through* the FFI
  layer, not just against the core directly — serialization across the boundary is
  where encoding/endianness/null-handling bugs live.
* **Boundary/edge cases:** empty inputs, maximum sizes, all-optional-fields-absent,
  invalid UTF-8, and other adversarial inputs that exercise the marshaling code.
* Pin the binding generator version (e.g. `wasm-pack`, `uniffi-bindgen`) and treat
  the generated bindings as committed generated artifacts (see
  [arch-06](./arch-06_monorepo_workspace_standards.md) §6).
* **Lockstep pins across repos.** When the core is consumed as a package by shells
  in *separate* repositories, the declared pin and its resolved lockfile move
  together — `Package.swift` + `Package.resolved`, `package.json` + the lockfile,
  `Cargo.toml` + `Cargo.lock` — through **paired PRs**: the core repo tags the
  release; the shell repo's PR bumps the declared pin *and* the resolved pin in
  the same commit; each PR body names its partner (`Pairs with org/core#123`). A
  bumped `Package.swift` beside a stale `Package.resolved` builds something other
  than what the diff says. The shell's CI asserts the two agree (a fresh
  `swift package resolve` / `npm ci` / `cargo build --locked` changes nothing),
  the core's release checklist lists every shell repo that must pair, and the
  pairing rule is recorded as an ADR so a new shell follows it without being told.
* **The core's side of the contract** — opaque handles, create/destroy pairing,
  borrowed-buffer lifetimes, null-handle tolerance, status codes, and catching
  every exception at the `extern "C"` boundary — is
  [lang-14 §10](../languages/lang-14_cpp_standards.md#10-the-c-abi-boundary) for a
  C++ core and [lang-08 §21](../languages/lang-08_rust_standards.md#21-ffi--wasm-facades)
  for a Rust core. A wrapper (Swift, Kotlin, C#, Python) relies on exactly those
  guarantees and no others; check `<prefix>_abi_version()` at load time.

### Cold-rebuild drift gate for committed generated artifacts

If you commit generated cross-platform artifacts — wasm `pkg/*_bg.wasm`, UniFFI
Swift/Kotlin bindings, design-token outputs — add a CI gate that regenerates them
and fails if the result differs from what is committed.

* **Rebuild from a cold/clean state before diffing.** A warm incremental build
  target (`target/`) *masks* artifact drift: a naive "regenerate and diff" on a
  warm target can pass falsely because stale build state produces the already-
  committed output. The gate must `cargo clean` (or the equivalent) first, or run
  in a fresh checkout, so the diff reflects a true from-scratch regeneration.
* Treat committed generated code as **generated** for coverage and TODO/lint
  rules — do not require the untestable-boundary or coverage treatment that
  hand-written code gets. Apply the generated-artifact rules in
  [core-standards.md](../shared/core-standards.md) (Testing Standards) rather than
  restating them here.
* **The gate MUST offer an auto-fix path.** A per-platform binding gate
  (`ci-android` for Kotlin, `ci-apple` for Swift, `ci-windows` for C#) that fails
  and tells a human to "regenerate" is incomplete. Each platform gate either
  pushes the regenerated binding to the PR branch as a bot commit when the PR
  carries the opt-in label (e.g. `regen`) — from *that platform's* pinned runner,
  since a Swift binding regenerated on Linux is not the artifact the gate
  compares — or uploads the regenerated binding plus a patch and prints the
  one-line apply command (a `git diff --binary --cached` patch taken after
  staging the regenerated outputs, so new files are included and `git apply`
  can restore the bytes). The same applies to visual/snapshot baselines: the CI
  dispatch job that regenerates them counts as an auto-fix path only when it
  ends in a bot commit or an uploaded patch plus apply command — one that
  re-renders snapshots for the developer to download and commit by hand does
  not. The full rule, the regenerate-before-compare requirement and input-hash
  baseline caching are in [arch-06](./arch-06_monorepo_workspace_standards.md)
  §6.
* **Pin the determinism inputs, per platform.** Cross-platform artifacts carry
  every determinism hazard in the arch-06 §6 checklist at once, because each
  platform shell adds its own toolchain to the chain:
  * wasm: `--remap-path-prefix=<checkout>=/src` passed through `RUSTFLAGS` by
    the regeneration script (Cargo does not expand `$PWD` in
    `.cargo/config.toml`), strip the `producers` section
    (`wasm-opt --strip-producers` or `wasm-bindgen --remove-producers-section`),
    pin `wasm-pack`/`wasm-bindgen`.
  * UniFFI Swift/Kotlin: pin `uniffi-bindgen` to the exact crate version the core
    depends on, and record the host triple the binding was generated on; a
    binding generated on a different host triple is a different artifact.
  * C#/JNI/C ABI: `-ffile-prefix-map`/`-fdebug-prefix-map` for native shims,
    `-trimpath`-style flags for any Go shims, and a stripped static/shared
    library (`.a`/`.so`/`.dylib`) if one is committed.
  * All platforms: forbid user-level toolchain profiles (`~/.cargo/config.toml`
    `[profile.release]`, global Gradle properties) in the regeneration path, and
    run the regeneration from the pinned platform runner only.

  The `artifact-hygiene` common check in `lint-standards.sh` WARNs when a
  committed `*.wasm`, `*.a`, `*.so`, `*.dylib` or `*.jar` embeds a `/Users/` or
  `/home/` path — the cheapest signal that the path-remapping input was missed.
  The worked example in arch-06 §6 (five commits to stabilise one wasm gate)
  is the cost of discovering these inputs one red build at a time.

## 4. UI Changes Are Cross-Platform by Default

When a product ships the same UX on multiple platforms, a UI change is assumed to
apply to **every** platform unless explicitly scoped otherwise.

* Scope UI issues and PRs to cover **all** surfaces — web *and* each native shell —
  with an acceptance criterion per surface. A web-only change silently leaves the
  native shells behind.
* Keep the shared data/logic behind the change single-sourced in the core (§1);
  only the rendering is implemented per shell.
* If a change genuinely applies to one platform only, say so in the issue/PR and
  give the reason (a platform-specific affordance, a capability gap). Silence
  defaults to "all platforms."

## 5. Testing Reaches the Platform Edges

* Logic is tested in the core with the conformance suite (platform-independent,
  runs in CI everywhere).
* Each shell has a thin layer of platform tests for rendering and glue.
* Runtime surfaces that **cannot** run in CI (a real filesystem-access API, a
  device keychain, a native window server) are handled per the untestable-boundary
  policy in [core-standards.md](../shared/core-standards.md) (Testing Standards):
  keep the boundary thin, push logic into the pure core where the conformance
  suite covers it, and flag the residual manual-verification step explicitly.
* See [arch-05](./arch-05_resilient_architecture_patterns.md) §3 for choosing
  layout by **semantic state** (a `LayoutMode` computed from dimensions) rather
  than platform detection — the same semantic state drives every shell.

## 6. Version Bumps Fan Out to Every Platform Artifact

A semver/release-version bump is a **coordinated fan-out** across all shipped
platforms — web plus each native shell — not a single-artifact edit with manual
follow-up on the rest.

* Cut the bump as **one step, enforced by the release script.** The script updates
  every platform's version artifact together; do not leave any platform to a manual
  follow-up commit, where it silently drifts out of version sync.
* The release checklist/script **enumerates every platform artifact** a version
  bump must produce (e.g. the web `package.json`, each native shell's manifest/build
  version, the core crate version). Adding a platform means adding it to this
  enumeration, so a missed platform fails the release rather than shipping mismatched
  versions.
