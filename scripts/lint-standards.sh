#!/bin/bash
# Standards compliance linter
# Reads .standards.yml, runs matching check modules, reports results.
#
# Usage:
#   ./scripts/lint-standards.sh [--format text|json|sarif] [project-root]
#
# Options:
#   --format text   Human-readable color output (default)
#   --format json   Machine-readable JSON array
#   --format sarif  SARIF 2.1.0 format for GitHub Code Scanning

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="$SCRIPT_DIR/lint-checks"

# Defaults
FORMAT="text"
PROJECT_ROOT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --format)
            FORMAT="${2:-text}"
            shift 2
            ;;
        --format=*)
            FORMAT="${1#--format=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--format text|json|sarif] [project-root]" >&2
            exit 1
            ;;
        *)
            PROJECT_ROOT="$1"
            shift
            ;;
    esac
done

# Resolve project root
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Source helpers for YAML parsing
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck source=scripts/lib/checksums.sh
    source "$SCRIPT_DIR/lib/checksums.sh"
fi

# Read .standards.yml config if available
LANGUAGES=""
if declare -f read_standards_config >/dev/null 2>&1; then
    read_standards_config "$PROJECT_ROOT" 2>/dev/null || true
    LANGUAGES="${STD_LANGUAGES:-}"
fi

# ---------------------------------------------------------------------------
# Result collection
# ---------------------------------------------------------------------------

RESULTS=()
PASS=0
WARN=0
FAIL=0

run_check() {
    local check_script="$1"
    if [ ! -f "$check_script" ] || [ ! -x "$check_script" ]; then
        return
    fi

    local output
    # Capture output; allow non-zero exit (checks use exit codes for severity)
    output=$("$check_script" "$PROJECT_ROOT" 2>/dev/null) || true

    if [ -n "$output" ]; then
        RESULTS+=("$output")
        case "$output" in
            PASS*) PASS=$((PASS + 1)) ;;
            WARN*) WARN=$((WARN + 1)) ;;
            FAIL*) FAIL=$((FAIL + 1)) ;;
        esac
    fi
}

# Run common checks
if [ -d "$CHECKS_DIR/common" ]; then
    for check in "$CHECKS_DIR/common/"*.sh; do
        run_check "$check"
    done
fi

# Run language-specific checks
for lang in $LANGUAGES; do
    if [ -d "$CHECKS_DIR/$lang" ]; then
        for check in "$CHECKS_DIR/$lang/"*.sh; do
            run_check "$check"
        done
    fi
done

TOTAL=$((PASS + WARN + FAIL))

# ---------------------------------------------------------------------------
# Output: text format
# ---------------------------------------------------------------------------

output_text() {
    # ANSI colors (disabled if not a terminal or NO_COLOR is set)
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        GREEN='\033[0;32m'
        YELLOW='\033[0;33m'
        RED='\033[0;31m'
        BOLD='\033[1m'
        RESET='\033[0m'
        DIM='\033[2m'
    else
        GREEN=''
        YELLOW=''
        RED=''
        BOLD=''
        RESET=''
        DIM=''
    fi

    local separator
    separator="═══════════════════════════════════════"

    printf "\n"
    printf "${BOLD}🔎 Standards Compliance Check${RESET}\n"
    printf "%s\n\n" "$separator"

    if [ ${#RESULTS[@]} -eq 0 ]; then
        printf "  ${DIM}No checks ran. Is .standards.yml configured?${RESET}\n"
    fi

    for result in "${RESULTS[@]}"; do
        local status check_name message icon color
        status=$(echo "$result" | awk '{print $1}')
        check_name=$(echo "$result" | awk '{print $2}')
        message=$(echo "$result" | cut -d' ' -f3-)

        case "$status" in
            PASS)
                icon="✅"
                color="$GREEN"
                ;;
            WARN)
                icon="⚠️ "
                color="$YELLOW"
                ;;
            FAIL)
                icon="❌"
                color="$RED"
                ;;
            *)
                icon="  "
                color=""
                ;;
        esac

        printf "  %s ${color}%-6s${RESET}  %-28s %s\n" \
            "$icon" "$status" "$check_name" "$message"
    done

    printf "\n%s\n" "$separator"

    local result_color="$GREEN"
    if [ "$FAIL" -gt 0 ]; then
        result_color="$RED"
    elif [ "$WARN" -gt 0 ]; then
        result_color="$YELLOW"
    fi

    printf "  ${result_color}Results: %d pass, %d warn, %d fail${RESET}\n" \
        "$PASS" "$WARN" "$FAIL"
    printf "\n"
    printf "  ${DIM}Run with --format json for machine-readable output${RESET}\n"
    printf "  ${DIM}Run with --format sarif for GitHub Code Scanning integration${RESET}\n"
    printf "\n"
}

# ---------------------------------------------------------------------------
# Output: JSON format
# ---------------------------------------------------------------------------

