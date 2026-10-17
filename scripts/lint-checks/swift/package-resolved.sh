#!/bin/bash
# Check: Package.resolved committed for packages with dependencies
# (lang-04 §1: the lockfile is committed for apps and executables)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="swift/package-resolved"

if [ ! -f "$PROJECT_ROOT/Package.swift" ]; then
    echo "WARN $CHECK_NAME No Package.swift found — SwiftPM is the required package manager (lang-04 §1)"
    exit 2
fi

# Dependency-free packages have nothing to pin.
if ! grep -qE '\.package[[:space:]]*\(' "$PROJECT_ROOT/Package.swift" 2>/dev/null; then
    echo "PASS $CHECK_NAME Package.swift declares no external dependencies; no Package.resolved required"
    exit 0
fi

# Root Package.resolved, or the Xcode workspace location for app projects.
RESOLVED=""
if [ -f "$PROJECT_ROOT/Package.resolved" ]; then
    RESOLVED="Package.resolved"
else
    xc=$(find "$PROJECT_ROOT" -maxdepth 5 -path "*/xcshareddata/swiftpm/Package.resolved" -not -path "*/.build/*" 2>/dev/null | head -1)
    if [ -n "$xc" ]; then
        RESOLVED="${xc#"$PROJECT_ROOT"/}"
    fi
fi

if [ -z "$RESOLVED" ]; then
    echo "FAIL $CHECK_NAME Package.swift has dependencies but no Package.resolved — run 'swift package resolve' and commit it"
    exit 1
fi

# Must actually be tracked by git (not ignored / untracked) when in a repo.
if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "$PROJECT_ROOT" check-ignore -q "$RESOLVED" 2>/dev/null; then
        echo "FAIL $CHECK_NAME $RESOLVED exists but is gitignored — commit the lockfile so CI resolves the same versions"
        exit 1
    fi
    if ! git -C "$PROJECT_ROOT" ls-files --error-unmatch "$RESOLVED" >/dev/null 2>&1; then
        echo "FAIL $CHECK_NAME $RESOLVED exists but is not tracked by git — commit it"
        exit 1
    fi
fi

echo "PASS $CHECK_NAME $RESOLVED committed"
exit 0
