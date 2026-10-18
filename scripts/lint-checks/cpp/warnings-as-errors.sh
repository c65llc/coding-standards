#!/bin/bash
# Check: C++ warnings are treated as errors in the CI build
# (lang-14 §2: warnings-as-errors in CI, not hard-coded for consumers —
# `CMAKE_COMPILE_WARNING_AS_ERROR=ON` in the CI preset, `-Werror` or `/WX`)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="cpp/warnings-as-errors"

# Preset resolution (which configure preset a `--preset <name>` selects and
# what it inherits) lives in scripts/lib/cmake-presets.sh.
PRESETS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/cmake-presets.sh"
if [ ! -f "$PRESETS_LIB" ]; then
    echo "WARN $CHECK_NAME cmake-presets library not found ($PRESETS_LIB)"
    exit 2
fi
# shellcheck source=../../lib/cmake-presets.sh
source "$PRESETS_LIB"

# What counts. A bare `-Werror` (optionally quoted or at end of line), MSVC's
# `/WX`, or CMake's COMPILE_WARNING_AS_ERROR variable/property. `-Werror=foo`
# promotes a single diagnostic and is deliberately NOT matched.
PATTERN='(^|[[:space:]"'"'"'=,;(])-Werror([[:space:]"'"'"'),;]|$)|(^|[[:space:]"'"'"'=,;(])/WX([[:space:]"'"'"'),;]|$)|COMPILE_WARNING_AS_ERROR[[:space:]"]*[:=]?[[:space:]"]*(ON|TRUE|YES|1)\b|COMPILE_WARNING_AS_ERROR[[:space:]]+(ON|TRUE|YES|1)\b'

# A CI step that builds: a build tool invocation, or an action that wraps one.
# A workflow that only publishes docs does not run the configuration, so a
# `-Werror` in CMakeLists.txt enforces nothing there.
BUILD_TOOL_PATTERN='(^|[[:space:]:;&|(`"'"'"'])(cmake|ctest|cpack|make|gmake|nmake|just|ninja|meson|msbuild|bazel|xcodebuild|scons)(\.exe)?([[:space:]"'"'"'&|;)]|$)|uses:[[:space:]]*[^[:space:]]*(cmake|msbuild)'

# `--preset <name>` as CI writes it (`--preset ci`, `--preset=ci`, quoted).
PRESET_SELECT_PREFIX='--preset[[:space:]=]+["'"'"']?'
PRESET_SELECT="${PRESET_SELECT_PREFIX}[[:alnum:]_.-]+"
WORKFLOW_PATTERN='--workflow'

# Lines that are comments in YAML, CMake or shell (`#`) or JSON-with-comments
# (`//`) must not satisfy the gate.
strip_comments() {
    grep -vE '^[[:space:]]*(#|//)' 2>/dev/null
}

# matches_pattern <text>: 0 when the text (comments removed) enables -Werror.
matches_pattern() {
    printf '%s\n' "$1" | strip_comments | grep -qE -- "$PATTERN"
}

