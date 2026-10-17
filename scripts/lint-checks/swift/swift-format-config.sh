#!/bin/bash
# Check: swift-format configuration present
# (lang-04 §2: swift-format is the default formatting/lint gate; SwiftLint optional)
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="swift/swift-format-config"

# swift-format reads `.swift-format` (JSON). Some projects keep it as
# .swift-format.json; accept both.
for cfg in .swift-format .swift-format.json; do
    if [ -f "$PROJECT_ROOT/$cfg" ]; then
        if grep -qE '"version"' "$PROJECT_ROOT/$cfg" 2>/dev/null; then
            echo "PASS $CHECK_NAME swift-format configured ($cfg)"
            exit 0
        fi
        echo "WARN $CHECK_NAME $cfg present but has no \"version\" key — is it a valid swift-format configuration?"
        exit 2
    fi
done

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
