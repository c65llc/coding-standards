Use `cargo`. Commit `Cargo.lock` for applications; not for libraries. Pin the toolchain in `rust-toolchain.toml` (exact `channel = "1.xx.y"`); `Cargo.toml` `rust-version` and every CI toolchain pin must agree with it — bump all three in one commit.
Format with `rustfmt` (`cargo fmt`). Lint with `clippy`: declare lints at `warn` in `[workspace.lints]` so local builds stay green, and let CI deny them (`cargo clippy --workspace --all-targets --all-features -- -D warnings`, one lane per feature set). Do not hard-code `#![deny(warnings)]` in crate roots — it breaks every consumer on a toolchain upgrade.
Add `#![deny(missing_docs)]` to library crate roots.
Use `Result<T, E>` for all fallible operations. Use `?` for propagation. Never panic for expected errors.
FFI/wasm facades (`src/ffi.rs`, `src/wasm.rs`) are panic-free: no `unwrap`/`expect`/`panic!`/indexing at the `extern "C"` or `#[wasm_bindgen]` boundary — convert every `Result` to an error code or JS error. Enforce with `clippy.toml` `disallowed-methods` + `#![deny(clippy::disallowed_methods)]` in the facade modules only.
Use `Option<T>` for nullable values. Use `match` and `if let` for exhaustive pattern matching.
Error layers: `thiserror` for library errors, `anyhow` for application errors.
Prefer borrowing (`&`) over cloning. Minimize heap allocations.
Tests live in `#[cfg(test)] mod tests { use super::*; }` within each source file. Integration tests in `tests/`.
Naming: `snake_case` functions/variables/files, `PascalCase` types/structs/enums, `UPPER_SNAKE_CASE` constants, `'a` for lifetimes.
Use `tokio` or `async-std` for async. Minimize `unsafe` — document all safety invariants.
Security: `cargo clippy --all-targets -- -D warnings`, `cargo audit`, and `cargo deny check` (with a `deny.toml` license allow-list) in CI. Use `rand::rngs::OsRng` for cryptographic randomness.
