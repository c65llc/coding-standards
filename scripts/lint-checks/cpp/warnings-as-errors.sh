#!/bin/bash
# Check: C++ warnings are treated as errors in the CI build
# (lang-14 §2: warnings-as-errors in CI, not hard-coded for consumers —
# `CMAKE_COMPILE_WARNING_AS_ERROR=ON` in the CI preset, `-Werror` or `/WX`)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="cpp/warnings-as-errors"

# What counts. A bare `-Werror` (optionally quoted or at end of line), MSVC's
# `/WX`, or CMake's COMPILE_WARNING_AS_ERROR variable/property. `-Werror=foo`
# promotes a single diagnostic and is deliberately NOT matched.
PATTERN='(^|[[:space:]"'"'"'=,;(])-Werror([[:space:]"'"'"'),;]|$)|(^|[[:space:]"'"'"'=,;(])/WX([[:space:]"'"'"'),;]|$)|COMPILE_WARNING_AS_ERROR[[:space:]"]*[:=]?[[:space:]"]*(ON|TRUE|YES|1)\b|COMPILE_WARNING_AS_ERROR[[:space:]]+(ON|TRUE|YES|1)\b'

# Lines that are comments in YAML, CMake or shell (`#`) or JSON-with-comments
# (`//`) must not satisfy the gate.
strip_comments() {
    grep -vE '^[[:space:]]*(#|//)' 2>/dev/null
}

# matches_pattern <text>: 0 when the text (comments removed) enables -Werror.
matches_pattern() {
    printf '%s\n' "$1" | strip_comments | grep -qE -- "$PATTERN"
}

# --- Self-test (proc-05 § 7): the detector must trip on known-good input and
# stay quiet on known-bad input, or the module refuses to report.
self_test() {
    matches_pattern 'run: cmake -B build -DCMAKE_CXX_FLAGS="-Wall -Werror"' || return 1
    matches_pattern '"CMAKE_COMPILE_WARNING_AS_ERROR": "ON"' || return 1
    matches_pattern 'set(CMAKE_COMPILE_WARNING_AS_ERROR ON)' || return 1
    matches_pattern 'cmake -B build -DCMAKE_CXX_FLAGS="/W4 /WX"' || return 1
    matches_pattern 'add_compile_options(-Wall -Wextra -Werror)' || return 1
    matches_pattern 'add_compile_options(-Werror=unused-variable)' && return 1
    matches_pattern '# -Werror would go here' && return 1
    matches_pattern 'run: cmake -B build && cmake --build build' && return 1
    return 0
}
if ! self_test; then
    echo "FAIL $CHECK_NAME self-test failed (detector rot, refusing to report): -Werror/WX pattern no longer matches its fixtures"
    exit 1
fi

# --- Candidate files -----------------------------------------------------------

# CI definitions: GitHub workflows plus the common single-file CIs.
CI_FILES=""
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    CI_FILES=$(find "$PROJECT_ROOT/.github/workflows" -maxdepth 1 \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)
fi
for extra in .gitlab-ci.yml .circleci/config.yml .buildkite/pipeline.yml azure-pipelines.yml; do
    if [ -f "$PROJECT_ROOT/$extra" ]; then
        CI_FILES="${CI_FILES}
$PROJECT_ROOT/$extra"
    fi
done
HAS_CI=false
if [ -n "$(printf '%s' "$CI_FILES" | tr -d '[:space:]')" ]; then
    HAS_CI=true
fi

# Build configuration CI runs: presets, the root CMakeLists and cmake/ modules,
# plus a Makefile/justfile when a CI definition delegates to one.
BUILD_FILES=""
for f in CMakePresets.json CMakeUserPresets.json CMakeLists.txt meson.build; do
    if [ -f "$PROJECT_ROOT/$f" ]; then
        BUILD_FILES="${BUILD_FILES}
$PROJECT_ROOT/$f"
    fi
done
if [ -d "$PROJECT_ROOT/cmake" ]; then
    cmake_modules=$(find "$PROJECT_ROOT/cmake" -maxdepth 2 -name "*.cmake" 2>/dev/null)
    if [ -n "$cmake_modules" ]; then
        BUILD_FILES="${BUILD_FILES}
$cmake_modules"
    fi
fi
if [ "$HAS_CI" = true ]; then
    delegates=false
    while IFS= read -r file; do
        [ -n "$file" ] && [ -f "$file" ] || continue
        if grep -qE '(^|[[:space:]:;&|(])(make|just)([[:space:]]|$)' "$file" 2>/dev/null; then
            delegates=true
            break
        fi
    done <<< "$CI_FILES"
    if [ "$delegates" = true ]; then
        for runner in Makefile justfile Justfile; do
            if [ -f "$PROJECT_ROOT/$runner" ]; then
                BUILD_FILES="${BUILD_FILES}
$PROJECT_ROOT/$runner"
            fi
        done
    fi
fi

# first_match <file-list>: prints "rel:line" of the first enabling line, if any.
first_match() {
    local file rel line
    while IFS= read -r file; do
        [ -n "$file" ] && [ -f "$file" ] || continue
        line=$(strip_comments < "$file" | grep -nE -- "$PATTERN" | head -1 | cut -d: -f1)
        if [ -n "$line" ]; then
            rel="${file#"$PROJECT_ROOT"/}"
            # The line number counts non-comment lines; re-derive the real one.
            real=$(grep -nE -- "$PATTERN" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|//)' | head -1 | cut -d: -f1)
            printf '%s:%s\n' "$rel" "${real:-$line}"
            return 0
        fi
    done <<< "$1"
    return 1
}

if [ "$HAS_CI" = false ] && [ -z "$(printf '%s' "$BUILD_FILES" | tr -d '[:space:]')" ]; then
    echo "FAIL $CHECK_NAME No CI workflow, CMakePresets.json or CMakeLists.txt found — enable CMAKE_COMPILE_WARNING_AS_ERROR=ON in the CI preset"
    exit 1
fi

ci_hit=""
if [ "$HAS_CI" = true ]; then
    ci_hit=$(first_match "$CI_FILES" || true)
fi
build_hit=$(first_match "$BUILD_FILES" || true)

if [ -n "$ci_hit" ]; then
    echo "PASS $CHECK_NAME warnings treated as errors in CI ($ci_hit)"
    exit 0
fi

if [ -n "$build_hit" ]; then
    if [ "$HAS_CI" = true ]; then
        echo "PASS $CHECK_NAME warnings treated as errors via build configuration CI runs ($build_hit)"
        exit 0
    fi
    echo "WARN $CHECK_NAME $build_hit enables warnings-as-errors but no CI definition runs the build — nothing enforces it"
    exit 2
fi

if [ "$HAS_CI" = false ]; then
    echo "FAIL $CHECK_NAME No CI workflow found (.github/workflows, .gitlab-ci.yml, .circleci) — the CI build must set CMAKE_COMPILE_WARNING_AS_ERROR=ON (or -Werror / /WX)"
    exit 1
fi

echo "FAIL $CHECK_NAME Warnings are not treated as errors — set CMAKE_COMPILE_WARNING_AS_ERROR=ON in the CI preset (templates/cpp/CMakePresets.json), or pass -Werror (gcc/clang) and /WX (MSVC) in the CI build"
exit 1
