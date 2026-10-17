# Rust Standards

## 1. Package Management

* **Tool:** `cargo`. `Cargo.toml` for dependencies.
* **Version:** Rust 1.70+ (use latest stable). Pin the exact toolchain in `rust-toolchain.toml` and keep `rust-version` and CI in step with it — see §21.4.
* **Lock Files:** `Cargo.lock` committed for applications, not libraries.
* **Age Gate:** Do not adopt any crate version published less than 3 days ago. Verify publish date via crates.io API before upgrading. See `sec-01` §5 for exceptions.

## 2. Code Style

* **Formatter:** `rustfmt`. Run via `make fmt` or `cargo fmt`.
* **Linter:** `clippy`. Lints are declared once in `[workspace.lints]` at level `warn`; CI promotes them with `cargo clippy --workspace --all-targets --all-features -- -D warnings` (§21.3). Enforced by `lint-checks/rust/clippy-ci`.
* **Warnings:** Treated as errors **in CI**, via `-D warnings` on the command line — not via `#![deny(warnings)]` in source. A source-level deny turns every new rustc/clippy lint into a build break for every consumer on their next toolchain upgrade; the CLI flag keeps the gate where it belongs.

### rustfmt.toml

```toml
edition = "2021"
max_width = 100
tab_spaces = 4
```

## 3. Naming Conventions

* **Files:** `snake_case.rs`
* **Modules:** `snake_case`
* **Types/Structs/Enums:** `PascalCase`
* **Functions/Variables:** `snake_case`
* **Constants:** `UPPER_SNAKE_CASE`
* **Lifetimes:** Single lowercase letter: `'a`, `'b`

## 4. Project Structure

```text
src/
├── domain/
│   ├── entities.rs
│   └── value_objects.rs
├── application/
│   ├── use_cases.rs
│   └── interfaces.rs
└── infrastructure/
    └── repositories.rs
```

## 5. Language Features

* **Ownership:** Understand ownership, borrowing, and lifetimes. Prefer borrowing over cloning.
* **Error Handling:** Use `Result<T, E>` for fallible operations. Use `?` operator for propagation.
* **Option:** Use `Option<T>` for nullable values. Prefer over `null`/`None` patterns.
* **Pattern Matching:** Use `match` and `if let` for exhaustive pattern matching.

### Example

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Email {
    value: String,
}

impl Email {
    pub fn new(value: String) -> Result<Self, InvalidEmailError> {
        if !value.contains('@') || !value.contains('.') {
            return Err(InvalidEmailError(value));
        }
        Ok(Email { value })
    }
    
    pub fn as_str(&self) -> &str {
        &self.value
    }
}

#[derive(Debug, thiserror::Error)]
#[error("Invalid email: {0}")]
pub struct InvalidEmailError(String);
```

## 6. Error Handling

* **Error Types:** Use `thiserror` for library errors, `anyhow` for application errors.
* **Result:** Use `Result<T, E>` for all fallible operations. Never use panics for expected errors.
* **Propagation:** Use `?` operator for error propagation. Handle errors at boundaries.

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum DomainError {
    #[error("Invalid email: {0}")]
    InvalidEmail(String),
    
    #[error("User not found: {0}")]
    UserNotFound(String),
    
    #[error("Database error: {0}")]
    Database(#[from] sqlx::Error),
}
```

## 7. Testing

* **Framework:** Built-in `#[test]` and `#[cfg(test)]`. Use `cargo test`.
* **Mocking:** Use `mockall` for trait mocking. Use test doubles for integration tests.
* **Coverage:** Use `cargo-tarpaulin` or `grcov`. **95% is the absolute minimum for any module.** Target 100% for domain, 95%+ for application and infrastructure.

### Test Structure

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn should_create_user_with_valid_email() {
        // Given
        let email = Email::new("test@example.com".to_string()).unwrap();
        
        // When
        let user = User::new(email, "Test User".to_string());
        
        // Then
        assert_eq!(user.email().as_str(), "test@example.com");
    }
}
```

## 8. Async/Await

* **Runtime:** Use `tokio` or `async-std` for async runtime.
* **Futures:** Use `async`/`await` syntax. Use `Future` trait for custom futures.
* **Error Handling:** Use `Result<T, E>` with async functions. Handle errors with `?`.

```rust
use tokio;

