#!/bin/bash
# Check: clang-format configuration committed at the project root
# (lang-14 §4: `.clang-format` is the single formatter config; CI runs
# `clang-format --dry-run --Werror`)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="cpp/clang-format-config"

# clang-format reads either spelling; `.clang-format` is the conventional one.
CONFIG=""
for candidate in .clang-format _clang-format; do
    if [ -f "$PROJECT_ROOT/$candidate" ]; then
        CONFIG="$candidate"
        break
    fi
done

if [ -z "$CONFIG" ]; then
    # A config nested below the root formats only that subtree; the standard
    # wants one root config so every source file (and CI) uses the same style.
    nested=$(find "$PROJECT_ROOT" -mindepth 2 -maxdepth 3 \( -name ".clang-format" -o -name "_clang-format" \) \
        -not -path "*/.git/*" -not -path "*/build/*" -not -path "*/third_party/*" -not -path "*/vendor/*" \
        -not -path "*/.standards/*" -not -path "*/node_modules/*" 2>/dev/null | head -1)
    if [ -n "$nested" ]; then
        rel="${nested#"$PROJECT_ROOT"/}"
        echo "WARN $CHECK_NAME $rel exists but no root .clang-format — move it to the project root (copy templates/cpp/.clang-format) so one style covers every source file"
        exit 2
    fi
    echo "FAIL $CHECK_NAME No .clang-format at the project root — copy templates/cpp/.clang-format and run 'clang-format --dry-run --Werror' in CI"
    exit 1
fi

# An empty or comment-only file makes clang-format fall back to LLVM defaults
# silently, which is not a committed style decision.
if ! grep -qE '^[[:space:]]*[A-Za-z]' "$PROJECT_ROOT/$CONFIG" 2>/dev/null; then
    echo "WARN $CHECK_NAME $CONFIG is empty — declare BasedOnStyle (and the project's overrides) so the style is explicit"
    exit 2
fi

# A `third_party/` tree should carry its own `DisableFormat: true` so the
# root style never mass-reformats vendored code (lang-14 §16). Advisory.
note=""
for vendored in third_party vendor external; do
    if [ -d "$PROJECT_ROOT/$vendored" ] && [ ! -f "$PROJECT_ROOT/$vendored/.clang-format" ]; then
        note="; $vendored/ has no .clang-format with DisableFormat: true (lang-14 §16)"
        break
    fi
done

if grep -qE '^[[:space:]]*BasedOnStyle[[:space:]]*:' "$PROJECT_ROOT/$CONFIG" 2>/dev/null; then
    echo "PASS $CHECK_NAME $CONFIG present with BasedOnStyle$note"
else
    echo "PASS $CHECK_NAME $CONFIG present (explicit options, no BasedOnStyle)$note"
fi
exit 0
