#!/bin/bash
# Check: CI has a sanitizer lane (ASan/UBSan, TSan, or MSVC /fsanitize) that
# runs the test suite
# (lang-14 §13: tests run under -fsanitize=address,undefined on every PR;
# a separate TSan lane for concurrent code. "They run the test suite, not just
# the build.")
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="cpp/sanitizer-lane"

# Preset resolution (which configure preset a `--preset <name>` selects and
# what it inherits) lives in scripts/lib/cmake-presets.sh.
PRESETS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/cmake-presets.sh"
if [ ! -f "$PRESETS_LIB" ]; then
    echo "WARN $CHECK_NAME cmake-presets library not found ($PRESETS_LIB)"
    exit 2
fi
# shellcheck source=../../lib/cmake-presets.sh
source "$PRESETS_LIB"

# A sanitizer is enabled by `-fsanitize=<list>` (gcc/clang), `/fsanitize=address`
# (MSVC), or CMake's ECM/ project conventions (`ECM_ENABLE_SANITIZERS`,
# `ENABLE_SANITIZERS`, `<PROJECT>_SANITIZE=ON`).
FLAG_PATTERN='[-/]fsanitize=[[:alnum:],_-]+|ECM_ENABLE_SANITIZERS|ENABLE_SANITIZERS?[[:space:]"]*[:=]?[[:space:]"]*(ON|TRUE|YES|1)\b|_SANITIZE(RS)?[[:space:]"]*[:=]?[[:space:]"]*(ON|TRUE|YES|1)\b'

# A CMake preset whose name says it is a sanitizer build.
PRESET_NAME_PATTERN='(asan|ubsan|tsan|msan|lsan|sanitiz)'

# `--preset <name>` as CI writes it (`--preset ci`, `--preset=ci`, quoted).
PRESET_SELECT_PREFIX='--preset[[:space:]=]+["'"'"']?'
PRESET_SELECT="${PRESET_SELECT_PREFIX}[[:alnum:]_.-]+"

# A step that runs the tests: ctest, a test target, a runner's test recipe,
# or a cmake workflow (checked below against the workflow's steps). A build
# alone does not count — a sanitizer that never executes finds nothing.
TEST_PATTERN='(^|[[:space:]:;&|(`"'"'"'])ctest(\.exe)?([[:space:]"'"'"'&|;)]|$)|--target[[:space:]=]+(test|check|RUN_TESTS|run[_-]tests?)([[:space:]"'"'"'&|;)]|$)|(^|[[:space:]:;&|(])(make|gmake|just|ninja|meson|bazel|cargo)[[:space:]]+(test|check)([[:space:]&|;)]|$)|(^|[[:space:]/=])(run[_-]tests?|unit[_-]tests?|test[_-]runner|gtest[[:alnum:]_-]*|catch2?[[:alnum:]_-]*_tests?)([[:space:]"'"'"'&|;)]|$)'
WORKFLOW_PATTERN='--workflow'

strip_comments() {
    grep -vE '^[[:space:]]*(#|//)' 2>/dev/null
}

has_flag() {
    printf '%s\n' "$1" | strip_comments | grep -qE -- "$FLAG_PATTERN"
}

runs_tests() {
    printf '%s\n' "$1" | strip_comments | grep -qE -- "$TEST_PATTERN"
}

selects_sanitizer_preset() {
    printf '%s\n' "$1" | grep -qiE -- "${PRESET_SELECT_PREFIX}[[:alnum:]_.-]*${PRESET_NAME_PATTERN}"
}

# preset_name <text>: the name the first `--preset` in <text> selects.
preset_name() {
    printf '%s\n' "$1" | grep -oE -- "$PRESET_SELECT" | sed -E "s/^${PRESET_SELECT_PREFIX}//" | head -1
}

