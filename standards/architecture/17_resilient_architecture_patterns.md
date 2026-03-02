# Resilient Architecture Patterns

## 1. Per-Module Coverage Gates

Instead of a single global coverage threshold, enforce coverage baselines per architectural layer. Inner layers (domain/core) hold the highest bar because they contain the most critical logic.

### Recommended Baselines

**95% is the absolute minimum for any module.** No layer is exempt.

| Layer | Min Coverage | Rationale |
|-------|-------------|-----------|
| Domain / Core | 100% | Pure business logic, no external dependencies, highest risk |
| Application / Shell | 95%+ | Orchestration logic, all use cases tested |
| Infrastructure / Integration | 95%+ | External adapters — use test containers and mocks to reach threshold |

### Enforcement

Define per-module thresholds as Make variables. **The floor is 95% — projects may raise but never lower these values:**

```makefile
CORE_COV_MIN  ?= 100
APP_COV_MIN   ?= 95
INFRA_COV_MIN ?= 95

coverage-check: ## Enforce per-module coverage baselines
	# Run coverage tool per module, compare against threshold
```

A PR that drops any module below its coverage gate MUST NOT be merged.

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

Use distinct naming prefixes for library/framework crates vs. app crates. This makes it immediately obvious which architectural layer a module belongs to.

### Pattern

| Prefix | Layer | Example |
|--------|-------|---------|
| Framework name (e.g., `lattice-`) | Internal libraries | `lattice-core`, `lattice-layout`, `lattice-shell` |
| Product name (e.g., `trellis-`) | User-facing apps and tools | `trellis-seed`, Trellis desktop app |

### Rules

* Library crates use the framework prefix. They are reusable across different apps.
* App crates use the product prefix. They are specific to a single deployable.
* Tools that support the app (seed generators, migration scripts) use the product prefix.
* This convention should be documented in the project's `CLAUDE.md` or README.