async fn fetch_user(id: &str) -> Result<User, DomainError> {
    let user = user_repository
        .find_by_id(id)
        .await?
        .ok_or_else(|| DomainError::UserNotFound(id.to_string()))?;
    Ok(user)
}
```

## 9. Dependencies

### Common Crates

* **HTTP:** `reqwest` (client), `axum` or `actix-web` (server)
* **Database:** `sqlx` (async SQL), `diesel` (ORM), `sea-orm` (async ORM)
* **Serialization:** `serde` with `serde_json`
* **Error Handling:** `thiserror`, `anyhow`
* **Logging:** `tracing` with `tracing-subscriber`

## 10. Documentation

* **Doc Comments:** Use `///` for public items, `//!` for module-level docs.
* **Format:** Use Markdown. Include examples with `#` for hidden code.

```rust
/// Creates a new user with validated email address.
///
/// # Arguments
///
/// * `email` - Valid email address (must match RFC 5322)
/// * `name` - User's full name (non-null, non-empty)
///
/// # Returns
///
/// New `User` entity instance.
///
/// # Errors
///
/// Returns `InvalidEmailError` if email format is invalid.
///
/// # Examples
///
/// ```rust
/// # use domain::email::Email;
/// let email = Email::new("test@example.com".to_string())?;
/// let user = User::new(email, "John Doe".to_string());
/// ```
pub fn create_user(email: Email, name: String) -> User {
    // Implementation
}
```

## 11. Memory Safety

* **Ownership:** Understand ownership rules. Use references (`&`) to avoid moving.
* **Lifetimes:** Use lifetime parameters (`'a`) when necessary. Prefer higher-ranked trait bounds.
* **Unsafe:** Avoid `unsafe` code unless absolutely necessary. Document why unsafe is needed.

## 12. Performance

* **Zero-Cost Abstractions:** Leverage Rust's zero-cost abstractions (iterators, closures).
* **Allocation:** Minimize allocations. Use `&str` over `String` when possible.
* **Profiling:** Use `cargo flamegraph` or `perf` for performance profiling.

## 13. Cargo Features

* **Feature Flags:** Use `[features]` in `Cargo.toml` for optional dependencies.
* **Workspaces:** Use workspaces for monorepo structure.
* **Publishing:** Follow semantic versioning. Use `cargo publish` for crates.io.

## 14. Inline Test Modules

* **Convention:** Tests live in `#[cfg(test)] mod tests { use super::*; ... }` within each source file.
* **Rationale:** Inline tests have access to private helpers without polluting the public API. Refactoring code and tests together is easier when they're in the same file.
* **Exception:** Integration tests that need compiled binaries or external processes belong in `tests/` at the crate root.

```rust
// In src/document.rs
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn insert_at_boundary_extends_document() {
        let mut doc = Document::new("hello");
        doc.insert(5, " world").unwrap();
        assert_eq!(doc.text(), "hello world");
    }
}
```

## 15. Workspace Member Tooling

* **Convention:** Data generators, seed tools, and scaffolding belong as workspace members, not external scripts.
* **Rationale:** Ensures version consistency with the main crate. CI can build and test them alongside the app. They're easy to iterate on during development.
* **Example:** A `tools/my-seed/` crate that generates test fixtures is a workspace member in the root `Cargo.toml`:

```toml
[workspace]
members = [
    "packages/*",
    "apps/*",
    "tools/my-seed",
]
```

## 16. Feature Flag Conventions

* **Named flags** for optional capabilities: `cosmic-shaping = ["dep:cosmic-text"]`.
* **Reserved flags** for documented future work: `experimental-sync = []` with a comment explaining intent.
* **Documentation:** Always add a comment in `Cargo.toml` explaining what a feature flag enables.