# --- Self-test (proc-05 § 7) ----------------------------------------------------
self_test() {
    has_flag 'run: cmake -B build -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined"' || return 1
    has_flag '"CMAKE_CXX_FLAGS": "-fsanitize=address -fno-omit-frame-pointer"' || return 1
    has_flag 'cmake -B build -DCMAKE_CXX_FLAGS="/fsanitize=address"' || return 1
    has_flag 'set(ENABLE_SANITIZERS ON)' || return 1
    has_flag '# -fsanitize=address is only mentioned in this comment' && return 1
    has_flag 'run: cmake -B build && cmake --build build' && return 1
    selects_sanitizer_preset 'run: cmake --workflow --preset ci-asan-ubsan' || return 1
    selects_sanitizer_preset 'run: cmake --preset ci' && return 1
    runs_tests 'run: ctest --test-dir build --output-on-failure' || return 1
    runs_tests 'run: cmake --build build --target test' || return 1
    runs_tests '      make test' || return 1
    runs_tests 'run: ./build/tests/unit_tests' || return 1
    runs_tests 'run: cmake -B build && cmake --build build' && return 1
    runs_tests '# ctest is only mentioned in this comment' && return 1
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

PRESET_FILES=()
for f in CMakePresets.json CMakeUserPresets.json; do
    [ -f "$PROJECT_ROOT/$f" ] && PRESET_FILES+=("$PROJECT_ROOT/$f")
done

# Everything CI runs, comments removed, for the test-step and preset scans.
CI_TEXT=""
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    CI_TEXT="${CI_TEXT}
$(strip_comments < "$file")"
done <<< "$CI_FILES"

# --- Does CI run the tests at all? ----------------------------------------------
# ctest / a test target / a runner recipe, or `cmake --workflow --preset X`
# where workflow X has a test step. A workflow whose preset the committed
# files do not define cannot be checked and is given the benefit of the doubt.
ci_runs_tests=false
if runs_tests "$CI_TEXT"; then
    ci_runs_tests=true
elif printf '%s\n' "$CI_TEXT" | grep -qE -- "$WORKFLOW_PATTERN"; then
    if [ "${#PRESET_FILES[@]}" -eq 0 ]; then
        ci_runs_tests=true
    else
        while IFS= read -r wf; do
            [ -n "$wf" ] || continue
            body=$(cmake_preset_body workflowPresets "$wf" "${PRESET_FILES[@]}") || { ci_runs_tests=true; break; }
            if printf '%s\n' "$body" | grep -qE '"type"[[:space:]]*:[[:space:]]*"test"'; then
                ci_runs_tests=true
                break
            fi
        done <<< "$(printf '%s\n' "$CI_TEXT" | grep -E -- "$WORKFLOW_PATTERN" | grep -oE -- "$PRESET_SELECT" | sed -E "s/^${PRESET_SELECT_PREFIX}//" | sort -u)"
    fi
fi

no_tests_msg="but no step runs the tests under it (ctest, cmake --workflow with a test step, make test) — a sanitizer lane must execute the test suite (lang-14 §13)"

# 1. A sanitizer flag directly in a CI step (or the Makefile CI delegates to).
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    line=$(grep -nE -- "$FLAG_PATTERN" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(#|//)' | head -1 | cut -d: -f1)
    if [ -n "$line" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        if [ "$ci_runs_tests" = true ]; then
            echo "PASS $CHECK_NAME sanitizer lane runs the tests in CI ($rel:$line)"
            exit 0
        fi
        echo "WARN $CHECK_NAME CI builds with a sanitizer ($rel:$line) $no_tests_msg"
        exit 2
    fi
done <<< "$CI_FILES"

# 2. CI selects a CMake preset. Resolve each selected name to its configure
#    preset plus everything it inherits, and look for the flag there — not
#    anywhere in the file, so an unsanitized `ci-asan` does not pass on the
#    strength of an unused `dev` preset.
presets_have_flag=false
for file in ${PRESET_FILES[@]+"${PRESET_FILES[@]}"}; do
    if strip_comments < "$file" | grep -qE -- "$FLAG_PATTERN"; then
        presets_have_flag=true
        break
    fi
done

sanitized_preset=""
unknown_sanitizer_preset=""
unflagged_sanitizer_preset=""
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    name=$(preset_name "$hit")
    [ -n "$name" ] || continue
    wf_flag=""
    printf '%s\n' "$hit" | grep -qE -- "$WORKFLOW_PATTERN" && wf_flag="--workflow"
    # shellcheck disable=SC2086  # $wf_flag is an optional bare flag
    if resolved=$(cmake_preset_resolve $wf_flag "$name" ${PRESET_FILES[@]+"${PRESET_FILES[@]}"}); then
        if printf '%s\n' "$resolved" | grep -qE -- "$FLAG_PATTERN"; then
            sanitized_preset="$name"
            break
        fi
        printf '%s' "$name" | grep -qiE -- "$PRESET_NAME_PATTERN" && unflagged_sanitizer_preset="${unflagged_sanitizer_preset:-$name}"
    else
        printf '%s' "$name" | grep -qiE -- "$PRESET_NAME_PATTERN" && unknown_sanitizer_preset="${unknown_sanitizer_preset:-$name}"
    fi
done <<< "$(printf '%s\n' "$CI_TEXT" | grep -oE -- "--workflow.*${PRESET_SELECT}|${PRESET_SELECT}" | sort -u)"

if [ -n "$sanitized_preset" ]; then
    if [ "$ci_runs_tests" = true ]; then
        echo "PASS $CHECK_NAME sanitizer preset runs the tests in CI (--preset $sanitized_preset)"
        exit 0
    fi
    echo "WARN $CHECK_NAME CI selects sanitizer preset '$sanitized_preset' $no_tests_msg"
    exit 2
fi
if [ -n "$unflagged_sanitizer_preset" ]; then
    echo "WARN $CHECK_NAME CI selects sanitizer-named preset '$unflagged_sanitizer_preset' but neither it nor anything it inherits sets -fsanitize — the lane does not sanitize anything"
    exit 2
fi
if [ -n "$unknown_sanitizer_preset" ]; then
    echo "WARN $CHECK_NAME CI selects sanitizer-named preset '$unknown_sanitizer_preset' that CMakePresets.json does not define (CMakeUserPresets.json is not committed) — cannot verify the lane sanitizes"
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
