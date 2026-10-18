# C++ Templates

Copy-and-fill configuration for the tooling
[lang-14_cpp_standards.md](../../standards/languages/lang-14_cpp_standards.md)
requires. Each file is self-describing; the table says where it goes.

| Template | Copy to | Standard | Enforced by |
|----------|---------|----------|-------------|
| [`.clang-format`](.clang-format) | project root | lang-14 §4 | `lint-checks/cpp/clang-format-config`, `clang-format --dry-run --Werror` in CI |
| [`.clang-tidy`](.clang-tidy) | project root | lang-14 §4, §5, §8 | `PROJECT_ENABLE_CLANG_TIDY=ON` in the `ci` preset (sets `CMAKE_CXX_CLANG_TIDY` with `--warnings-as-errors=*`) |
| [`CMakePresets.json`](CMakePresets.json) | project root | lang-14 §3, §13, §17 | `lint-checks/cpp/warnings-as-errors` (the `ci` preset sets `CMAKE_COMPILE_WARNING_AS_ERROR=ON`), `lint-checks/cpp/sanitizer-lane` (the `ci-asan-ubsan` / `ci-tsan` / `ci-msvc-asan` workflow presets configure, build **and test**) |
| [`ProjectWarnings.cmake`](ProjectWarnings.cmake) | `cmake/ProjectWarnings.cmake` | lang-14 §1, §2, §4, §12, §13, §17 | linked as `${PROJECT_NAME}_warnings` (alias `${PROJECT_NAME}::warnings`) by every target the project owns |

`ProjectWarnings.cmake` owns every switch the presets flip: `PROJECT_WARNINGS_AS_ERRORS`,
`PROJECT_HARDENED_STDLIB`, `PROJECT_HARDENING_FLAGS`, `PROJECT_ENABLE_COVERAGE`
and `PROJECT_ENABLE_CLANG_TIDY`, plus the C++20 requirement
(`target_compile_features(... INTERFACE cxx_std_20)`) so the standard reaches
only the targets that link it — never a dependency pulled in with
`FetchContent`.

## After copying

1. Rename the `PROJECT_` option prefix in `ProjectWarnings.cmake` and
   `CMakePresets.json` to your project's (`MESH_CORE_WARNINGS_AS_ERRORS`, ...),
   and `include(ProjectWarnings)` from the root `CMakeLists.txt` after
   `project()`. The warnings target is named after the project automatically
   (`mesh_core_warnings` for `project(mesh_core)`), so two libraries built from
   this template can be combined without a target-name collision.
2. Add `CMakeUserPresets.json` to `.gitignore`; personal overrides live there.
3. Create `third_party/.clang-format` so vendored code is never reformatted
   (lang-14 §16), and `set(CMAKE_CXX_CLANG_TIDY "")` in `third_party/CMakeLists.txt`
   so clang-tidy never runs on it:

   ```yaml
   DisableFormat: true
   SortIncludes: Never
   ```

4. Wire CI to the presets. One job per lane, each a single command that
   configures, builds and runs the tests (a sanitizer that never executes
   finds nothing; `lint-checks/cpp/sanitizer-lane` looks for the test step):

   ```yaml
   - run: cmake --workflow --preset ci
   - run: cmake --workflow --preset ci-asan-ubsan   # Linux/macOS runners
   - run: cmake --workflow --preset ci-tsan         # Linux runner, when any target spawns a thread
   - run: cmake --workflow --preset ci-msvc-asan    # Windows runner
   ```

   The `ci` preset builds with the release hardening flags on so a hardening
   option a toolchain rejects surfaces on every PR, not at packaging time. The
   sanitizer lanes turn hardening off: `_FORTIFY_SOURCE` and AddressSanitizer
   interfere, and the lane measures the sanitizer. `ci-msvc-asan` replaces the
   default MSVC Debug flags because `/fsanitize=address` is incompatible with
   `/RTC1` and incremental linking.

5. Pin the `clang-format` / `clang-tidy` version in the README build matrix
   (the matrix's Clang version) so formatting is reproducible across machines.
