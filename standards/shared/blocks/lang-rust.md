# Rust

Use `cargo`. Commit `Cargo.lock` for applications; not for libraries. Rust 1.70+ stable.
Format with `rustfmt` (`cargo fmt`). Lint with `cargo clippy -- -D warnings`.
Add `#![deny(warnings)]` and `#![deny(missing_docs)]` to library crate roots.
Use `Result<T, E>` for all fallible operations. Use `?` for propagation. Never panic for expected errors.
Use `Option<T>` for nullable values. Use `match` and `if let` for exhaustive pattern matching.
Error layers: `thiserror` for library errors, `anyhow` for application errors.
Prefer borrowing (`&`) over cloning. Minimize heap allocations.
Tests live in `#[cfg(test)] mod tests { use super::*; }` within each source file. Integration tests in `tests/`.
Naming: `snake_case` functions/variables/files, `PascalCase` types/structs/enums, `UPPER_SNAKE_CASE` constants, `'a` for lifetimes.
Use `tokio` or `async-std` for async. Minimize `unsafe` — document all safety invariants.
Security: `cargo clippy --all-targets -- -D warnings` and `cargo audit` in CI. Use `rand::rngs::OsRng` for cryptographic randomness.
