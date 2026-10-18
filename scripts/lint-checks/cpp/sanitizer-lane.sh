#!/bin/bash
# Check: CI has a sanitizer lane (ASan/UBSan, TSan, or MSVC /fsanitize)
# (lang-14 §13: tests run under -fsanitize=address,undefined on every PR;
# a separate TSan lane for concurrent code)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="cpp/sanitizer-lane"

# A sanitizer is enabled by `-fsanitize=<list>` (gcc/clang), `/fsanitize=address`
# (MSVC), or CMake's ECM/ project conventions (`ECM_ENABLE_SANITIZERS`,
# `ENABLE_SANITIZERS`, `<PROJECT>_SANITIZE=ON`).
FLAG_PATTERN='[-/]fsanitize=[[:alnum:],_-]+|ECM_ENABLE_SANITIZERS|ENABLE_SANITIZERS?[[:space:]"]*[:=]?[[:space:]"]*(ON|TRUE|YES|1)\b|_SANITIZE(RS)?[[:space:]"]*[:=]?[[:space:]"]*(ON|TRUE|YES|1)\b'

# A CMake preset whose name says it is a sanitizer build, or a CI step that
# selects one.
PRESET_NAME_PATTERN='(asan|ubsan|tsan|msan|lsan|sanitiz)'

strip_comments() {
    grep -vE '^[[:space:]]*(#|//)' 2>/dev/null
}

has_flag() {
    printf '%s\n' "$1" | strip_comments | grep -qE -- "$FLAG_PATTERN"
}

# --- Self-test (proc-05 § 7) ----------------------------------------------------
self_test() {
    has_flag 'run: cmake -B build -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"' || return 1
    has_flag '"CMAKE_CXX_FLAGS": "-fsanitize=address -fno-omit-frame-pointer"' || return 1
    has_flag 'cmake -B build -DCMAKE_CXX_FLAGS="/fsanitize=address"' || return 1
    has_flag 'set(ENABLE_SANITIZERS ON)' || return 1
    has_flag '# -fsanitize=address is only mentioned in this comment' && return 1
    has_flag 'run: cmake -B build && cmake --build build' && return 1
    printf '%s\n' 'run: cmake --workflow --preset ci-asan-ubsan' | grep -qiE -- "--preset[[:space:]=]+[\"']?[[:alnum:]_.-]*${PRESET_NAME_PATTERN}" || return 1
    printf '%s\n' 'run: cmake --preset ci' | grep -qiE -- "--preset[[:space:]=]+[\"']?[[:alnum:]_.-]*${PRESET_NAME_PATTERN}" && return 1
    return 0
}
if ! self_test; then
    echo "FAIL $CHECK_NAME self-test failed (detector rot, refusing to report): sanitizer pattern no longer matches its fixtures"
    exit 1
fi

# --- CI definitions ------------------------------------------------------------
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
if [ -z "$(printf '%s' "$CI_FILES" | tr -d '[:space:]')" ]; then
    echo "FAIL $CHECK_NAME No CI workflow found (.github/workflows, .gitlab-ci.yml, .circleci) — tests must run under -fsanitize=address,undefined in CI"
    exit 1
fi

# A Makefile/justfile counts when a CI definition delegates to it.
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
            CI_FILES="${CI_FILES}
$PROJECT_ROOT/$runner"
        fi
    done
fi

# 1. A sanitizer flag directly in a CI step (or the Makefile CI delegates to).
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    line=$(grep -nE -- "$FLAG_PATTERN" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|//)' | head -1 | cut -d: -f1)
    if [ -n "$line" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        echo "PASS $CHECK_NAME sanitizer lane runs in CI ($rel:$line)"
        exit 0
    fi
done <<< "$CI_FILES"

# 2. CI selects a CMake preset whose name is a sanitizer build, and the preset
#    exists with a sanitizer flag (or at least exists — a preset named asan that
#    sets no -fsanitize is reported, not trusted).
PRESET_FILES=""
for f in CMakePresets.json CMakeUserPresets.json; do
    [ -f "$PROJECT_ROOT/$f" ] && PRESET_FILES="${PRESET_FILES}
$PROJECT_ROOT/$f"
done
presets_have_flag=false
if [ -n "$(printf '%s' "$PRESET_FILES" | tr -d '[:space:]')" ]; then
    while IFS= read -r file; do
        [ -n "$file" ] && [ -f "$file" ] || continue
        if strip_comments < "$file" | grep -qE -- "$FLAG_PATTERN"; then
            presets_have_flag=true
            break
        fi
    done <<< "$PRESET_FILES"
fi

ci_preset=""
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    hit=$(strip_comments < "$file" | grep -oiE -- "--preset[[:space:]=]+[\"']?[[:alnum:]_.-]*${PRESET_NAME_PATTERN}[[:alnum:]_.-]*" | head -1)
    if [ -n "$hit" ]; then
        ci_preset="${file#"$PROJECT_ROOT"/}: $hit"
        break
    fi
done <<< "$CI_FILES"

if [ -n "$ci_preset" ]; then
    if [ "$presets_have_flag" = true ]; then
        echo "PASS $CHECK_NAME sanitizer preset runs in CI ($ci_preset)"
        exit 0
    fi
    echo "WARN $CHECK_NAME CI selects a sanitizer-named preset ($ci_preset) but no CMakePresets.json sets -fsanitize — the lane may not sanitize anything"
    exit 2
fi

# 3. A sanitizer preset or option exists but nothing in CI runs it.
if [ "$presets_have_flag" = true ]; then
    echo "WARN $CHECK_NAME CMakePresets.json defines a sanitizer build but no CI step selects it — add a lane running 'cmake --workflow --preset ci-asan-ubsan'"
    exit 2
fi
if [ -f "$PROJECT_ROOT/CMakeLists.txt" ] && strip_comments < "$PROJECT_ROOT/CMakeLists.txt" | grep -qE -- "$FLAG_PATTERN|option[[:space:]]*\([[:space:]]*[A-Za-z0-9_]*SANITIZ"; then
    echo "WARN $CHECK_NAME CMakeLists.txt offers a sanitizer option but no CI lane enables it — add an ASan/UBSan job"
    exit 2
fi

echo "FAIL $CHECK_NAME No sanitizer lane in CI — add a job that builds with -fsanitize=address,undefined (templates/cpp/CMakePresets.json: ci-asan-ubsan) and runs the tests"
exit 1