```toml
[features]
# Enable advanced text shaping via cosmic-text
cosmic-shaping = ["dep:cosmic-text"]
# Reserved for future CRDT-based collaboration (automerge-rs)
experimental-sync = []
```

## 17. Enforcing Documentation

* **Library crates:** Add `#![deny(missing_docs)]` to `lib.rs`. Every public item requires a `///` doc comment.
* **App crates:** Documentation is recommended but not enforced. App entry points change frequently and internal APIs are less stable.
* **Compiler warnings as errors:** Enforced in CI with `-D warnings` (§2, §21.3), **not** with `#![deny(warnings)]` in crate roots. The only source-level `deny` attributes are the targeted ones: `missing_docs` on libraries and `clippy::disallowed_methods` on FFI/wasm facades (§21.2).

## 18. Error Handling Layering (Rust-Specific)

* **Library crates:** Use `thiserror` with typed error enums. Each error variant includes context fields.
* **App crates:** Use `anyhow` for context-rich error chaining. Wrap library errors with `.context("what was happening")`.
* **GUI event handlers:** Handlers that return `()` (common in frameworks like Makepad, egui, iced) should `eprintln!` errors, never `panic!` or `unwrap()`.

```rust
// Library crate
#[derive(Debug, thiserror::Error)]
pub enum DocumentError {
    #[error("offset {offset} is out of bounds for document length {len}")]
    OffsetOutOfBounds { offset: usize, len: usize },
}

// App crate
use anyhow::Context;
fn load_project(path: &Path) -> anyhow::Result<Project> {
    let data = std::fs::read_to_string(path)
        .context("failed to read project file")?;
    // ...
}
```

## 19. Workspace Cargo Configuration

* **`.cargo/config.toml`:** Use for workspace-wide settings (target-specific flags, custom runners, env vars).
* **`RUSTC_WRAPPER`:** When external build tools hard-code `RUSTFLAGS` (e.g., `cargo-makepad wasm build`), use a wrapper script to inject required flags without conflicting.
* **Target-specific config:** Platform-specific compilation flags belong in `.cargo/config.toml`, not scattered across Makefiles.

```toml
# .cargo/config.toml
[target.wasm32-unknown-unknown]
rustflags = ['--cfg', 'getrandom_backend="custom"']
```

## 20. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** Run `cargo clippy --all-targets --all-features -- -D warnings` in CI. Use `cargo-geiger` to audit `unsafe` usage across dependencies.
- **Dependency scanning:** Run `cargo audit` and `cargo deny check` in CI.
- **SAST:** Run `cargo clippy -- -D warnings` and `cargo geiger` in CI for static analysis and unsafe code auditing.
- **Banned functions:** See [sec-01_security_standards.md](../security/sec-01_security_standards.md) for the complete banned-functions list with language-specific examples.
- **Unsafe code:** Minimize `unsafe` blocks. Document safety invariants for every `unsafe` usage. Prefer safe abstractions.
- **Secure random:** Use `rand::rngs::OsRng` or `getrandom` crate for cryptographic randomness.

## 21. FFI & wasm Facades

A facade module is the thin layer that exposes Rust to another runtime: `extern "C"` functions in `src/ffi.rs` (consumed from Swift, C, Python, …) or `#[wasm_bindgen]` exports in `src/wasm.rs`. Everything the host can call lives there, and nothing else in the crate knows the host exists. The facade has one job — translate between the host's ABI and the crate's typed API — and it has stricter rules than the rest of the crate because a mistake there is undefined behavior or a host-process crash, not a Rust panic with a backtrace.

### 21.1 Panics never cross the boundary

* A panic that unwinds out of an `extern "C"` function aborts the process (Rust 1.81+) or is undefined behavior (earlier). In wasm a panic traps, which the JS host sees as an opaque `RuntimeError` with the Rust stack gone.
* The facade therefore **never** calls anything that can panic on a reachable input: no `unwrap`/`expect`, no `panic!`/`unreachable!`/`todo!`, no slice indexing (`buf[i]` → `buf.get(i)`), no unchecked arithmetic on host-supplied lengths.
* Every `Result` is converted at the facade: `extern "C"` returns a status code (`0` success, negative errno-style codes) and writes outputs through out-pointers; wasm exports return `Result<T, JsError>` (or `Result<T, JsValue>`) so the host gets a real exception with a message.
* As a last line of defence, wrap the body of every `extern "C"` function in `std::panic::catch_unwind` and map a caught panic to an error code. This is belt-and-braces: the lint in §21.2 is the real gate, `catch_unwind` just turns a bug into a reportable error instead of an abort.

