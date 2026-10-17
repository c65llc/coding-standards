#!/bin/bash
# scripts/check-commit-message.sh — validate one commit message (or PR title)
# against Conventional Commits and the optional commits.scopes allow-list.
#
# Usage:
#   check-commit-message.sh [--project-root <dir>] [--quiet] [--no-exempt] "<message>"
#   check-commit-message.sh [--project-root <dir>] [--quiet] --file <path>
#
# The --file form is what commit-msg hooks use (git passes the message file
# path as $1). The positional form is what the standards-review action uses
# for the PR title — on squash-merge, the PR title *is* the mainline commit.
#
# Exemptions: fixup!/squash!/amend! prefixes, merge commits and `git revert`
# subjects pass because git rewrites or generates them before they reach
# mainline. --no-exempt disables that — a PR title is never rewritten, so a
# squash-merged "Merge branch x" or "fixup! wip" title would land verbatim.
# Use `revert: ...` / `revert(scope): ...` for revert PR titles.
#
# Exit codes: 0 valid (or exempt), 1 invalid, 2 usage error.
#
# Scope allow-list: when <project-root>/.standards.yml has
#   commits:
#     scopes: [api, domain]
# a scoped message must use one of the listed scopes. Unscoped messages pass.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/conventional-commits.sh
source "$SCRIPT_DIR/lib/conventional-commits.sh"

PROJECT_ROOT=""
MSG_FILE=""
MESSAGE=""
QUIET=false
EXEMPT=true

usage() {
    echo "Usage: $0 [--project-root <dir>] [--quiet] [--no-exempt] (\"<message>\" | --file <path>)" >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)
            [ $# -ge 2 ] || usage
            PROJECT_ROOT="$2"
            shift 2
            ;;
        --project-root=*)
            PROJECT_ROOT="${1#--project-root=}"
            shift
            ;;
        --file|-f)
            [ $# -ge 2 ] || usage
            MSG_FILE="$2"
            shift 2
            ;;
        --file=*)
            MSG_FILE="${1#--file=}"
            shift
            ;;
        --quiet|-q)
            QUIET=true
            shift
            ;;
        --no-exempt)
            EXEMPT=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        --)
            shift
            [ $# -ge 1 ] && MESSAGE="$1"
            break
            ;;
        -*)
            usage
            ;;
        *)
            MESSAGE="$1"
            shift
            ;;
    esac
done

if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

if [ -n "$MSG_FILE" ]; then
    if [ ! -f "$MSG_FILE" ]; then
        echo "error: commit message file not found: $MSG_FILE" >&2
        exit 2
    fi
    # The subject is the first non-empty line git will keep. Git drops comment
    # lines (core.commentChar, default '#') only under the strip/scissors
    # cleanup modes; with commit.cleanup=verbatim or whitespace they stay in
    # the message, so the first non-empty line is the subject as written.
    comment_char=$(git -C "$PROJECT_ROOT" config --get core.commentChar 2>/dev/null)
    case "$comment_char" in
        ''|auto) comment_char='#' ;;
    esac
    cleanup=$(git -C "$PROJECT_ROOT" config --get commit.cleanup 2>/dev/null)
    case "$cleanup" in
        verbatim|whitespace)
            subject=$(grep -m1 . "$MSG_FILE" || true)
            ;;
        *)
            subject=$(awk -v c="$comment_char" 'substr($0, 1, 1) != c' "$MSG_FILE" | grep -m1 . || true)
            ;;
    esac
elif [ -n "$MESSAGE" ]; then
    subject=$(printf '%s\n' "$MESSAGE" | grep -m1 . || true)
else
    usage
fi

# Trim surrounding whitespace
subject=$(printf '%s' "$subject" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

if [ -z "$subject" ]; then
    echo "error: empty commit message" >&2
    exit 1
fi

if [ "$EXEMPT" = true ] && cc_is_exempt "$subject"; then
    exit 0
fi

fail() {
    if [ "$QUIET" = false ]; then
        printf '%s\n' "$@" >&2
    fi
    exit 1
}

if ! cc_is_conventional "$subject"; then
    fail "error: not a Conventional Commit subject:" \
         "    $subject" \
         "" \
         "  expected: <type>(<scope>): <subject>     scope optional, '!' marks a breaking change" \
         "  types:    feat fix refactor test docs chore perf ci   (also accepted: build style revert)" \
         "  example:  feat(api): add user endpoint" \
         "" \
         "  Squash-merge uses the PR title as the mainline commit subject, so PR titles" \
         "  must follow the same format. See proc-02_git_version_control_standards.md § 2."
fi

scopes=$(cc_config_scopes "$PROJECT_ROOT")
if [ -n "$scopes" ]; then
    scope=$(cc_scope "$subject")
    if ! cc_scope_allowed "$scope" "$scopes"; then
        fail "error: scope '$scope' is not in the commits.scopes allow-list (.standards.yml):" \
             "    $subject" \
             "" \
             "  allowed scopes: $scopes" \
             "  Add the scope to commits.scopes in .standards.yml or use one of the listed scopes."
    fi
fi

exit 0
