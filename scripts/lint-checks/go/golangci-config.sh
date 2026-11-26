#!/bin/bash
# Check: golangci-lint configuration present and in the v2 format
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="go/golangci-config"

# The filenames golangci-lint reads, in the order it picks one when several
# exist (verified with v2.15.0 `golangci-lint config path`).
GOLANGCI_CONFIGS=(
    ".golangci.json"
    ".golangci.toml"
    ".golangci.yaml"
    ".golangci.yml"
)

# declares_v2 <file> — true when the config's top-level version is the string
# "2". golangci-lint v2 refuses to load a config without it, and its schema
# rejects an unquoted YAML/TOML 2.
declares_v2() {
    local q="[\"']" v2="(\"2\"|'2')"
    case "$1" in
        *.json)
            tr -d '\r\n' < "$1" | grep -qE '"version"[[:space:]]*:[[:space:]]*"2"'
            ;;
        *.toml)
            # Top level only: stop at the first [table] header.
            tr -d '\r' < "$1" | sed -n '/^[[:space:]]*\[/q;p' \
                | grep -qE "^[[:space:]]*${q}?version${q}?[[:space:]]*=[[:space:]]*${v2}[[:space:]]*(#.*)?$"
            ;;
        *)
            # Top level only: an unindented key.
            tr -d '\r' < "$1" \
                | grep -qE "^${q}?version${q}?[[:space:]]*:[[:space:]]+${v2}[[:space:]]*(#.*)?$"
            ;;
    esac
}

for cfg in "${GOLANGCI_CONFIGS[@]}"; do
    [ -f "$PROJECT_ROOT/$cfg" ] || continue
    if declares_v2 "$PROJECT_ROOT/$cfg"; then
        echo "PASS $CHECK_NAME golangci-lint configured ($cfg, v2 format)"
        exit 0
    fi
    echo "WARN $CHECK_NAME $cfg is not a golangci-lint v2 config (no top-level version \"2\") — run 'golangci-lint migrate' (see lang-12 §2)"
    exit 2
done

for cfg in .golangci-lint.yml .golangci-lint.yaml; do
    if [ -f "$PROJECT_ROOT/$cfg" ]; then
        echo "FAIL $CHECK_NAME golangci-lint does not read $cfg — rename it to .golangci.yml and use the v2 format (see lang-12 §2)"
        exit 1
    fi
done

echo "FAIL $CHECK_NAME No golangci-lint configuration found (checked .golangci.yml, .golangci.yaml, .golangci.toml, .golangci.json)"
exit 1
