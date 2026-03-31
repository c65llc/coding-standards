# Zig Standards

## 1. Build System

* **Tool:** `zig build`. `build.zig` for build configuration.
* **Version:** Zig 0.11+ (use latest stable).
* **Dependencies:** Use `build.zig.zon` for package dependencies.
* **Age Gate:** Do not adopt any dependency version (commit/tag) published less than 3 days ago. Manually verify the upstream commit or tag date before upgrading. See `sec-01` §5 for exceptions.

## 2. Code Style

* **Formatter:** `zig fmt`. Run via `make fmt` or `zig fmt`.
* **Linter:** Compiler warnings. Use `@setRuntimeSafety(true)` for safety checks.
* **Type Checker:** Compiler is the type checker. Enable all warnings.

### build.zig Example

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "project",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);
}
```

## 3. Naming Conventions

* **Files:** `snake_case.zig`
* **Types/Structs/Enums:** `PascalCase`
* **Functions/Variables:** `camelCase`
* **Constants:** `UPPER_SNAKE_CASE` or `camelCase` with `const`
* **Private:** No special prefix (use `pub`/non-`pub` for visibility)

## 4. Project Structure

```text
src/
├── domain/
│   ├── entities.zig
│   └── value_objects.zig
├── application/
│   ├── use_cases.zig
│   └── interfaces.zig
└── infrastructure/
    └── repositories.zig
```

## 5. Language Features

* **Memory Management:** Manual memory management. Use allocators explicitly.
* **Error Handling:** Use error unions `!T` or `Error!T`. Use `try`/`catch` for error handling.
* **Optionals:** Use `?T` for nullable types. Use `if (value) |v|` for unwrapping.
* **Comptime:** Leverage compile-time execution for metaprogramming.

### Example

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Email = struct {
    value: []const u8,
    
    pub fn init(allocator: Allocator, value: []const u8) !Email {
        if (!std.mem.containsAtLeast(u8, value, 1, "@") or 
            !std.mem.containsAtLeast(u8, value, 1, ".")) {
            return error.InvalidEmail;
        }
        return Email{ .value = value };
    }
    
    pub fn deinit(self: *const Email, allocator: Allocator) void {
        _ = self;
        _ = allocator;
        // Free if allocated
    }
};

pub const Result = union(enum) {
    success: void,
    failure: Error,
    
    pub const Error = error{
        InvalidEmail,
        UserNotFound,
    };
};
```

## 6. Error Handling

* **Error Sets:** Define error sets explicitly. Use `error{}` for custom errors.
* **Error Unions:** Use `!T` or `Error!T` for fallible operations.
* **Propagation:** Use `try` for error propagation. Use `catch` for error handling.

```zig
pub const DomainError = error{
    InvalidEmail,
    UserNotFound,
    DatabaseError,
};

pub fn createUser(
    allocator: Allocator,
    email_str: []const u8,
    name: []const u8,
) !User {
    const email = Email.init(allocator, email_str) catch |err| {
        return DomainError.InvalidEmail;
    };
    return User.init(allocator, email, name);
}
```

## 7. Testing

* **Framework:** Built-in `test` blocks. Use `zig test`.
* **Test Structure:** Use `test "description"` blocks. Test in same file or separate test files.

### Test Structure

```zig
const std = @import("std");
const testing = std.testing;

test "should create user with valid email" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const email = try Email.init(allocator, "test@example.com");
    defer email.deinit(allocator);
    
    const user = try User.init(allocator, email, "Test User");
    defer user.deinit(allocator);
    
    try testing.expectEqualStrings("test@example.com", user.email.value);
}
```

## 8. Memory Management

* **Allocators:** Always pass allocators explicitly. Use appropriate allocator for use case.
* **Ownership:** Document ownership semantics. Use `defer` for cleanup.
* **Arena Allocators:** Use `ArenaAllocator` for temporary allocations.

```zig
pub fn processUsers(allocator: Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();
    
    // Use arena_allocator for temporary allocations
    // Automatically freed when arena is deinit
}
```

## 9. Dependencies

### Common Libraries

* **HTTP:** `http.zig` or `h11` for HTTP parsing
* **JSON:** `std.json` (standard library)
* **Database:** `zig-sqlite` or database-specific bindings
* **Logging:** Custom logging or `std.log`

## 10. Documentation

* **Doc Comments:** Use `///` for public items, `//!` for module-level docs.
* **Format:** Use Markdown. Include examples.

```zig
/// Creates a new user with validated email address.
///
/// Arguments:
/// - `allocator`: Memory allocator for user allocation
/// - `email_str`: Valid email address (must match RFC 5322)
/// - `name`: User's full name (non-null, non-empty)
///
/// Returns:
/// New `User` entity instance.
///
/// Errors:
/// - `DomainError.InvalidEmail` if email format is invalid
///
/// Example:
/// ```zig
/// const user = try createUser(allocator, "test@example.com", "John Doe");
/// defer user.deinit(allocator);
/// ```
pub fn createUser(
    allocator: Allocator,
    email_str: []const u8,
    name: []const u8,
) !User {
    // Implementation
}
```

## 11. Performance

* **Zero-Cost Abstractions:** Zig has minimal runtime overhead. Use comptime for optimizations.
* **SIMD:** Use `@Vector` for SIMD operations when appropriate.
* **Profiling:** Use `perf` or `valgrind` for performance profiling.

## 12. Safety

* **Runtime Safety:** Use `@setRuntimeSafety(true)` for safety checks in debug builds.
* **Undefined Behavior:** Avoid undefined behavior. Use `@panic()` for unreachable code.
* **Bounds Checking:** Enable bounds checking in debug builds.

## 13. Build Modes

* **Debug:** `-O Debug` - Full safety checks, no optimizations.
* **ReleaseSafe:** `-O ReleaseSafe` - Safety checks enabled, optimized.
* **ReleaseFast:** `-O ReleaseFast` - No safety checks, maximum optimization.
* **ReleaseSmall:** `-O ReleaseSmall` - Optimized for size.

## 14. Security

> Full security standards: `standards/security/sec-01_security_standards.md`

- **SAST:** No major SAST tool for Zig yet. Rely on compiler warnings and manual review.
- **Memory safety:** Zig has no hidden control flow. Use `@panic` only for programming errors. Validate all external inputs at system boundaries.
- **Secure random:** Use `std.crypto.random` for security contexts.
