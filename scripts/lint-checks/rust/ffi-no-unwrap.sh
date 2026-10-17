#!/bin/bash
# Check: no panicking calls in FFI / wasm facade modules
# (lang-08 §21: panics must not cross the extern "C" / wasm boundary)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="rust/ffi-no-unwrap"

# Facade files: ffi.rs / wasm.rs, *_ffi.rs / *_wasm.rs, and anything under an
# ffi/ or wasm/ source directory.
FACADE_FILES=$(find "$PROJECT_ROOT" -type f \
    \( -name "ffi.rs" -o -name "wasm.rs" -o -name "*_ffi.rs" -o -name "*_wasm.rs" \
       -o -path "*/ffi/*.rs" -o -path "*/wasm/*.rs" \) \
    -not -path "*/.git/*" \
    -not -path "*/target/*" \
    -not -path "*/node_modules/*" \
    -not -path "*/.standards/*" \
    -not -path "*/.standards_tmp/*" \
    2>/dev/null)

if [ -z "$FACADE_FILES" ]; then
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
    # Drop line comments and doc comments; keep code. Also skip lines that
    # opt out explicitly with a SAFETY/allow annotation on the same line.
    matches=$(grep -nE "$PANIC_PATTERN" "$file" 2>/dev/null \
        | grep -vE '^[0-9]+:[[:space:]]*//' \
        | grep -vE 'allow\(clippy::(unwrap_used|expect_used|disallowed_methods|panic)\)' \
        || true)
    if [ -n "$matches" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        count=$(printf '%s\n' "$matches" | wc -l | tr -d ' ')
        TOTAL=$((TOTAL + count))
        first_line=$(printf '%s\n' "$matches" | head -1 | cut -d: -f1)
        VIOLATIONS="${VIOLATIONS}${rel}:${first_line} (${count}); "
    fi
done <<< "$FACADE_FILES"

if [ -z "$VIOLATIONS" ]; then
    count=$(printf '%s\n' "$FACADE_FILES" | wc -l | tr -d ' ')
    echo "PASS $CHECK_NAME $count FFI/wasm facade file(s) free of unwrap/expect/panic"
    exit 0
fi

VIOLATIONS="${VIOLATIONS%; }"
echo "FAIL $CHECK_NAME $TOTAL panicking call(s) in FFI/wasm facade — $VIOLATIONS — return error codes/Results across the boundary"
exit 1