```rust
// src/ffi.rs
#![deny(clippy::disallowed_methods)]
#![deny(clippy::indexing_slicing, clippy::panic, clippy::unwrap_used, clippy::expect_used)]

use std::panic::{catch_unwind, AssertUnwindSafe};

#[repr(i32)]
pub enum Status { Ok = 0, NullPointer = -1, Parse = -2, Internal = -99 }

/// # Safety
/// `bytes` must point to `len` readable bytes, or be null (returns NullPointer).
#[no_mangle]
pub unsafe extern "C" fn mesh_parse(bytes: *const u8, len: usize, out: *mut *mut Mesh) -> i32 {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if bytes.is_null() || out.is_null() { return Status::NullPointer; }
        // SAFETY: caller guarantees `bytes` points to `len` readable bytes (see `# Safety`).
        // Explicit block: `unsafe_op_in_unsafe_fn` warns otherwise, and CI runs `-D warnings`.
        let slice = unsafe { std::slice::from_raw_parts(bytes, len) };
        match crate::parse(slice) {
            Ok(mesh) => {
                // SAFETY: `out` is non-null (checked above) and the caller guarantees it is writable.
                unsafe { *out = Box::into_raw(Box::new(mesh)) };
                Status::Ok
            }
            Err(_) => Status::Parse,
        }
    }));
    result.unwrap_or(Status::Internal) as i32   // allowed: Result<Status, Box<dyn Any>> from catch_unwind, never panics
}
```

```rust
// src/wasm.rs
#![deny(clippy::disallowed_methods)]
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn parse_mesh(bytes: &[u8]) -> Result<JsValue, JsError> {
    let mesh = crate::parse(bytes).map_err(|e| JsError::new(&e.to_string()))?;
    serde_wasm_bindgen::to_value(&mesh).map_err(|e| JsError::new(&e.to_string()))
}
```

### 21.2 The `disallowed-methods` pattern

Clippy's `unwrap_used`/`expect_used` are blunt across a whole crate — tests and internal invariants legitimately `unwrap`. Scope the ban to the facade instead:

1. **List the methods once, with reasons, in `clippy.toml`** at the workspace root. `disallowed-methods` takes fully qualified paths, so the list is precise and self-documenting.
2. **Declare the lint at `warn` workspace-wide** in `[workspace.lints.clippy]` so every crate sees it locally without failing the build.
3. **Promote it to `deny` only in the facade modules** with a module-level `#![deny(clippy::disallowed_methods)]` at the top of `src/ffi.rs` / `src/wasm.rs`. Those files fail to compile under `cargo clippy` if anyone adds an `unwrap`; the rest of the crate just gets a warning that CI turns into an error (§21.3).
4. **Grep gate in `lint-standards`:** `lint-checks/rust/ffi-no-unwrap` scans `ffi.rs`, `wasm.rs`, `*_ffi.rs`, `*_wasm.rs`, and `ffi/`/`wasm/` directories for `unwrap`/`expect`/`panic!`-family calls, so the rule holds even when clippy is not installed on the reviewer's machine.

```toml
# clippy.toml
disallowed-methods = [
  { path = "core::option::Option::unwrap",  reason = "panics cross the FFI/wasm boundary as UB — return an error code" },
  { path = "core::option::Option::expect",  reason = "same as unwrap" },
  { path = "core::result::Result::unwrap",  reason = "same as unwrap" },
  { path = "core::result::Result::expect",  reason = "same as unwrap" },
]
```

