#!/bin/bash
# Standards compliance linter
# Reads .standards.yml, runs matching check modules, reports results.
#
# Usage:
#   ./scripts/lint-standards.sh [--format text|json|sarif] [--since <ref> | --changed]
#                               [--timeout <seconds>] [--fail-on-timeout] [project-root]
#
# Options:
#   --format text      Human-readable color output (default)
#   --format json      Machine-readable JSON object (timestamp, projectRoot, summary, results)
#   --format sarif     SARIF 2.1.0 format for GitHub Code Scanning
#   --since <ref>      PR mode: file-scanning checks only look at files changed
#                      since the merge-base with <ref> (plus untracked files).
#                      Config/history checks still run on the whole project.
#   --changed          Same as --since with the base auto-detected (origin/HEAD,
#                      origin/main, origin/master, main, master). Falls back to a
#                      full scan, with a note on stderr, when none exists.
#   --timeout <secs>   Wall-clock guard per check module (default 60; 0 disables;
#                      env LINT_CHECK_TIMEOUT). A check that overruns is killed
#                      (SIGTERM, then SIGKILL after a short grace period) so the
#                      run always finishes. The result is WARN, except that
#                      security checks (no-secrets, */banned-functions) always
#                      FAIL: an incomplete security scan must not pass a gate.
#   --fail-on-timeout  Report every timed-out check as FAIL (env
#                      LINT_FAIL_ON_TIMEOUT=1). The standards-review action sets
#                      this so CI never fails open.
#
# Monorepo members (#179):
#   The root .standards.yml may declare `members:` (root-relative sub-roots
#   with their own .standards.yml); without the key, every */.standards.yml
#   and */*/.standards.yml is auto-discovered (see scripts/lib/members.sh).
#   Repo-wide checks (conventional-commits, ci-workflow-hygiene, headless-ci,
#   no-secrets, doc-lint) run once at the root. Project checks
#   (coverage-config, quarantine-policy, test-directory-structure) and the
#   language checks run in every member against that member's own config;
#   they also run at the root unless the root declares no languages and has
#   members (a pure aggregator). Results are aggregated into one report; each
#   JSON/SARIF result carries a "member" field ("." for the root) and --since
#   scopes are re-based onto each member.
#
# Environment:
#   LINT_CHECK_TIMEOUT    Default for --timeout.
#   LINT_FAIL_ON_TIMEOUT  Default for --fail-on-timeout (1/true).
#   LINT_CHECKS_DIR       Alternate check-module directory (tests use this).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKS_DIR="${LINT_CHECKS_DIR:-$SCRIPT_DIR/lint-checks}"

# Defaults
FORMAT="text"
PROJECT_ROOT=""
CHANGED_MODE=false
SINCE_REF=""
CHECK_TIMEOUT="${LINT_CHECK_TIMEOUT:-60}"
FAIL_ON_TIMEOUT=false
case "${LINT_FAIL_ON_TIMEOUT:-}" in 1|true|yes) FAIL_ON_TIMEOUT=true ;; esac

# Checks whose incomplete scan must never be reported as a mere warning.
SECURITY_CHECKS_ERE='^(no-secrets|[a-z]+/banned-functions)$'

usage() {
    echo "Usage: $0 [--format text|json|sarif] [--since <ref> | --changed] [--timeout <seconds>] [--fail-on-timeout] [project-root]" >&2
}

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
        --since)
            SINCE_REF="${2:-}"
            CHANGED_MODE=true
            if [ -z "$SINCE_REF" ]; then
                echo "--since requires a git ref" >&2
                usage
                exit 1
            fi
            shift 2
            ;;
        --since=*)
            SINCE_REF="${1#--since=}"
            CHANGED_MODE=true
            shift
            ;;
        --changed)
            CHANGED_MODE=true
            shift
            ;;
        --timeout)
            CHECK_TIMEOUT="${2:-}"
            shift 2
            ;;
        --timeout=*)
            CHECK_TIMEOUT="${1#--timeout=}"
            shift
            ;;
        --fail-on-timeout)
            FAIL_ON_TIMEOUT=true
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
        *)
            PROJECT_ROOT="$1"
            shift
            ;;
    esac
