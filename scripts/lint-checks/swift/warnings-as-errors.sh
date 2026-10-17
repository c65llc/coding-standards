#!/bin/bash
# Check: Swift warnings treated as errors in the build gate
# (lang-04 §2: -warnings-as-errors in CI, or SWIFT_TREAT_WARNINGS_AS_ERRORS / treatAllWarnings)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="swift/warnings-as-errors"

# Where the flag may legitimately live.
CANDIDATES=""
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    CANDIDATES=$(find "$PROJECT_ROOT/.github/workflows" -maxdepth 1 \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)
fi
for f in Package.swift Makefile justfile Justfile project.yml Project.swift .gitlab-ci.yml; do
    [ -f "$PROJECT_ROOT/$f" ] && CANDIDATES="${CANDIDATES}
$PROJECT_ROOT/$f"
done
xcconfigs=$(find "$PROJECT_ROOT" -maxdepth 3 -name "*.xcconfig" -not -path "*/.build/*" -not -path "*/.git/*" 2>/dev/null)
[ -n "$xcconfigs" ] && CANDIDATES="${CANDIDATES}
$xcconfigs"
scripts=$(find "$PROJECT_ROOT" -maxdepth 2 -name "*.sh" -not -path "*/.build/*" -not -path "*/.git/*" -not -path "*/.standards/*" 2>/dev/null)
[ -n "$scripts" ] && CANDIDATES="${CANDIDATES}
$scripts"

# Swift-specific mechanisms only: a bare `-Werror` is a C/C++/Java flag
# (CFLAGS, javac) and says nothing about Swift warnings.
PATTERN='-warnings-as-errors|SWIFT_TREAT_WARNINGS_AS_ERRORS[[:space:]]*[:=][[:space:]]*"?YES|treatAllWarnings[[:space:]]*\([[:space:]]*as:[[:space:]]*\.error|-Xswiftc[[:space:]]+-warnings-as-errors'

while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    line=$(grep -nE -e "$PATTERN" "$file" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 || true)
    if [ -n "$line" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        echo "PASS $CHECK_NAME warnings treated as errors ($rel:$(printf '%s' "$line" | cut -d: -f1))"
        exit 0
    fi
done <<< "$CANDIDATES"

if [ -z "$(printf '%s' "$CANDIDATES" | tr -d '[:space:]')" ]; then
    echo "FAIL $CHECK_NAME No CI workflow, Package.swift or project spec found to enable -warnings-as-errors"
    exit 1
fi

echo "FAIL $CHECK_NAME Warnings are not treated as errors — add 'swift build -Xswiftc -warnings-as-errors' to CI (or SWIFT_TREAT_WARNINGS_AS_ERRORS: YES in project.yml)"
exit 1
