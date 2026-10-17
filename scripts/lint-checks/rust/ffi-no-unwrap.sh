#!/bin/bash
# Check: no panicking calls in FFI / wasm facade modules
# (lang-08 §21: panics must not cross the extern "C" / wasm boundary)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="rust/ffi-no-unwrap"

# File enumeration (git ls-files with pruned-find fallback, built-in
# cache/worktree exclusions, `.standards.yml` lint.exclude, and the runner's
# --since/--changed scope) lives in scripts/lib/lint-files.sh.
LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../lib/lint-files.sh
source "$LINT_LIB"

# Facade files: ffi.rs / wasm.rs, *_ffi.rs / *_wasm.rs, and anything under an
# ffi/ or wasm/ source directory.
FACADE_ERE='(^|/)(ffi|wasm)\.rs$|_(ffi|wasm)\.rs$|/(ffi|wasm)/.*\.rs$'
FACADE_FILES=$(lint_list_files "$PROJECT_ROOT" | grep -E "$FACADE_ERE" || true)

# Filenames containing a newline cannot be carried by the file list; report
# them rather than skipping them silently.
UNSCANNABLE=$(lint_unscannable_files "$PROJECT_ROOT" | grep -E "$FACADE_ERE" || true)

if [ -z "$FACADE_FILES" ] && [ -z "$UNSCANNABLE" ]; then
    echo "PASS $CHECK_NAME No FFI/wasm facade files found (ffi.rs, wasm.rs, ffi/, wasm/)"
    exit 0
fi

# Calls that panic. Indexing and arithmetic overflow also panic but cannot be
# found reliably with grep; clippy's disallowed-methods + deny lints cover those.
PANIC_PATTERN='\.(unwrap|expect|unwrap_err|expect_err)[[:space:]]*\(|(^|[^[:alnum:]_])(panic|unreachable|todo|unimplemented|assert|assert_eq|assert_ne)![[:space:]]*\('

VIOLATIONS=""
TOTAL=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Drop line comments and doc comments; keep code. There is deliberately no
    # opt-out: an `allow(clippy::…)` annotation silences clippy, not the panic,
    # and a panic across the boundary aborts the host process regardless.
    matches=$(grep -nE "$PANIC_PATTERN" "$file" 2>/dev/null \
        | grep -vE '^[0-9]+:[[:space:]]*//' \
        || true)
    if [ -n "$matches" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
        TOTAL=$((TOTAL + count))
        first_line=$(printf '%s\n' "$matches" | head -1 | cut -d: -f1)
        VIOLATIONS="${VIOLATIONS}${rel}:${first_line} (${count}); "
    fi
done <<< "$FACADE_FILES"

if [ -n "$UNSCANNABLE" ]; then
    n=$(echo "$UNSCANNABLE" | wc -l | tr -d ' ')
    TOTAL=$((TOTAL + n))
    VIOLATIONS="${VIOLATIONS}${n} file(s) not scanned (newline in filename): $(echo "$UNSCANNABLE" | head -3 | tr '\n' ' '); "
fi

if [ -z "$VIOLATIONS" ]; then
    count=$(printf '%s\n' "$FACADE_FILES" | wc -l | tr -d ' ')
    echo "PASS $CHECK_NAME $count FFI/wasm facade file(s) free of unwrap/expect/panic"
    exit 0
fi

VIOLATIONS="${VIOLATIONS%; }"
echo "FAIL $CHECK_NAME $TOTAL panicking call(s) in FFI/wasm facade — $VIOLATIONS — return error codes/Results across the boundary"
exit 1
