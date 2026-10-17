#!/bin/bash
# Check: swift-format configuration present
# (lang-04 §2: swift-format is the default formatting/lint gate; SwiftLint optional)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="swift/swift-format-config"

# swift-format auto-discovers exactly one file name: `.swift-format` (JSON).
if [ -f "$PROJECT_ROOT/.swift-format" ]; then
    if grep -qE '"version"' "$PROJECT_ROOT/.swift-format" 2>/dev/null; then
        echo "PASS $CHECK_NAME swift-format configured (.swift-format)"
        exit 0
    fi
    echo "WARN $CHECK_NAME .swift-format present but has no \"version\" key — is it a valid swift-format configuration?"
    exit 2
fi

# A `.swift-format.json` is silently ignored by `swift format lint` unless every
# invocation passes `--configuration`; without that the defaults apply.
if [ -f "$PROJECT_ROOT/.swift-format.json" ]; then
    if grep -rqE -- '--configuration[[:space:]=]+[^[:space:]]*\.swift-format\.json' \
        "$PROJECT_ROOT/.github/workflows" "$PROJECT_ROOT/Makefile" "$PROJECT_ROOT/justfile" "$PROJECT_ROOT/Justfile" 2>/dev/null; then
        echo "PASS $CHECK_NAME swift-format configured (.swift-format.json, passed via --configuration)"
        exit 0
    fi
    echo "WARN $CHECK_NAME .swift-format.json is not auto-discovered by swift-format — rename it to .swift-format, or pass '--configuration .swift-format.json' in CI"
    exit 2
fi

# Nested packages (monorepo) — accept a config one level down.
nested=$(find "$PROJECT_ROOT" -maxdepth 2 -name ".swift-format" -not -path "*/.git/*" -not -path "*/.build/*" 2>/dev/null | head -1)
if [ -n "$nested" ]; then
    echo "PASS $CHECK_NAME swift-format configured (${nested#"$PROJECT_ROOT"/})"
    exit 0
fi

if [ -f "$PROJECT_ROOT/.swiftlint.yml" ] || [ -f "$PROJECT_ROOT/.swiftformat" ]; then
    found=".swiftlint.yml"
    [ -f "$PROJECT_ROOT/.swiftformat" ] && found=".swiftformat"
    echo "WARN $CHECK_NAME Only $found found — swift-format (bundled with the Swift 6 toolchain) is the default gate; add .swift-format and run 'swift format lint --strict --recursive Sources Tests'"
    exit 2
fi

echo "FAIL $CHECK_NAME No swift-format configuration found (.swift-format) — add one and run 'swift format lint --strict' in CI"
exit 1
