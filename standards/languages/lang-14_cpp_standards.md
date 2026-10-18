# C++ Standards

Modern C++ that builds and behaves the same on macOS, Linux and Windows, with
the sharp edges kept away from the people who call it from Swift, Kotlin, C# or
Python. The C ABI section (§10) is the contract those wrappers depend on; the
wrapping side itself lives in
[arch-07_cross_platform_shared_core_standards.md](../architecture/arch-07_cross_platform_shared_core_standards.md).

## 1. Language Baseline

* **Baseline: C++20.** `target_compile_features(<target> PUBLIC cxx_std_20)` on every target; never set `CMAKE_CXX_STANDARD` globally in a library that others consume.
* **Floor: C++17** where a platform toolchain lags (an older NDK, an embedded vendor compiler, a distro's system GCC). A project that must honour the floor says so in its `README` build matrix and in an ADR, and CI runs one lane on the floor compiler so the floor is real, not aspirational.
* **Extensions off.** `CMAKE_CXX_EXTENSIONS OFF` (`-std=c++20`, not `-std=gnu++20`). `/permissive-` on MSVC. Code that compiles on one compiler only is a bug.
* **C++20 features to rely on:** `<span>`, `<concepts>`, `<ranges>` (views only; avoid actions), designated initialisers, `constexpr` containers and algorithms, `<bit>`, `std::endian`, `[[likely]]`/`[[unlikely]]`, three-way comparison, `std::jthread`/`std::stop_token`.
* **Formatting:** `fmt::format` from `{fmt}` behind a project alias (`core::format`) by default. `std::format` needs libc++ 17, libstdc++ 13 or MSVC 19.29, which is newer than the §2 minimums (Clang 16, GCC 12): a project may switch the alias to `std::format` only when every compiler in *its* matrix ships it, and the matrix in its `README` says so.
* **Not yet:** C++20 modules (§7), coroutines in public APIs (the ABI of a coroutine frame is compiler-specific), `std::execution` policies on libc++. These are allowed inside a single translation unit when the whole compiler matrix supports them and an ADR records the decision.
* **C++23:** `std::expected` is the preferred result type (§9). On a C++20 toolchain use `tl::expected` behind a project alias so the switch is one header.

## 2. Toolchain Matrix

Every project names its supported compilers in the `README` and CI builds on all of them. The minimums below are the floor for a C++20 baseline; raise them freely, never lower them silently.

| Compiler | Minimum | Platforms | Standard library |
| --- | --- | --- | --- |
| Clang / Apple Clang | 16 / Xcode 15 | macOS, iOS, Linux, Android (NDK r26+), WebAssembly (Emscripten 3.1.50+) | libc++ |
| GCC | 12 | Linux, MinGW | libstdc++ |
| MSVC | 19.36 (Visual Studio 2022 17.6) | Windows | MSVC STL |

### Warning sets

Warnings are declared once, on an `INTERFACE` target named after the project (`${PROJECT_NAME}_warnings`, alias `${PROJECT_NAME}::warnings` — a fixed name would collide when two libraries built the same way meet in one build) that every target the project owns links. Copy [`templates/cpp/ProjectWarnings.cmake`](../../templates/cpp/ProjectWarnings.cmake); it also carries the `cxx_std_20` requirement (§1) and the coverage, clang-tidy and hardening switches the presets flip (§3). The sets it carries are:

| Compiler | Baseline set |
| --- | --- |
| Clang + GCC | `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion -Wnon-virtual-dtor -Wold-style-cast -Wcast-align -Woverloaded-virtual -Wnull-dereference -Wdouble-promotion -Wformat=2 -Wimplicit-fallthrough -Wunused` |
| GCC extras | `-Wmisleading-indentation -Wduplicated-cond -Wduplicated-branches -Wlogical-op -Wuseless-cast` |
| Clang extras | `-Wmost -Wextra-semi -Wunreachable-code -Wthread-safety` (when annotations are used) |
| MSVC | `/W4 /permissive- /Zc:__cplusplus /Zc:preprocessor /utf-8 /EHsc /w14242 /w14254 /w14263 /w14265 /w14287 /we4289 /w14296 /w14311 /w14545 /w14546 /w14547 /w14549 /w14555 /w14619 /w14640 /w14826 /w14905 /w14906 /w14928` |

### Warnings as errors: on in CI, off by default

* **Local builds** show every warning and still link, so a developer on a newer compiler is not blocked by a diagnostic the project has not seen yet.
* **CI builds** fail on any warning: the `ci` preset sets `CMAKE_COMPILE_WARNING_AS_ERROR=ON` (CMake 3.24+), which adds `-Werror` / `/WX` to every target the project owns. Pass `-Werror` explicitly on toolchains older than 3.24.
* **Never hard-code `-Werror` in `CMakeLists.txt`** without an `option()` guard (`<PROJECT>_WARNINGS_AS_ERRORS`, default `OFF`). A consumer that adds your library with `FetchContent` on a compiler you did not test must not see their build break on a warning in your code. Same rule as Rust's `#![deny(warnings)]` (lang-08 §21.3) and for the same reason.
* Vendored code is exempt (§16): it is included as `SYSTEM` and has `COMPILE_WARNING_AS_ERROR OFF`.
* Enforced by `lint-checks/cpp/warnings-as-errors`: PASS when a CI command enables `-Werror`, `/WX` or `COMPILE_WARNING_AS_ERROR`, when the preset CI selects with `--preset` (or one it inherits) enables it, or when `CMakeLists.txt`/`cmake/*.cmake` enables it and a CI step runs the build; WARN when the build configuration enables it but no CI step builds the project or CI selects a different preset; FAIL otherwise. `-Werror=<one-warning>` does not count.

## 3. Build System

* **CMake 3.25+** with **Ninja**. One `CMakeLists.txt` per target directory; `add_subdirectory`, not one 2,000-line root file.
* **Presets, not README incantations.** `CMakePresets.json` (version 6) is committed and is the only way CI configures, builds and tests. Copy [`templates/cpp/CMakePresets.json`](../../templates/cpp/CMakePresets.json). `CMakeUserPresets.json` is gitignored and holds personal overrides. Required presets:

  | Preset | Purpose |
  | --- | --- |
  | `dev` | Debug, warnings on, warnings-as-errors off, `compile_commands.json` exported |
  | `ci` | RelWithDebInfo, `CMAKE_COMPILE_WARNING_AS_ERROR=ON`, tests on |
  | `ci-asan-ubsan` | `ci` plus `-fsanitize=address,undefined` (§13) |
  | `ci-tsan` | `ci` plus `-fsanitize=thread` — a separate build; TSan cannot share a binary with ASan |
  | `release` | Release, LTO on where the toolchain supports it, tests off |

  Workflow presets (`cmake --workflow --preset ci`) chain configure, build and test so a CI job is one line.
* **Target-based everything.** `target_compile_features`, `target_compile_options`, `target_include_directories`, `target_link_libraries` with `PUBLIC`/`PRIVATE`/`INTERFACE`. No `include_directories()`, `add_definitions()`, `link_libraries()` or `CMAKE_CXX_FLAGS` edits in project code; those leak into every consumer.
* **Sources are listed, not globbed.** `file(GLOB ...)` hides a forgotten file until the build that misses it; list sources explicitly.
* **Export `compile_commands.json`** (`CMAKE_EXPORT_COMPILE_COMMANDS ON` in the `dev` preset): clang-tidy, clangd and include-what-you-use all read it.
* **Install and package.** A library target has `install(TARGETS ... EXPORT)`, a `<Project>Config.cmake` and a version file, so a consumer can `find_package(Project 1.2 CONFIG REQUIRED)`.
* **Dependencies** (§15): a manifest plus a lock. `vcpkg.json` with `builtin-baseline`, `conanfile.py` with `conan.lock`, or `FetchContent` pinned to a tag **and** `GIT_TAG <full-sha>` with `FIND_PACKAGE_ARGS` so a system package can satisfy it.

## 4. Code Style

* **Formatter:** `clang-format` (version pinned in the README; the matrix's Clang version). `.clang-format` at the project root is the single style file; copy [`templates/cpp/.clang-format`](../../templates/cpp/.clang-format). Commit only formatted code. CI runs `clang-format --dry-run --Werror $(git ls-files '*.cpp' '*.hpp' ...)` (or `cmake --build --target format-check`). Enforced by `lint-checks/cpp/clang-format-config`: PASS when a root `.clang-format` exists with content, WARN when it is empty or lives only in a subdirectory, FAIL when missing.
* **Static analysis:** `clang-tidy` with the committed [`templates/cpp/.clang-tidy`](../../templates/cpp/.clang-tidy) (bugprone, cert, cppcoreguidelines, modernize, performance, portability, readability, with the noisy checks turned off deliberately, not wholesale). `--warnings-as-errors='*'` in CI: the `ci` preset sets `<PROJECT>_ENABLE_CLANG_TIDY=ON`, which `ProjectWarnings.cmake` turns into `CMAKE_CXX_CLANG_TIDY` for the targets the project owns, or a dedicated `clang-tidy` job runs over `compile_commands.json`. Suppressions are `// NOLINT(check-name): <reason>`, never a bare `// NOLINT`.
* **Line length 100**, 4-space indent, no tabs, braces on the same line (`Attach`), `east const` is **not** used (`const T&`, left-aligned pointers `T* p`).
* **Includes** are grouped and sorted by clang-format: the matching header first, then project headers, then third-party, then the standard library; `"project/..."` for the project's own headers, `<...>` for everything else.
* **`auto`** where the type is obvious from the right-hand side or is an iterator/lambda; spell the type out when it is a domain type the reader needs to see.
* **No macros** for constants, functions or control flow. `constexpr`, `inline` functions and templates cover every case except include guards, export annotations (§10) and platform `#if`s (§14).
* **`[[nodiscard]]`** on every function whose return value is a status or a resource.

## 5. Naming Conventions

| Entity | Style | Example |
| --- | --- | --- |
| Namespaces | `snake_case`, one per project, nested by layer | `mesh_core::io` |
| Types (class, struct, enum, alias, concept) | `PascalCase` | `MeshBuilder`, `VertexId` |
| Functions, methods, variables, parameters | `snake_case` | `build_normals()`, `vertex_count` |
| Private data members | `snake_case_` with trailing underscore | `vertices_` |
| Constants and enumerators | `kPascalCase` | `kMaxVertices`, `Status::kNotFound` |
| Template parameters | `PascalCase` | `template <typename Allocator>` |
| Macros (rare, §4) | `UPPER_SNAKE_CASE` with project prefix | `MESH_CORE_EXPORT` |
| Files | `snake_case.hpp` / `snake_case.cpp`; tests `snake_case_test.cpp` | `mesh_builder.hpp` |
| C ABI symbols (§10) | `<prefix>_<noun>_<verb>` | `dust3d_mesh_create` |

Enumerations are `enum class`; never `enum`. Booleans read as predicates (`is_closed`, `has_normals`). Getters have no `get_` prefix (`size()`, not `get_size()`).

## 6. Project Structure

```text
include/
└── mesh_core/                # Public headers only; one directory per library
    ├── mesh.hpp
    ├── export.hpp            # MESH_CORE_EXPORT visibility macro (§10)
    └── expected.hpp          # std::expected / tl::expected alias (§9)
src/
├── mesh/                     # Implementation, private headers next to .cpp
│   ├── mesh.cpp
│   └── mesh_internal.hpp
└── platform/                 # The only directory allowed to #if on the OS (§14)
    ├── file_posix.cpp
    └── file_windows.cpp
bindings/
└── c/                        # extern "C" facade (§10): mesh_core_c.h + .cpp
tests/
├── unit/
├── conformance/              # Golden vectors shared with the wrappers (arch-07 §2)
└── fuzz/
cmake/
├── ProjectWarnings.cmake
└── MeshCoreConfig.cmake.in
third_party/                  # Vendored verbatim (§16), own .clang-format with DisableFormat
CMakeLists.txt
CMakePresets.json
.clang-format
.clang-tidy
```

Domain and application layers (core-standards) are plain C++ with no OS, UI or binding includes; `src/platform/` and `bindings/` are the infrastructure layer.

## 7. Header Hygiene and Modules

* **Self-contained headers.** Every header compiles on its own (`#include` what you use; CI can run `include-what-you-use` or a `header-check` target that compiles each public header as its own TU).
* **`#pragma once`** in every header; all three compilers honour it and it cannot be mistyped the way a guard macro can.
* **No `using namespace` and no `using std::x;` at namespace scope in a header.** Inside a function body is fine.
* **Forward-declare** in headers; include the full definition in the `.cpp`. Public headers include only other public headers and the standard library — a private header or third-party header in `include/` leaks the dependency to every consumer.
* **Templates and `inline` in headers only when they must be.** A public header that pulls `<regex>` or `<iostream>` into every consumer is a compile-time regression for all of them. Use PIMPL (`std::unique_ptr<Impl>` with the destructor defined in the `.cpp`) for classes that cross a shared-library boundary or carry heavy private dependencies.
* **ABI-stable public API:** no `std::string`, `std::vector` or other STL types in the signature of a function exported from a shared library that another compiler or standard library may consume; that is the C ABI's job (§10). Within one build tree (static libraries, same compiler) STL types in headers are fine.
* **C++20 modules** are allowed only when every compiler in the matrix (§2) *and* CMake 3.28+ with Ninja 1.11+ are in place, the module is internal to one build tree, and an ADR records the decision. Public interfaces stay headers until the ecosystem (package managers, clang-tidy, IDEs) is uniform; never export a module across the C ABI or to a wrapper language.

## 8. Ownership, Lifetime and RAII

* **No naked `new`/`delete`.** `std::make_unique`, `std::make_shared`, containers and `std::optional` own everything. A raw pointer is always non-owning and may be null unless the comment says otherwise; `gsl::not_null`/`std::reference_wrapper` or a reference expresses "never null".
* **`std::unique_ptr` is the default owner.** `std::shared_ptr` needs a sentence in the comment saying who the co-owners are. No `std::shared_ptr<T>` parameters where a `T&` or `const T&` would do.
* **Borrow with views:** `std::span<const T>` and `std::string_view` for read-only, non-owning parameters. Never store a `string_view`/`span` in a member unless the type's documentation names the owner whose lifetime it is tied to.
* **Rule of zero.** A class either manages one resource and declares all five special members (or deletes copy and defaults move), or it declares none. Destructors and move operations are `noexcept`.
* **No raw owning arrays, no `malloc`/`free` in C++ code** except inside a C-ABI allocator shim (§10) that documents the pairing.
* **Resource handles are types.** `FileHandle`, `GpuBuffer`, not `int fd` or `void*` passed around.
* **Const-correctness:** member functions that do not mutate are `const`; pass by `const&` for anything larger than two words, by value for sinks (`std::string name` then `std::move`).

## 9. Error Handling

* **Expected failures are values.** Public functions that can fail return `expected<T, Error>` (alias in `include/<project>/expected.hpp` to `std::expected` on C++23, `tl::expected` on C++20). `Error` is a small struct: a project `ErrorCode` enum class plus a bounded message. Callers `and_then`/`transform`/`or_else` or match explicitly.
* **Status enums at boundaries.** The C ABI (§10), callbacks into other languages and any `extern "C"` signature return a `<prefix>_status` integer enum: `0` is success, every other value is a documented, stable, never-reused code. The `ErrorCode` → status mapping is one table in the facade.
* **Exceptions are for bugs and resource exhaustion**, inside the core only: `std::bad_alloc`, a violated precondition in a constructor, a corrupted invariant. They are never part of a function's documented contract, never caught to implement control flow, and **never cross the C ABI, a thread boundary or a callback into another runtime** (§10.4).
* **`noexcept`** on destructors, move constructors/assignments, swap and any function the C ABI calls directly.
* **No silent swallowing.** `catch (...) {}` is banned. The only `catch (...)` lives at the C-ABI boundary and converts to a status code plus a diagnostic (§10.4).
* **Assertions:** `assert()` for internal invariants (compiled out in release); a project `PROJECT_EXPECTS(cond)` macro or `[[assume]]`-free `if (!cond) return Error{...}` for preconditions on public input. A violated public-input precondition is an error return, not a crash.
* **Errors carry context, not stack traces.** Format diagnostics with `std::format`/`fmt::format` into a bounded buffer; log at the boundary, once.

## 10. The C ABI Boundary

The C facade (`bindings/c/`) is the only thing Swift, Kotlin/JNI, C#, Python and Rust see. It has stricter rules than the rest of the codebase because a mistake there is a host-process crash with no C++ backtrace, in an app that ships through an app store. The wrapper side — conformance vectors through the FFI, export smoke tests, generated-binding drift gates — is arch-07 §3; this section is the C++ side of the same contract.

### 10.1 Shape of the API

* **`extern "C"`, C99-compatible header.** `bindings/c/<project>_c.h` compiles as C and as C++ (`#ifdef __cplusplus extern "C" {`). It includes only `<stdint.h>`, `<stddef.h>`, `<stdbool.h>` and the project's export header.
* **Opaque handles.** `typedef struct <prefix>_mesh* <prefix>_mesh_handle;` — the struct is never defined in the header. No C++ class, no STL type, no reference, no `bool` in a struct layout (use `uint8_t`/`int32_t`), no `enum` as a parameter, return or field type (a status or flag type is `typedef int32_t <prefix>_status` with its values named by an anonymous `enum` — C99 has no fixed underlying type for `enum`, and C23's `enum e : int32_t` does not compile under the header's C99 floor), no bitfields.
* **Fixed-width scalars only:** `int32_t`, `uint64_t`, `double`, `size_t` for byte counts, `const char*` UTF-8 NUL-terminated for strings. Never `long`, `wchar_t`, `size_t` in a struct that is persisted, or `std::size_t` in the header.
* **Naming:** `<prefix>_<noun>_<verb>` (`dust3d_mesh_create`, `dust3d_mesh_destroy`, `dust3d_mesh_vertex_count`). The prefix is the project's and never changes.
* **Symbol visibility:** `-fvisibility=hidden` (`CMAKE_CXX_VISIBILITY_PRESET hidden`, `CMAKE_VISIBILITY_INLINES_HIDDEN ON`) on every target; only functions annotated `<PREFIX>_EXPORT` (`__attribute__((visibility("default")))` / `__declspec(dllexport)`) are visible. Nothing in `src/` is exported.
* **ABI version:** `<prefix>_abi_version()` returns a monotonically increasing `uint32_t`, and the header defines `<PREFIX>_ABI_VERSION`. A wrapper checks them at load time. Any change to a struct layout, enum value or function signature bumps it; additive changes (new functions) do not.

### 10.2 Ownership and lifetime rules

1. **Every `create` has one `destroy`, and only that `destroy` frees it.** A handle created by `<prefix>_mesh_create` is released by `<prefix>_mesh_destroy`, never by `free()`, never by another type's destroy. The header documents the pair next to each `create`.
2. **No allocator ownership crosses the boundary.** Memory the library allocates is freed by the library; memory the caller allocates is freed by the caller. If the library must return a buffer it does not own a handle for, it provides `<prefix>_buffer_free(ptr)` — or, preferably, takes a caller-provided buffer and returns the required size when it is too small (`required_len` out-parameter, status `kBufferTooSmall`).
3. **Borrowed buffers expire with their owner.** A pointer returned by an accessor (`const float* <prefix>_mesh_vertices(handle, size_t* count)`) is valid only until the next mutating call on that handle or its destruction, whichever is first. The header states this on every accessor. A wrapper that needs to keep the data copies it.
4. **Strings in are borrowed for the call only.** The library never stores a `const char*` the caller passed; it copies into a `std::string` if it needs it later.
5. **Callbacks carry a `void* user_data`** and are invoked only during the API call that registered them unless the header says otherwise; the library never calls back after `destroy` returns.
6. **Null handles are tolerated.** Every accessor on a null handle returns the zero value (`0`, `nullptr`, `kInvalidHandle` status) and never dereferences. `destroy(nullptr)` is a no-op, like `free(NULL)`. A wrapper that fails half-way through construction can tear down unconditionally.
7. **Threading is documented per handle.** By default a handle is **not** thread-safe and the library **serialises engine calls** behind one mutex when the underlying engine (OpenGL context, a global allocator, a third-party library with static state) requires it. The header says which: "all calls are serialised by the library" or "a handle may be used from one thread at a time". Never "probably fine".

### 10.3 Status codes and diagnostics

```c
/* bindings/c/dust3d_c.h */
/* The status type is a fixed-width integer, not an enum: C99 has no way to fix
   an enum's underlying type (C23 does, but this header compiles as C99). The
   anonymous enum only names the values. */
typedef int32_t dust3d_status;
enum {
    DUST3D_OK = 0,
    DUST3D_ERR_INVALID_HANDLE = 1,
    DUST3D_ERR_INVALID_ARGUMENT = 2,
    DUST3D_ERR_BUFFER_TOO_SMALL = 3,
    DUST3D_ERR_PARSE = 4,
    DUST3D_ERR_OUT_OF_MEMORY = 5,
    DUST3D_ERR_INTERNAL = 99   /* a C++ exception reached the boundary; see dust3d_last_error */
};

/* Copies the last diagnostic for the calling thread into buf (always NUL-terminated,
   truncated to buf_len - 1); returns the length that would have been needed. */
DUST3D_EXPORT size_t dust3d_last_error(char* buf, size_t buf_len);
```

* Codes are **stable and never reused**: a removed code stays in the enum as `DUST3D_ERR_RESERVED_N`.
* The diagnostic lives in a **thread-local, fixed-size buffer** (`char[512]`) written with `std::snprintf`, so reporting an error can never itself allocate or throw. The wrapper reads it immediately after a non-zero status.

### 10.4 Catch everything at the boundary

Every `extern "C"` function body is a single `try` whose handlers map to a status; nothing else is allowed to execute outside it.

```cpp
// bindings/c/dust3d_c.cpp
namespace {
thread_local char g_last_error[512] = "";

void set_last_error(const char* what) noexcept {
    std::snprintf(g_last_error, sizeof g_last_error, "%s", what ? what : "unknown error");
}

template <typename Fn>
dust3d_status guarded(Fn&& fn) noexcept {
    try {
        return fn();
    } catch (const std::bad_alloc&) {
        set_last_error("out of memory");
        return DUST3D_ERR_OUT_OF_MEMORY;
    } catch (const std::exception& e) {
        set_last_error(e.what());
        return DUST3D_ERR_INTERNAL;
    } catch (...) {
        set_last_error("non-standard exception");
        return DUST3D_ERR_INTERNAL;
    }
}
}  // namespace

extern "C" DUST3D_EXPORT dust3d_status dust3d_mesh_parse(const uint8_t* bytes, size_t len,
                                                          dust3d_mesh_handle* out) {
    return guarded([&]() -> dust3d_status {
        if (out == nullptr) return DUST3D_ERR_INVALID_ARGUMENT;
        *out = nullptr;
        if (bytes == nullptr && len != 0) return DUST3D_ERR_INVALID_ARGUMENT;
        auto mesh = dust3d::parse(std::span<const uint8_t>{bytes, len});  // expected<Mesh, Error>
        if (!mesh) {
            set_last_error(mesh.error().message.c_str());
            return to_status(mesh.error().code);
        }
        *out = reinterpret_cast<dust3d_mesh_handle>(new dust3d::Mesh(std::move(*mesh)));
        return DUST3D_OK;
    });
}

extern "C" DUST3D_EXPORT void dust3d_mesh_destroy(dust3d_mesh_handle handle) {
    delete reinterpret_cast<dust3d::Mesh*>(handle);  // delete nullptr is a no-op
}
```

* `-fno-exceptions` is **not** the answer: the core may still throw `bad_alloc`, and a third-party library may throw anything. The boundary converts; the lint keeps it honest.
* `std::terminate` is reachable only through a `noexcept` violation, which the `guarded` wrapper makes impossible for the exported functions.
* The wrapper languages' rules for the other side — never store a borrowed pointer past the owner, check the ABI version, run the conformance vectors through the FFI — are in arch-07 §3. The two documents describe one contract.

## 11. Concurrency

* **`std::jthread` + `std::stop_token`**, never `std::thread` without a join plan and never `detach()`.
* **Shared state is protected or atomic.** A data race is undefined behaviour, not a flaky test. `std::mutex`/`std::scoped_lock`, `std::atomic<T>` with the weakest ordering the comment can justify, or message passing. `volatile` is not a synchronisation primitive.
* **Clang thread-safety annotations** (`GUARDED_BY`, `REQUIRES`) on every mutex-protected member when building with Clang; they turn locking mistakes into compile errors.
* **No blocking in callbacks** that arrive from another runtime (a Swift completion handler, a JNI callback); hand off to the engine's own queue.
* **The TSan lane (§13) is mandatory** for any target that creates a thread.

## 12. Testing

* **Framework:** GoogleTest (or Catch2 v3) registered with CTest via `gtest_discover_tests`/`catch_discover_tests`. `ctest --test-dir build --output-on-failure` is the only test command CI runs; a test preset wraps it.
* **Layout:** `tests/unit/<module>_test.cpp` mirrors `src/`; `tests/conformance/` holds the golden vectors shared with every wrapper (arch-07 §2); `tests/fuzz/` holds libFuzzer targets for every parser and decoder (`-fsanitize=fuzzer`, run with a time budget in CI, corpus committed).
* **Coverage:** 95% minimum per target, 100% for domain logic (core-standards). `--coverage` with `gcovr` (GCC) or `-fprofile-instr-generate -fcoverage-mapping` with `llvm-cov` (Clang); the `ci` preset turns it on and the gate reads the report. The C facade is covered through the conformance suite, which calls the `extern "C"` API, not the C++ classes behind it.
* **Death tests** for every precondition that aborts in debug; **no test depends on undefined behaviour** (the sanitizer lanes run the same test binaries).
* **Determinism:** no wall-clock, no network, no filesystem outside a per-test temp dir created by the fixture. Random inputs use a seeded `std::mt19937_64` and print the seed on failure.
* **Cross-platform tests:** path handling, line endings and encoding (§14) have tests that run on all three OSes, not just the one the author uses.

## 13. Sanitizer Lanes

Sanitizers find the bugs the warnings cannot. They run the **test suite**, not just the build, on every PR.

| Lane | Preset | Flags | Platforms |
| --- | --- | --- | --- |
| ASan + UBSan | `ci-asan-ubsan` | `-fsanitize=address,undefined -fno-omit-frame-pointer -fno-sanitize-recover=all` | Linux (Clang or GCC), macOS (Clang); MSVC `/fsanitize=address` for ASan only |
| TSan | `ci-tsan` | `-fsanitize=thread -fno-omit-frame-pointer` | Linux Clang; required when any target spawns a thread |
| MSan (optional) | `ci-msan` | `-fsanitize=memory -fsanitize-memory-track-origins` | Linux Clang only; requires an instrumented libc++ |

* Environment in CI: `ASAN_OPTIONS=detect_leaks=1:strict_string_checks=1:check_initialization_order=1` (`detect_leaks=0` on macOS, where LSan is unavailable), `UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1`, `TSAN_OPTIONS=halt_on_error=1 second_deadlock_stack=1`.
* ASan and TSan are **separate builds**; they cannot be combined in one binary.
* Sanitizer lanes build with the §17 hardening flags **off**: `_FORTIFY_SOURCE` and AddressSanitizer interfere, and the lane measures the sanitizer. On MSVC, `/fsanitize=address` is incompatible with `/RTC1` and incremental linking, so the `ci-msvc-asan` preset replaces the default Debug flags (`/MDd /Zi /Ob0 /Od`, `/INCREMENTAL:NO`).
* Hardened standard library in Debug and sanitizer builds: `-D_GLIBCXX_ASSERTIONS` (libstdc++) or `-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_EXTENSIVE` (libc++ 18+) so `operator[]` is bounds-checked where the sanitizer cannot see.
* A finding in a sanitizer lane is a bug, not a flake; suppressions (`-fsanitize-blacklist`, `ASAN_OPTIONS=suppressions=`) name a third-party library and an issue number, never project code.
* Enforced by `lint-checks/cpp/sanitizer-lane`: PASS when a CI step passes `-fsanitize=`/`/fsanitize=`, or selects a CMake preset that (itself or through `inherits`) sets it, **and** CI runs the tests (`ctest`, a `cmake --workflow` whose preset has a test step, `make test`); WARN when the sanitizer build never runs the tests, when CI selects a sanitizer-named preset that sets no flag, or when a sanitizer preset or option exists but no CI lane runs it; FAIL when CI has no sanitizer lane.

## 14. Cross-Platform Rules

### Files, encoding, line endings

* **Source files are UTF-8 without BOM.** `.editorconfig` (`charset = utf-8`, `end_of_line = lf`, `insert_final_newline = true`, `indent_style = space`, `indent_size = 4`) and `.gitattributes` with `* text=auto eol=lf` plus explicit `-text` for binaries (`*.png`, `*.bin`, `*.obj`, test fixtures), so a Windows checkout cannot turn a fixture into CRLF.
* **Compilers read UTF-8:** `/utf-8` on MSVC (source and execution charset), `-finput-charset=UTF-8` is already the default on GCC/Clang. Without `/utf-8` a string literal with a non-ASCII character is silently re-encoded on Windows.
* **Text data is UTF-8 end to end.** `std::string` holds UTF-8; `std::u8string` only where a type-level guarantee helps; **no `wchar_t`/`std::wstring` in portable APIs** (it is 16-bit on Windows and 32-bit elsewhere). Convert at the Win32 call (`MultiByteToWideChar`) in `src/platform/`, nowhere else.
* **Line endings in data:** parsers accept `\n` and `\r\n`; writers emit `\n` unless the format mandates otherwise. Tests contain both.

### Paths and the filesystem

* `std::filesystem::path` everywhere; build paths with `/`, never string concatenation. `path::u8string()` when a UTF-8 `std::string` is needed; `path::native()` only inside `src/platform/`.
* Case-sensitive filesystems are the norm (Linux, iOS devices); `#include` paths and asset names must match case exactly. CI runs on Linux so a macOS-only mismatch is caught.
* No path longer than 260 characters assumed to work on Windows without the long-path manifest; no reserved names (`aux.cpp`, `con.hpp`, `nul`).

### Integers, layout and the ABI

* Fixed-width types (`<cstdint>`) in anything serialised, persisted or crossing the C ABI. `int` and `long` differ between MSVC and everyone else (`long` is 32-bit on Windows).
* `std::endian::native` checks and explicit byte-swap (`std::byteswap`, C++23, or a project helper) in binary readers; never `reinterpret_cast` a struct onto a byte buffer (alignment and padding are compiler-defined). Use `std::memcpy` or `std::bit_cast`.
* Struct layouts that cross the ABI are `static_assert(sizeof(T) == N)` and `static_assert(std::is_standard_layout_v<T>)`.

### Platform code

* **One place:** `src/platform/` is the only directory where `#if defined(_WIN32)`, `__APPLE__`, `__linux__`, `__ANDROID__`, `__EMSCRIPTEN__` appear. Everything else calls a platform-neutral interface. Prefer separate `*_posix.cpp`/`*_windows.cpp` files selected in CMake over `#if` ladders inside one file.
* **`windows.h` never appears in a public header.** Where it is included: `#define WIN32_LEAN_AND_MEAN` and `#define NOMINMAX` first.
* **`std::min`/`std::max`** are written `(std::min)(a, b)` only in files that must include `windows.h`; elsewhere `NOMINMAX` makes the parentheses unnecessary.
* **Symbol export** is `__declspec(dllexport)`/`dllimport` on Windows and `visibility("default")` elsewhere, behind one generated or hand-written `export.hpp` (`GenerateExportHeader` does it).
* **No `#pragma comment(lib, ...)`, no `__declspec` in portable code, no `#pragma pack` without a matching `static_assert`.**
* **Shell and scripts:** build helpers are CMake scripts (`cmake -P`) or Python, not bash — Windows CI has neither bash nor coreutils by default.

## 15. Dependencies and Supply Chain

* **Manifest + lock, always:** `vcpkg.json` with `builtin-baseline` (and `vcpkg-configuration.json` for registries), or `conanfile.py` + `conan.lock`, or `FetchContent` with `GIT_TAG` set to a full commit SHA (a tag can move). `make deps-update` (arch-02) is the only way the lock changes.
* **Audit:** CI runs `osv-scanner --lockfile vcpkg.json` (or the Conan equivalent) and fails on known CVEs (sec-01 §5). Header-only libraries count too.
* **Licenses:** an allow-list in `THIRD_PARTY_LICENSES.md` (or `vcpkg` `license` field checks); a new copyleft dependency fails review until consciously added. Every vendored library's license file ships with it.
* **System packages** are satisfied with `find_package(... CONFIG)` first and `FetchContent` as fallback (`FIND_PACKAGE_ARGS`), so distro packagers and Homebrew users are not forced to rebuild the world.
* **No Git submodules for dependencies** in new projects; they bypass the lock and the audit.

## 16. Vendored Code Preservation

Inherited and vendored code (a third-party engine, a historical codebase a product grew from, a header-only library copied in) is kept **verbatim** so upstream diffs stay reviewable and upstream fixes still apply.

* **Lives in `third_party/<name>/`** with an `UPSTREAM.md` naming the origin URL, version or commit, license, and the list of local modifications (file, reason, issue). An empty modifications list is the goal.
* **No mass reformat, ever.** `third_party/.clang-format` contains `DisableFormat: true` and `SortIncludes: Never`; `.clang-tidy` excludes it via `HeaderFilterRegex`; the pre-commit hook and the CI format check skip it. A reformatting commit destroys the ability to `git diff` against upstream and to apply upstream patches, and it buries any real change in noise.
* **No drive-by modernisation.** Do not fix warnings, rename identifiers, replace `NULL` with `nullptr` or convert to `enum class` in vendored code. Warnings are silenced at the build level: `target_include_directories(... SYSTEM ...)` and `set_target_properties(<vendored> PROPERTIES COMPILE_WARNING_AS_ERROR OFF)`; a vendored target may carry its own, narrower warning set.
* **Changes are patches.** A necessary local fix lands as `third_party/<name>/patches/NNNN-<slug>.patch` applied at configure time (or recorded in `UPSTREAM.md` when applied in place), with an upstream issue or PR link. Prefer wrapping (an adapter in `src/`) over editing.
* **Coverage and lint treat it as `inherited`:** declare `layer: inherited` in `coverage.scopes` (proc-05 § 6) with the upstream suite as the stated reason, and list the directory in `lint.exclude` for the banned-function scans (`no-secrets` still runs — a vendored secret is still a secret).
* **Updating** replaces the directory wholesale from the new upstream version, re-applies the patches, and bumps `UPSTREAM.md` in one `chore(third_party): bump <name> to <version>` commit.
* **Ownership of code you inherited** (not from a public upstream) follows the same rules until the team decides to adopt it: adoption is an ADR plus a *single* reformatting commit, after which the directory moves out of `third_party/` and the normal standards apply.

## 17. Security

* **Banned functions** (sec-01 §4): `gets`, `strcpy`, `strcat`, `sprintf`, `vsprintf`, `scanf("%s")` without a width, `strtok`, `atoi`/`atol`/`atof` on untrusted input (no error reporting — use `std::from_chars`), `system()`, `popen()`, `tmpnam`, `rand()` for anything security-relevant, `alloca`, raw `memcpy` into a buffer whose size is not checked on the same line. `clang-tidy`'s `cert-*` and `bugprone-*` groups flag most of these; the rest is review.
* **Bounds:** `std::span`, `.at()` in non-hot paths, hardened library mode in Debug/sanitizer builds (§13), `-fsanitize=bounds` under UBSan. Every length that arrives across the C ABI is validated against the buffer it describes before use.
* **Integer safety:** `-Wconversion -Wsign-conversion` in the warning set; checked arithmetic (`__builtin_add_overflow`, `std::add_sat` in C++26, or a project helper) on sizes computed from untrusted input before any allocation.
* **Hardening flags** in `release` and `ci`: `-D_FORTIFY_SOURCE=3 -fstack-protector-strong -fstack-clash-protection -fPIE -pie -Wl,-z,relro,-z,now -Wl,-z,noexecstack` (GCC/Clang, Linux), `-fcf-protection=full` on x86-64; `/GS /guard:cf /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA /SDL` on MSVC. On macOS, hardened runtime and library validation at codesign time.
* **Randomness:** `std::random_device` is acceptable on the mainstream platforms for seeding; secrets and tokens come from the OS CSPRNG (`getrandom(2)`, `SecRandomCopyBytes`, `BCryptGenRandom`) or a vetted crypto library (libsodium, OpenSSL 3), never `<random>` engines alone.
* **Parsing untrusted input** gets a fuzz target (§12) and runs under ASan/UBSan in CI before it ships.
* **Secrets** are never compiled in; `#define API_KEY` and `constexpr char kToken[]` are hardcoded-credential P0 findings. Configuration arrives through the platform's secure store or environment at runtime.
* See [sec-01_security_standards.md](../security/sec-01_security_standards.md) for the severity model and the cross-language tables.

## 18. Documentation

* **Public headers carry Doxygen comments** (`///` or `/** */`) on every exported type and function: one-line summary, parameters (ownership and lifetime for pointers — §10.2), return value, error codes, thread-safety. `doxygen -g` config committed; `WARN_AS_ERROR = YES` in the docs lane so an undocumented export fails.
* **The C header is the wrapper authors' manual.** Every `extern "C"` declaration states: who allocates, who frees, how long a returned pointer lives, which status codes it can return, and whether it may be called concurrently. An undocumented rule does not exist.
* **README build matrix:** the compiler/OS table from §2 as the project actually tests it, the preset names, and the one command that runs everything (`cmake --workflow --preset ci`).
* **ADRs** (proc-01) for: raising or lowering the language baseline or compiler floor, adopting modules or coroutines, changing the ABI version policy, adopting inherited code (§16).

## 19. Enforcement

| Rule | Mechanism |
| --- | --- |
| Root `.clang-format` committed (§4) | `lint-checks/cpp/clang-format-config` |
| Warnings as errors in CI (§2) | `lint-checks/cpp/warnings-as-errors` |
| Sanitizer lane in CI (§13) | `lint-checks/cpp/sanitizer-lane` |
| Formatting, naming, include order (§4, §5) | `clang-format --dry-run --Werror`, `clang-tidy` `readability-identifier-naming` |
| No `new`/`delete`, no C arrays, no `catch (...)` outside the facade (§8, §9) | `clang-tidy` `cppcoreguidelines-owning-memory`, `cppcoreguidelines-avoid-c-arrays`, `bugprone-empty-catch` + review |
| Banned functions (§17) | `clang-tidy` `cert-*`, `bugprone-*`, review |
| C ABI contract (§10) | Conformance suite through the FFI, export smoke tests, ABI-version check (arch-07 §3) |
| Vendored code untouched (§16) | `third_party/.clang-format` with `DisableFormat: true`; `UPSTREAM.md` reviewed on every change under `third_party/` |
