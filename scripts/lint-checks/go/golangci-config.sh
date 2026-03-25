#!/bin/bash
# Check: golangci-lint configuration present
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="go/golangci-config"

# Check for golangci-lint config files
GOLANGCI_CONFIGS=(
    ".golangci.yml"
    ".golangci.yaml"
    ".golangci.toml"
    ".golangci.json"
)

for cfg in "${GOLANGCI_CONFIGS[@]}"; do
    if [ -f "$PROJECT_ROOT/$cfg" ]; then
        echo "PASS $CHECK_NAME golangci-lint configured ($cfg)"
        exit 0
    fi
done

echo "FAIL $CHECK_NAME No golangci-lint configuration found (checked .golangci.yml, .golangci.yaml, .golangci.toml, .golangci.json)"
exit 1
