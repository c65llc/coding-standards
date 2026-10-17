#!/bin/bash
# Check: CI runs `cargo clippy` with `-D warnings`
# (lang-08 §2/§21: lints warn locally, CI denies them)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="rust/clippy-ci"

# Collect CI definitions: GitHub workflows plus the common single-file CIs.
CI_FILES=""
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    CI_FILES=$(find "$PROJECT_ROOT/.github/workflows" -maxdepth 1 \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)
fi
for extra in .gitlab-ci.yml .circleci/config.yml .buildkite/pipeline.yml; do
    if [ -f "$PROJECT_ROOT/$extra" ]; then
        CI_FILES="${CI_FILES}
$PROJECT_ROOT/$extra"
    fi
done
# Also accept the repo's own Makefile / justfile when CI delegates to it.
for runner in Makefile justfile Justfile; do
    if [ -f "$PROJECT_ROOT/$runner" ]; then
        CI_FILES="${CI_FILES}
$PROJECT_ROOT/$runner"
    fi
done

if [ -z "$(printf '%s' "$CI_FILES" | tr -d '[:space:]')" ]; then
    echo "FAIL $CHECK_NAME No CI workflow found (.github/workflows, .gitlab-ci.yml, .circleci) — cargo clippy -D warnings must run in CI"
    exit 1
fi

CLIPPY_LINES=""
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    matches=$(grep -nE 'cargo[[:space:]]+(\+[[:alnum:].-]+[[:space:]]+)?clippy' "$file" 2>/dev/null || true)
    if [ -n "$matches" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        CLIPPY_LINES="${CLIPPY_LINES}${rel}:${matches}
"
    fi
done <<< "$CI_FILES"

if [ -z "$CLIPPY_LINES" ]; then
    echo "FAIL $CHECK_NAME No CI step runs cargo clippy — add 'cargo clippy --workspace --all-targets --all-features -- -D warnings'"
    exit 1
fi

# -D warnings may be passed inline, as --deny warnings, or via RUSTFLAGS/CLIPPY env.
if printf '%s' "$CLIPPY_LINES" | grep -qE -- '(-D|--deny)[[:space:]]+warnings'; then
    first=$(printf '%s' "$CLIPPY_LINES" | grep -E -- '(-D|--deny)[[:space:]]+warnings' | head -1 | cut -d: -f1,2)
    echo "PASS $CHECK_NAME cargo clippy runs with -D warnings in CI ($first)"
    exit 0
fi

env_deny=""
while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    if grep -qE '(RUSTFLAGS|CLIPPY_FLAGS|RUSTDOCFLAGS)[[:space:]]*[:=][[:space:]]*["'"'"']?[^"'"'"'#]*(-D|--deny)[[:space:]]+warnings' "$file" 2>/dev/null; then
        env_deny="${file#"$PROJECT_ROOT"/}"
        break
    fi
done <<< "$CI_FILES"

if [ -n "$env_deny" ]; then
    echo "PASS $CHECK_NAME cargo clippy runs in CI with warnings denied via environment ($env_deny)"
    exit 0
fi

first=$(printf '%s' "$CLIPPY_LINES" | head -1 | cut -d: -f1,2)
echo "WARN $CHECK_NAME cargo clippy runs in CI ($first) but without -D warnings — lints are advisory, add '-- -D warnings'"
exit 2