```toml
# Cargo.toml (workspace root)
[workspace.lints.clippy]
disallowed_methods = "warn"   # facades promote to deny with #![deny(...)]
unwrap_used        = "warn"
expect_used        = "warn"
indexing_slicing   = "warn"

[workspace.lints.rust]
unsafe_op_in_unsafe_fn = "warn"
```

Every member crate opts in with `[lints] workspace = true`.

### 21.3 Warn locally, deny in CI

* **Local:** `cargo clippy` prints warnings and exits 0. Developers see every finding without a red build while iterating.
* **CI:** `cargo clippy --workspace --all-targets --all-features -- -D warnings` makes the same findings fatal. Run one clippy lane per meaningful feature set (e.g. `--no-default-features`, `--features wasm`, `--all-features`) — feature-gated code is only linted when its feature is on.
* **Never** put `#![deny(warnings)]` in source (§2). It makes the crate's build depend on which toolchain the consumer happens to have.
* Enforced by `lint-checks/rust/clippy-ci`, which looks for a `cargo clippy … -D warnings` (or `RUSTFLAGS=-D warnings`) step in CI.

### 21.4 Toolchain pin consistency

Three places name the compiler, and they drift independently unless something checks them:

| File | Key | Role |
| --- | --- | --- |
| `rust-toolchain.toml` | `channel = "1.99.0"` | What `cargo` actually uses locally and in CI (rustup honours it) |
| `Cargo.toml` | `rust-version = "1.99"` | MSRV: the oldest compiler that must build the crate; `cargo` refuses older toolchains |
| CI workflow | `dtolnay/rust-toolchain@1.99.0`, `toolchain: 1.99.0`, `rustup default 1.99.0` | What CI installs when it does not read the file |

Rules:

* **`rust-toolchain.toml` is the source of truth.** Pin an exact `major.minor.patch`; `stable` is not a pin.
* **Applications:** `rust-version` equals the pinned toolchain's `major.minor`. Bump both (and `Cargo.lock`) in one `chore(rust): upgrade toolchain to X.Y.Z` commit, with an ADR entry if the bump changes edition or MSRV policy.
* **Libraries** may declare an older MSRV than the pinned toolchain, but then CI must have a lane that builds on `rust-version` (`dtolnay/rust-toolchain@<msrv>`), or the MSRV is a fiction.
* **CI** either omits an explicit toolchain (so rustup reads the file) or pins the identical version. Pinning a *different* explicit version is an error.
* `rust-version` **newer** than the pinned toolchain is always wrong (the pinned compiler cannot build the crate).
* Enforced by `lint-checks/rust/toolchain-pin`: FAIL on a CI pin or `rust-version` that contradicts `rust-toolchain.toml`; WARN when the file is missing, floats, or `rust-version` trails it.

### 21.5 License allow-list (`deny.toml`)

* Every workspace ships a `deny.toml` with a `[licenses] allow = [...]` list of SPDX identifiers; `cargo deny check` runs in CI alongside `cargo audit`. An allow-list (not a deny-list) means a new copyleft dependency fails the build until someone consciously adds its license.
* Keep `[advisories]` on the current cargo-deny schema: vulnerabilities are always errors, so the knobs are `unmaintained = "workspace"` and `yanked = "deny"` (the old `vulnerability = "deny"` / `unmaintained = "warn"` keys were removed and now fail to parse). `[bans] multiple-versions = "warn"`, and `[sources]` restricted to crates.io plus explicitly listed git sources.
* Enforced by `lint-checks/rust/deny-config`: FAIL when no `deny.toml`, WARN when it has no non-empty `allow` list.

```toml
# deny.toml
[licenses]
allow = ["MIT", "Apache-2.0", "Apache-2.0 WITH LLVM-exception", "BSD-2-Clause", "BSD-3-Clause", "ISC", "Unicode-3.0", "Zlib"]
confidence-threshold = 0.9

[advisories]
# Vulnerabilities always fail; these are the remaining knobs on the current schema.
unmaintained = "workspace"
yanked = "deny"

[bans]
multiple-versions = "warn"
wildcards = "deny"

[sources]
unknown-registry = "deny"
unknown-git = "deny"
```
