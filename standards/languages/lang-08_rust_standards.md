# Rust Standards

## 1. Package Management

* **Tool:** `cargo`. `Cargo.toml` for dependencies.
* **Version:** Rust 1.70+ (use latest stable).
* **Lock Files:** `Cargo.lock` committed for applications, not libraries.

## 2. Code Style

* **Formatter:** `rustfmt`. Run via `make fmt` or `cargo fmt`.
* **Linter:** `clippy`. Run via `cargo clippy -- -D warnings`.
* **Type Checker:** Compiler strict warnings. Use `#![deny(warnings)]` in lib.rs.

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
* **Compiler warnings as errors:** Add `#![deny(warnings)]` to all library crate roots. This catches dead code, unused imports, and other issues early.

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
- **Unsafe code:** Minimize `unsafe` blocks. Document safety invariants for every `unsafe` usage. Prefer safe abstractions.
- **Secure random:** Use `rand::rngs::OsRng` or `getrandom` crate for cryptographic randomness.