done

if ! [[ "$CHECK_TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "--timeout must be a non-negative integer (seconds), got: $CHECK_TIMEOUT" >&2
    exit 1
fi
# Force base 10: bash treats a leading zero as octal in arithmetic, so "08"
# would otherwise abort the check loop and yield an empty, passing report.
CHECK_TIMEOUT=$((10#$CHECK_TIMEOUT))

# Resolve project root
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ---------------------------------------------------------------------------
# Changed-files scope (--since / --changed)
#
# Writes the project-relative paths of tracked files changed since the
# merge-base with the base ref (committed, staged and unstaged; deletions
# dropped) to a NUL-delimited temp file and exports LINT_FILE_LIST.
# File-scanning check modules read that list via scripts/lib/lint-files.sh in
# place of `git ls-files`; the library still enumerates untracked files itself,
# so a new, uncommitted file is scanned too.
#
# `--relative` matters when the project root is a subdirectory of a larger
# work tree: without it git prints paths relative to the repository root and
# the modules would look for "<root>/<repo-relative>" and silently miss every
# changed file.
# ---------------------------------------------------------------------------
SCOPE_BASE=""
SCOPE_FILE_COUNT=0
if [ "$CHANGED_MODE" = true ]; then
    if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "lint-standards: --since/--changed needs a git repository; scanning all files" >&2
    else
        SCOPE_BASE="$SINCE_REF"
        if [ -z "$SCOPE_BASE" ]; then
            for candidate in origin/HEAD origin/main origin/master main master; do
                if git -C "$PROJECT_ROOT" rev-parse --verify -q "$candidate" >/dev/null 2>&1; then
                    SCOPE_BASE="$candidate"
                    break
                fi
            done
        fi
        if [ -z "$SCOPE_BASE" ]; then
            echo "lint-standards: --changed: no base ref found (tried origin/HEAD, origin/main, origin/master, main, master); scanning all files" >&2
        elif ! git -C "$PROJECT_ROOT" rev-parse --verify -q "$SCOPE_BASE" >/dev/null 2>&1; then
            echo "lint-standards: --since: unknown ref '$SCOPE_BASE'; scanning all files" >&2
            SCOPE_BASE=""
        else
            merge_base=$(git -C "$PROJECT_ROOT" merge-base "$SCOPE_BASE" HEAD 2>/dev/null || echo "$SCOPE_BASE")
            LINT_FILE_LIST=$(mktemp "${TMPDIR:-/tmp}/lint-scope.XXXXXX")
            # ACMRT: added, copied, modified, renamed, and type changes (a symlink
            # or submodule replaced by a regular file); deletions are dropped.
            git -C "$PROJECT_ROOT" diff -z --relative --name-only --diff-filter=ACMRT "$merge_base" -- 2>/dev/null \
                > "$LINT_FILE_LIST" || true
            export LINT_FILE_LIST
            # shellcheck disable=SC2064
            trap "rm -f '$LINT_FILE_LIST'" EXIT
            SCOPE_FILE_COUNT=$(tr -cd '\0' < "$LINT_FILE_LIST" | wc -c | tr -d ' ')
            SCOPE_FILE_COUNT="${SCOPE_FILE_COUNT:-0}"
        fi
    fi
fi

# Source helpers for YAML parsing
if [ -f "$SCRIPT_DIR/lib/checksums.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/checksums.sh"
fi

# Read .standards.yml config if available
LANGUAGES=""
if declare -f read_standards_config >/dev/null 2>&1; then
    read_standards_config "$PROJECT_ROOT" 2>/dev/null || true
    # Normalize: `languages: []` parses to a lone space, which must read as
    # "no languages" below.
    LANGUAGES=$(printf '%s\n' "${STD_LANGUAGES:-}" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
fi

# ---------------------------------------------------------------------------
# Members: the root (".") plus every declared or discovered sub-root.
# ---------------------------------------------------------------------------
if [ ! -f "$SCRIPT_DIR/lib/members.sh" ]; then
    echo "lint-standards: required library not found: $SCRIPT_DIR/lib/members.sh" >&2
    exit 1
fi
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/members.sh"
MEMBERS=(".")
while IFS= read -r m; do
    [ -z "$m" ] && continue
    MEMBERS+=("$m")
done <<EOF
$(resolve_members "$PROJECT_ROOT")
EOF
MEMBER_COUNT=${#MEMBERS[@]}

# Common checks that describe the repository as a whole (history, CI
# definitions, every tracked file) run once at the root; all other common
# checks describe one project and run per member. Classified by module file
# name under lint-checks/common/.
REPO_SCOPED_CHECKS_ERE='^(conventional-commits|ci-workflow-hygiene|headless-ci|no-secrets|doc-lint)$'

# A root that has members but declares no languages is a pure aggregator: its
# project-level checks (test directory, coverage config …) would only report
# the members' layout as missing.
ROOT_IS_AGGREGATOR=false
if [ "$MEMBER_COUNT" -gt 1 ] && [ -z "$LANGUAGES" ]; then
    ROOT_IS_AGGREGATOR=true
fi

# ---------------------------------------------------------------------------
# Result collection
# ---------------------------------------------------------------------------

RESULTS=()
RESULT_MEMBERS=()
PASS=0
WARN=0
FAIL=0

# record_result <member> <status line>
record_result() {
    local member="$1" output="$2"
    [ -z "$output" ] && return 0
    RESULTS+=("$output")
    RESULT_MEMBERS+=("$member")
    case "$output" in
        PASS*) PASS=$((PASS + 1)) ;;
        WARN*) WARN=$((WARN + 1)) ;;
        FAIL*) FAIL=$((FAIL + 1)) ;;
    esac
}

# descendants <pid>: the pid and all of its descendants, deepest first, as a
# space-separated list. Snapshotted before any signal is sent, because once a
# parent dies its children are re-parented and pgrep -P can no longer find
# them. pgrep exists on macOS and Linux; without it only the pid is returned.
descendants() {
    local pid="$1" child
    if command -v pgrep >/dev/null 2>&1; then
        for child in $(pgrep -P "$pid" 2>/dev/null || true); do
            descendants "$child"
        done
    fi
    printf '%s ' "$pid"
}

# kill_tree <pid>: terminate a process and its descendants (a check module's
# grep/find children would otherwise outlive it). SIGTERM first; a module that
# traps or ignores it is escalated to SIGKILL after a 2 s grace period, so the
# wall-clock guard is a hard bound and `wait` cannot block on a survivor.
kill_tree() {
    local pid="$1" victims grace=0
    victims=$(descendants "$pid")
    # shellcheck disable=SC2086
    kill -TERM $victims 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null && [ "$grace" -lt 40 ]; do
        sleep 0.05
        grace=$((grace + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        # Re-snapshot: a child spawned after the first pass must not survive.
        victims="$(descendants "$pid") $victims"
        # shellcheck disable=SC2086
        kill -KILL $victims 2>/dev/null || true
    fi
}

# check_label <script>: best-effort check name for a module that produced no
# status line (e.g. it timed out) — "<group>/<name>", or "<name>" for common/.
check_label() {
    local script="$1" base group
    base=$(basename "$script" .sh)
    group=$(basename "$(dirname "$script")")
    if [ "$group" = "common" ]; then
        echo "$base"
    else
        echo "$group/$base"
    fi
}

# run_check <script> [root] [member]
# Runs one module against <root> (default: the project root) and records the
# result under <member> (default "."). LINT_FILE_LIST, when set, has already
# been re-based onto <root> by the member loop.
run_check() {
    local check_script="$1" check_root="${2:-$PROJECT_ROOT}" member="${3:-.}"
    if [ ! -f "$check_script" ] || [ ! -x "$check_script" ]; then
        return
    fi

    local output
    # Capture output; allow non-zero exit (checks use exit codes for severity)
    if [ "$CHECK_TIMEOUT" -eq 0 ]; then
        output=$("$check_script" "$check_root" 2>/dev/null) || true
    else
        # Wall-clock guard: run the module in the background and poll (bash 3.2
        # has no `timeout`). A module that overruns is killed with its children
        # (TERM, then KILL) so one slow check can never hang the run. The
        # result is WARN, or FAIL for security checks and under
        # --fail-on-timeout: an incomplete scan must not pass a gate.
        local out_file pid ticks max_ticks timed_out=false label status
        out_file=$(mktemp "${TMPDIR:-/tmp}/lint-check.XXXXXX")
        "$check_script" "$check_root" >"$out_file" 2>/dev/null &
        pid=$!
        ticks=0
        max_ticks=$((CHECK_TIMEOUT * 20))
        while kill -0 "$pid" 2>/dev/null; do
            if [ "$ticks" -ge "$max_ticks" ]; then
                kill_tree "$pid"
                timed_out=true
                break
            fi
            sleep 0.05
            ticks=$((ticks + 1))
        done
        wait "$pid" 2>/dev/null || true
        if [ "$timed_out" = true ]; then
            label=$(check_label "$check_script")
            status="WARN"
            if [ "$FAIL_ON_TIMEOUT" = true ] || [[ "$label" =~ $SECURITY_CHECKS_ERE ]]; then
                status="FAIL"
            fi
            output="$status $label Check timed out after ${CHECK_TIMEOUT}s — scan incomplete (raise --timeout, or skip paths via lint.exclude in .standards.yml)"
        else
            output=$(cat "$out_file")
        fi
        rm -f "$out_file"
    fi

    record_result "$member" "$output"
}

# member_file_list <member> <src> <dest>
# Writes the entries of the NUL-delimited root scope list <src> that live under
# <member>/ to <dest>, re-based onto the member root, so a member's
# file-scanning checks see "src/x.py" rather than "server/src/x.py" (which they
# would look up under the member root and silently miss).
member_file_list() {
    local member="$1" src="$2" dest="$3" entry
    : > "$dest"
    while IFS= read -r -d '' entry || [ -n "$entry" ]; do
        case "$entry" in
            "$member"/*) printf '%s\0' "${entry#"$member/"}" >> "$dest" ;;
        esac
        entry=""
    done < "$src"
}

# run_member <member>
# Runs the checks that apply to one member against its own root and config.
run_member() {
    local member="$1" member_dir member_langs="" check base saved_list=""
    member_dir=$(member_root "$PROJECT_ROOT" "$member")

    if [ "$member" = "." ]; then
        member_langs="$LANGUAGES"
    else
        [ -d "$member_dir" ] || return 0
        if [ -f "$member_dir/.standards.yml" ] && declare -f read_standards_config >/dev/null 2>&1; then
            read_standards_config "$member_dir" 2>/dev/null || true
            member_langs="${STD_LANGUAGES:-}"
        fi
        # Re-base the --since scope onto this member.
        if [ -n "${LINT_FILE_LIST:-}" ] && [ -r "$LINT_FILE_LIST" ]; then
            saved_list="$LINT_FILE_LIST"
            LINT_FILE_LIST=$(mktemp "${TMPDIR:-/tmp}/lint-scope-member.XXXXXX")
            member_file_list "$member" "$saved_list" "$LINT_FILE_LIST"
            export LINT_FILE_LIST
        fi
    fi

    if [ -d "$CHECKS_DIR/common" ]; then
        for check in "$CHECKS_DIR/common/"*.sh; do
            base=$(basename "$check" .sh)
            if [[ "$base" =~ $REPO_SCOPED_CHECKS_ERE ]]; then
                # Repo-wide: once, at the root.
                [ "$member" = "." ] || continue
            elif [ "$member" = "." ] && [ "$ROOT_IS_AGGREGATOR" = true ]; then
                # Project-level check on a root that is only an aggregator.
                continue
            fi
            run_check "$check" "$member_dir" "$member"
        done
    fi

    local lang
    for lang in $member_langs; do
        if [ -d "$CHECKS_DIR/$lang" ]; then
            for check in "$CHECKS_DIR/$lang/"*.sh; do
                run_check "$check" "$member_dir" "$member"
            done
        fi
    done

    if [ -n "$saved_list" ]; then
        rm -f "$LINT_FILE_LIST"
        LINT_FILE_LIST="$saved_list"
        export LINT_FILE_LIST
    fi
}

# A declared member that is missing, or has no .standards.yml, is a finding
# in its own right (recorded under the root, before any module runs, so it
# leads the root group), not a silent skip.
for member in "${MEMBERS[@]}"; do
    [ "$member" = "." ] && continue
    if ! problem=$(member_problem "$PROJECT_ROOT" "$member"); then
        record_result "." "WARN members $problem"
    fi
done

for member in "${MEMBERS[@]}"; do
    run_member "$member"
done

TOTAL=$((PASS + WARN + FAIL))

# members_json: the members array as a one-line JSON list.
members_json() {
    local first=true m out="["
    for m in "${MEMBERS[@]}"; do
        if [ "$first" = true ]; then first=false; else out="$out, "; fi
        out="$out\"$(printf '%s' "$m" | sed 's/\\/\\\\/g; s/"/\\"/g')\""
    done
    printf '%s]' "$out"
}

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
    printf "%s\n" "${BOLD}🔎 Standards Compliance Check${RESET}"
    printf "%s\n\n" "$separator"

    if [ -n "$SCOPE_BASE" ]; then
        printf "  %s\n\n" "${DIM}Scope: $SCOPE_FILE_COUNT changed file(s) since $SCOPE_BASE (file-scanning checks only)${RESET}"
    fi

    if [ "$MEMBER_COUNT" -gt 1 ]; then
        local m labels=""
        for m in "${MEMBERS[@]}"; do
            labels="${labels:+$labels, }$(member_label "$m")"
        done
        printf "  %s\n\n" "${DIM}Members: $labels${RESET}"
    fi

    if [ ${#RESULTS[@]} -eq 0 ]; then
        printf "  %s\n" "${DIM}No checks ran. Is .standards.yml configured?${RESET}"
    fi

    local i=0 current_member=""
    for result in "${RESULTS[@]}"; do
        local status check_name message icon color member
        member="${RESULT_MEMBERS[$i]}"
        i=$((i + 1))
        if [ "$MEMBER_COUNT" -gt 1 ] && [ "$member" != "$current_member" ]; then
            [ -n "$current_member" ] && printf "\n"
            printf "  %s\n" "${BOLD}▸ $(member_label "$member")${RESET}"
            current_member="$member"
        fi
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

        # shellcheck disable=SC2059
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

    # shellcheck disable=SC2059
    printf "  ${result_color}Results: %d pass, %d warn, %d fail${RESET}\n" \
        "$PASS" "$WARN" "$FAIL"
    printf "\n"
    printf "  %s\n" "${DIM}Run with --format json for machine-readable output${RESET}"
    printf "  %s\n" "${DIM}Run with --format sarif for GitHub Code Scanning integration${RESET}"
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
    printf '  "members": %s,\n' "$(members_json)"
    printf '  "summary": {\n'
    printf '    "pass": %d,\n' "$PASS"
    printf '    "warn": %d,\n' "$WARN"
    printf '    "fail": %d,\n' "$FAIL"
    printf '    "total": %d\n' "$TOTAL"
    printf '  },\n'
    printf '  "results": [\n'

    local first=true i=0
    if [ ${#RESULTS[@]} -gt 0 ]; then
    for result in "${RESULTS[@]}"; do
        local status check_name message member
        member="${RESULT_MEMBERS[$i]}"
        i=$((i + 1))
        status=$(echo "$result" | awk '{print $1}')
        check_name=$(echo "$result" | awk '{print $2}')
        message=$(echo "$result" | cut -d' ' -f3-)

        # Escape message for JSON
        message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
        member=$(printf '%s' "$member" | sed 's/\\/\\\\/g; s/"/\\"/g')

        if [ "$first" = true ]; then
            first=false
        else
            printf ',\n'
        fi

        printf '    {\n'
        printf '      "status": "%s",\n' "$status"
        printf '      "check": "%s",\n' "$check_name"
        printf '      "member": "%s",\n' "$member"
        printf '      "message": "%s"\n' "$message"
        printf '    }'
    done
    fi

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
    # shellcheck disable=SC2016
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
    if [ ${#RESULTS[@]} -gt 0 ]; then
    for result in "${RESULTS[@]}"; do
        local check_name
        check_name=$(echo "$result" | awk '{print $2}')

        # Skip duplicates
        local already_seen=false
        if [ ${#seen_rules[@]} -gt 0 ]; then
        for seen in "${seen_rules[@]}"; do
            [ "$seen" = "$check_name" ] && already_seen=true && break
        done
        fi
        $already_seen && continue
        seen_rules+=("$check_name")

        if [ "$rules_first" = true ]; then
            rules_first=false
        else
            printf ',\n'
        fi

        printf '            {\n'
        printf '              "id": "%s",\n' "$check_name"
        local rule_name
        rule_name=$(printf '%s' "$check_name" | tr '/' '-' | awk -F'-' '{
            out = ""
            for (i = 1; i <= NF; i++) {
                if (i == 1) out = $i
                else if (length($i) > 0) out = out toupper(substr($i, 1, 1)) substr($i, 2)
            }
            print out
        }')
        printf '              "name": "%s",\n' "$rule_name"
        printf '              "shortDescription": { "text": "Standards compliance check: %s" }\n' "$check_name"
        printf '            }'
    done
    fi

    printf '\n          ]\n'
    printf '        }\n'
    printf '      },\n'
    printf '      "results": [\n'

    local results_first=true i=0
    if [ ${#RESULTS[@]} -gt 0 ]; then
    for result in "${RESULTS[@]}"; do
        local status check_name message level member
        member="${RESULT_MEMBERS[$i]}"
        i=$((i + 1))
        status=$(echo "$result" | awk '{print $1}')
        check_name=$(echo "$result" | awk '{print $2}')
        message=$(echo "$result" | cut -d' ' -f3-)
        level=$(sarif_level "$status")

        # Skip PASS results in SARIF (only warnings/errors are actionable)
        [ "$status" = "PASS" ] && continue

        message=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g')
        member=$(printf '%s' "$member" | sed 's/\\/\\\\/g; s/"/\\"/g')

        if [ "$results_first" = true ]; then
            results_first=false
        else
            printf ',\n'
        fi

        # The member directory is the artifact location, so Code Scanning
        # attributes a finding to the sub-root it was produced in.
        printf '        {\n'
        printf '          "ruleId": "%s",\n' "$check_name"
        printf '          "level": "%s",\n' "$level"
        printf '          "message": { "text": "%s" },\n' "$message"
        printf '          "locations": [\n'
        printf '            {\n'
        printf '              "physicalLocation": {\n'
        printf '                "artifactLocation": {\n'
        printf '                  "uri": "%s",\n' "$member"
        printf '                  "uriBaseId": "%%SRCROOT%%"\n'
        printf '                }\n'
        printf '              }\n'
        printf '            }\n'
        printf '          ],\n'
        printf '          "properties": { "member": "%s" }\n' "$member"
        printf '        }'
    done
    fi

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
