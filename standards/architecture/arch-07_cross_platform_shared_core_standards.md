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
