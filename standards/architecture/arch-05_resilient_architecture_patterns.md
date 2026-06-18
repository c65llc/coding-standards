# Resilient Architecture Patterns

## 1. Per-Module Coverage Gates

See [core-standards.md](../shared/core-standards.md) Section 4 for coverage requirements and gates.

## 2. Pure Render Logic

Separate **data→view model** transformations from **view model→pixels** rendering. This enables testing UI logic without framework dependencies.

### Pattern

```text
Source Data  →  pure function  →  View Model (Vec<RenderEntry>)  →  UI framework renders it
```

### Rules

* View model functions take data in, return data out. No side effects, no framework imports.
* Unit tests verify the view model output directly (e.g., "given this folder tree, the sidebar produces these entries at these depths").
* The rendering layer consumes the view model and maps it to framework-specific widgets. This layer is thin and primarily declarative.

### Benefits

* Tests run in CI without a display server or framework runtime.
* View models can be reused across different rendering backends.
* Debugging UI issues reduces to inspecting the view model, not stepping through framework internals.

## 3. Responsive Design via Semantic State

Use a **semantic enum** computed from window dimensions instead of platform detection (`#[cfg(target_os)]`, `navigator.userAgent`, etc.).

### Pattern

```text
Window dimensions  →  LayoutMode enum  →  Layout decisions
```

### Example

```rust
pub enum LayoutMode {
    Compact,    // < 600px: sidebar as drawer overlay, larger touch targets
    Expanded,   // >= 600px: persistent sidebar, standard hit targets
}
```

### Rules

* Layout decisions reference `LayoutMode`, never platform strings.
* The threshold is configurable (not hard-coded in business logic).
* Touch-adapted features (larger hit targets, long-press interactions) are driven by `LayoutMode`, not by detecting mobile OS.
* `LayoutMode` is testable: pass it as a parameter to layout functions.

## 4. Error Handling Layering

Errors should be typed differently at each architectural layer.

### Pattern

| Layer | Error Strategy | Example |
|-------|---------------|---------|
| Domain / Core | Typed error enums (e.g., `thiserror` in Rust, custom exceptions in Python) | `DocumentError::OffsetOutOfBounds { offset, len }` |
| Application / Shell | Wrapping errors that add context (e.g., `ShellError(DocumentError)`) | Converts domain errors into layer-appropriate types |
| Apps / UI | Contextual error handling — log and continue, show user feedback | `eprintln!` or toast notification; never crash the app |

### Rules

* Libraries expose typed errors that callers can match on.
* Apps use contextual error wrappers (`anyhow` in Rust, exception chaining in Python/Java) for debugging.
* UI event handlers that return `void`/`()` MUST NOT panic on errors. Log the error and degrade gracefully.

## 5. Centralized Platform Paths

All storage and configuration path resolution should live in a single module.

### Pattern

```text
platform_paths module
  ├── data_dir()      → platform-specific app data directory
  ├── config_dir()    → platform-specific config directory
  ├── cache_dir()     → platform-specific cache directory
  └── projects_dir()  → where user projects are stored
```

### Rules

* One module handles all platform-specific path logic, with fallbacks for platforms where standard libraries fail (e.g., `dirs` crate returns `None` on Android).
* All other modules call through this centralized API — never scatter `dirs::data_dir()` calls throughout the codebase.
* The module can be stubbed for testing (accept a root path parameter or use dependency injection).

## 6. Naming That Reinforces Architecture

See [core-standards.md](../shared/core-standards.md) Section 2 for naming conventions.

## 7. Secondary Subsystems Are Best-Effort and Isolated

A **secondary** or **derived** subsystem (a mirror, an on-disk archive, a search
index, a sync/replication path, telemetry) exists to reflect or augment the
**primary** state. It must never be able to break the primary.

### Rules

* The primary write path is authoritative. Updating a secondary subsystem is
  **best-effort**: wrap it so a failure is caught, logged (with a clear prefix,
  e.g. `console.warn('[archive] …')`), and swallowed *at that boundary* — never
  propagated into the primary operation.
* Isolate each secondary side effect in its own `try`/`catch`. One mirror failing
  must not void the result of a whole operation, nor abort the other side effects.
* Keep the secondary subsystem behind a seam (a port/interface) so the primary
  path depends on the abstraction, not the concrete mirror, and can run with it
  disabled.
* Make secondary work **opt-in / detect-only** where appropriate (run it only when
  a change is detected) rather than forcing it on every operation.

## 8. Coordination Singletons Need Liveness and Takeover

When a single elected participant coordinates others — a leader tab holding a
lock, a primary node, a lease holder — design for that singleton becoming
**unresponsive**, not just for it dying cleanly.

### Rules

* Followers that depend on the singleton MUST have a bounded probe/timeout and a
  recovery path (re-election, takeover, or a one-shot guarded reload). A
  persistently unresponsive-but-alive leader otherwise wedges *every* dependent
  indefinitely.
* Liveness ≠ presence. A holder that still owns the lock but never answers is the
  hard case — detect it via timeout and route to takeover, don't assume a held
  lock means a healthy leader.
* Test the "stale leader" path explicitly; it does not reproduce in a single-tab /
  single-node dev setup, so it is easy to ship broken.

## 9. Don't Swallow the Root Cause

Degrading gracefully (§4) does **not** mean discarding the diagnostic.

* When you catch-and-degrade at a boundary, **preserve and surface the original
  cause** — log it, attach it to the wrapping error, expose it in a diagnostics
  view. A generic "pipeline failed" with the real `cause` (e.g. `"probe timed
  out"`) swallowed sends every future investigation down dead ends.
* Wrapping errors to add context (§4) must chain the underlying error, not replace
  it.
