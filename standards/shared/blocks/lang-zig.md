# Zig

Use `zig build` with `build.zig`. Declare dependencies in `build.zig.zon`. Zig 0.11+ stable.
Format with `zig fmt`. Enable all compiler warnings. Use `@setRuntimeSafety(true)` in debug builds.
Pass allocators explicitly to all functions that allocate. Use `defer` for cleanup.
Use `ArenaAllocator` for temporary allocations. Document ownership semantics.
Use `comptime` for metaprogramming and compile-time optimizations.
Use `?T` for nullable values; `if (value) |v|` for safe unwrapping.
Define error sets with `error{}`. Use error unions (`!T`) for fallible operations. Use `try` to propagate, `catch` to handle.
Build modes: `Debug` (safety), `ReleaseSafe` (safety + opt), `ReleaseFast` (no safety), `ReleaseSmall` (size).
Naming: `snake_case.zig` files, `PascalCase` types/structs/enums, `camelCase` functions/variables, `pub`/non-`pub` for visibility.
Test with built-in `test` blocks (`zig test`). Use `std.testing` assertions.
Security: validate all external inputs at boundaries. Use `std.crypto.random` for security contexts.
