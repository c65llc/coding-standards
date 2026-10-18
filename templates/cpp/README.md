# C++ Templates

Copy-and-fill configuration for the tooling
[lang-14_cpp_standards.md](../../standards/languages/lang-14_cpp_standards.md)
requires. Each file is self-describing; the table says where it goes.

| Template | Copy to | Standard | Enforced by |
|----------|---------|----------|-------------|
| [`.clang-format`](.clang-format) | project root | lang-14 §4 | `lint-checks/cpp/clang-format-config`, `clang-format --dry-run --Werror` in CI |
| [`.clang-tidy`](.clang-tidy) | project root | lang-14 §4, §5, §8 | `clang-tidy --warnings-as-errors='*'` in CI |
| [`CMakePresets.json`](CMakePresets.json) | project root | lang-14 §3, §13 | `lint-checks/cpp/warnings-as-errors` (the `ci` preset sets `CMAKE_COMPILE_WARNING_AS_ERROR=ON`), `lint-checks/cpp/sanitizer-lane` (the `ci-asan-ubsan` / `ci-tsan` presets) |
| [`ProjectWarnings.cmake`](ProjectWarnings.cmake) | `cmake/ProjectWarnings.cmake` | lang-14 §2, §13, §17 | linked as `project_warnings` by every target the project owns |

## After copying

1. Rename the `PROJECT_` option prefix in `ProjectWarnings.cmake` and
   `CMakePresets.json` to your project's (`MESH_CORE_WARNINGS_AS_ERRORS`, ...),
   and `include(ProjectWarnings)` from the root `CMakeLists.txt`.
2. Add `CMakeUserPresets.json` to `.gitignore`; personal overrides live there.
3. Create `third_party/.clang-format` so vendored code is never reformatted
   (lang-14 §16):

   ```yaml
   DisableFormat: true
   SortIncludes: Never
   ```

4. Wire CI to the presets. One job per lane, each a single command:

   ```yaml
   - run: cmake --workflow --preset ci
   - run: cmake --workflow --preset ci-asan-ubsan   # Linux/macOS runners
   - run: cmake --workflow --preset ci-tsan         # Linux runner, when any target spawns a thread
   - run: cmake --workflow --preset ci-msvc-asan    # Windows runner
   ```

5. Pin the `clang-format` / `clang-tidy` version in the README build matrix
   (the matrix's Clang version) so formatting is reproducible across machines.