# builds <text>: 0 when the text (comments removed) invokes a build tool.
builds() {
    printf '%s\n' "$1" | strip_comments | grep -qE -- "$BUILD_TOOL_PATTERN"
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
    builds 'run: cmake --workflow --preset ci' || return 1
    builds '      - run: make all' || return 1
    builds 'uses: lukka/run-cmake@v10' || return 1
    builds 'run: mkdocs build --strict' && return 1
    builds '# cmake would go here' && return 1
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

# Build configuration: presets on one side (CI selects them by name, so a hit
# is correlated with the preset CI runs), the root CMakeLists, cmake/ modules
# and meson.build on the other (any cmake/meson invocation runs them), plus a
# Makefile/justfile when a CI definition delegates to one.
PRESET_FILES=()
for f in CMakePresets.json CMakeUserPresets.json; do
    [ -f "$PROJECT_ROOT/$f" ] && PRESET_FILES+=("$PROJECT_ROOT/$f")
done
BUILD_FILES=""
for f in CMakeLists.txt meson.build; do
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

preset_hit=""
if [ "${#PRESET_FILES[@]}" -gt 0 ]; then
    preset_hit=$(first_match "$(printf '%s\n' "${PRESET_FILES[@]}")" || true)
fi
build_hit=$(first_match "$BUILD_FILES" || true)

if [ "$HAS_CI" = false ] && [ -z "$preset_hit$build_hit" ] && [ "${#PRESET_FILES[@]}" -eq 0 ] && [ -z "$(printf '%s' "$BUILD_FILES" | tr -d '[:space:]')" ]; then
    echo "FAIL $CHECK_NAME No CI workflow, CMakePresets.json or CMakeLists.txt found — enable CMAKE_COMPILE_WARNING_AS_ERROR=ON in the CI preset"
    exit 1
fi

# 1. The flag is on a CI command line.
if [ "$HAS_CI" = true ]; then
    ci_hit=$(first_match "$CI_FILES" || true)
    if [ -n "$ci_hit" ]; then
        echo "PASS $CHECK_NAME warnings treated as errors in CI ($ci_hit)"
        exit 0
    fi
fi

if [ -z "$preset_hit$build_hit" ]; then
    if [ "$HAS_CI" = false ]; then
        echo "FAIL $CHECK_NAME No CI workflow found (.github/workflows, .gitlab-ci.yml, .circleci) — the CI build must set CMAKE_COMPILE_WARNING_AS_ERROR=ON (or -Werror / /WX)"
        exit 1
    fi
    echo "FAIL $CHECK_NAME Warnings are not treated as errors — set CMAKE_COMPILE_WARNING_AS_ERROR=ON in the CI preset (templates/cpp/CMakePresets.json), or pass -Werror (gcc/clang) and /WX (MSVC) in the CI build"
    exit 1
fi

# The build configuration enables it somewhere. Does CI run that configuration?
if [ "$HAS_CI" = false ]; then
    echo "WARN $CHECK_NAME ${preset_hit:-$build_hit} enables warnings-as-errors but no CI definition runs the build — nothing enforces it"
    exit 2
fi

CI_TEXT=""
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    CI_TEXT="${CI_TEXT}
$(strip_comments < "$file")"
done <<< "$CI_FILES"

if ! builds "$CI_TEXT"; then
    echo "WARN $CHECK_NAME ${preset_hit:-$build_hit} enables warnings-as-errors but no CI step builds the project (no cmake, make, ninja or msbuild invocation) — nothing enforces it"
    exit 2
fi

# 2. A preset enables it: PASS only when CI selects that preset (or one that
#    inherits it). `CMakePresets.json` carrying it in `ci` while CI runs
#    `--preset dev` enforces nothing.
preset_warn=""
if [ -n "$preset_hit" ]; then
    selected=$(printf '%s\n' "$CI_TEXT" | grep -oE -- "--workflow.*${PRESET_SELECT}|${PRESET_SELECT}" | sort -u)
    if [ -z "$selected" ]; then
        preset_warn="$preset_hit enables warnings-as-errors but no CI step selects a preset (--preset) — the CI build does not use it"
    else
        unknown="" names=""
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            name=$(printf '%s\n' "$hit" | grep -oE -- "$PRESET_SELECT" | sed -E "s/^${PRESET_SELECT_PREFIX}//" | head -1)
            [ -n "$name" ] || continue
            names="${names:+$names }$name"
            wf_flag=""
            printf '%s\n' "$hit" | grep -qE -- "$WORKFLOW_PATTERN" && wf_flag="--workflow"
            # shellcheck disable=SC2086  # $wf_flag is an optional bare flag
            if resolved=$(cmake_preset_resolve $wf_flag "$name" "${PRESET_FILES[@]}"); then
                if printf '%s\n' "$resolved" | grep -qE -- "$PATTERN"; then
                    echo "PASS $CHECK_NAME warnings treated as errors via the preset CI selects (--preset $name, $preset_hit)"
                    exit 0
                fi
            else
                unknown="${unknown:-$name}"
            fi
        done <<< "$selected"
        if [ -n "$unknown" ]; then
            preset_warn="CI selects preset '$unknown' that CMakePresets.json does not define (CMakeUserPresets.json is not committed) — cannot verify it enables warnings-as-errors ($preset_hit does)"
        else
            preset_warn="$preset_hit enables warnings-as-errors in a preset CI never selects (CI selects: $names) — the CI build does not enforce it"
        fi
    fi
fi

# 3. CMakeLists.txt, a cmake/ module, meson.build or the delegated runner
#    enables it and CI invokes the build: every configure runs those files.
if [ -n "$build_hit" ]; then
    echo "PASS $CHECK_NAME warnings treated as errors via build configuration CI runs ($build_hit)"
    exit 0
fi

echo "WARN $CHECK_NAME $preset_warn"
exit 2