output_json() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    printf '{\n'
    printf '  "timestamp": "%s",\n' "$timestamp"
    printf '  "projectRoot": "%s",\n' "$PROJECT_ROOT"
    printf '  "summary": {\n'
    printf '    "pass": %d,\n' "$PASS"
    printf '    "warn": %d,\n' "$WARN"
    printf '    "fail": %d,\n' "$FAIL"
    printf '    "total": %d\n' "$TOTAL"
    printf '  },\n'
    printf '  "results": [\n'

    local first=true
    for result in "${RESULTS[@]}"; do
        local status check_name message
        status=$(echo "$result" | awk '{print $1}')
        check_name=$(echo "$result" | awk '{print $2}')
        message=$(echo "$result" | cut -d' ' -f3-)

        # Escape message for JSON
        message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')

        if [ "$first" = true ]; then
            first=false
        else
            printf ',\n'
        fi

        printf '    {\n'
        printf '      "status": "%s",\n' "$status"
        printf '      "check": "%s",\n' "$check_name"
        printf '      "message": "%s"\n' "$message"
        printf '    }'
    done

    printf '\n  ]\n'
    printf '}\n'
}

# ---------------------------------------------------------------------------
# Output: SARIF 2.1.0 format
# ---------------------------------------------------------------------------

output_sarif() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

    # Map our severity levels to SARIF levels
    sarif_level() {
        case "$1" in
            PASS) echo "none" ;;
            WARN) echo "warning" ;;
            FAIL) echo "error" ;;
            *)    echo "note" ;;
        esac
    }

    printf '{\n'
    printf '  "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",\n'
    printf '  "version": "2.1.0",\n'
    printf '  "runs": [\n'
    printf '    {\n'
    printf '      "tool": {\n'
    printf '        "driver": {\n'
    printf '          "name": "standards-linter",\n'
    printf '          "version": "1.0.0",\n'
    printf '          "informationUri": "https://coding-standards.c65llc.com",\n'
    printf '          "rules": [\n'

    # Emit rules array from unique check names
    local rules_first=true
    local seen_rules=()
    for result in "${RESULTS[@]}"; do
        local check_name
        check_name=$(echo "$result" | awk '{print $2}')

        # Skip duplicates
        local already_seen=false
        for seen in "${seen_rules[@]}"; do
            [ "$seen" = "$check_name" ] && already_seen=true && break
        done
        $already_seen && continue
        seen_rules+=("$check_name")

        if [ "$rules_first" = true ]; then
            rules_first=false
        else
            printf ',\n'
        fi

        printf '            {\n'
        printf '              "id": "%s",\n' "$check_name"
        printf '              "name": "%s",\n' "$(echo "$check_name" | sed 's|/|-|g; s|-\([a-z]\)|\U\1|g')"
        printf '              "shortDescription": { "text": "Standards compliance check: %s" }\n' "$check_name"
        printf '            }'
    done

    printf '\n          ]\n'
    printf '        }\n'
    printf '      },\n'
    printf '      "results": [\n'

    local results_first=true
    for result in "${RESULTS[@]}"; do
        local status check_name message level
        status=$(echo "$result" | awk '{print $1}')
        check_name=$(echo "$result" | awk '{print $2}')
        message=$(echo "$result" | cut -d' ' -f3-)
        level=$(sarif_level "$status")

        # Skip PASS results in SARIF (only warnings/errors are actionable)
        [ "$status" = "PASS" ] && continue

        message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')

        if [ "$results_first" = true ]; then
            results_first=false
        else
            printf ',\n'
        fi

        printf '        {\n'
        printf '          "ruleId": "%s",\n' "$check_name"
        printf '          "level": "%s",\n' "$level"
        printf '          "message": { "text": "%s" },\n' "$message"
        printf '          "locations": [\n'
        printf '            {\n'
        printf '              "physicalLocation": {\n'
        printf '                "artifactLocation": {\n'
        printf '                  "uri": ".",\n'
        printf '                  "uriBaseId": "%%SRCROOT%%"\n'
        printf '                }\n'
        printf '              }\n'
        printf '            }\n'
        printf '          ]\n'
        printf '        }'
    done

    printf '\n      ],\n'
    printf '      "invocations": [\n'
    printf '        {\n'
    printf '          "executionSuccessful": true,\n'
    printf '          "startTimeUtc": "%s"\n' "$timestamp"
    printf '        }\n'
    printf '      ]\n'
    printf '    }\n'
    printf '  ]\n'
    printf '}\n'
}

# ---------------------------------------------------------------------------
# Dispatch output format
# ---------------------------------------------------------------------------

case "$FORMAT" in
    text)
        output_text
        ;;
    json)
        output_json
        ;;
    sarif)
        output_sarif
        ;;
    *)
        echo "Unknown format: $FORMAT. Use text, json, or sarif." >&2
        exit 1
        ;;
esac

# Exit with non-zero if any FAILs
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
