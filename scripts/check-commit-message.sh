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
    # The subject is the first non-empty line git will keep. Which lines git
    # drops depends on commit.cleanup — and, for the default, on whether an
    # editor ran: git exports GIT_EDITOR=: to commit hooks when it will not.
    #   strip                 → comment lines (core.commentString, else
    #                           core.commentChar, else '#') are removed. With
    #                           "auto" git picks a character absent from the
    #                           user's message, which cannot be reconstructed
    #                           from the final file, so nothing is stripped and
    #                           a leading comment-looking line is judged as the
    #                           subject (never skipped in favour of a later,
    #                           possibly decoy, line).
    #   scissors              → everything from the scissors line down is
    #                           removed; comment lines above it are kept
    #   verbatim | whitespace → comment lines are kept
    #   unset ("default")     → strip when an editor ran, whitespace (keep) for
    #                           -m / -F messages (GIT_EDITOR=:)
    cleanup=$(git -C "$PROJECT_ROOT" config --get commit.cleanup 2>/dev/null)
    if [ -z "$cleanup" ] || [ "$cleanup" = default ]; then
        if [ "${GIT_EDITOR:-}" = ":" ]; then
            cleanup='whitespace'
        else
            cleanup='strip'
        fi
    fi
    case "$cleanup" in
        strip)
            prefix=$(cc_comment_prefix "$PROJECT_ROOT")
            if [ -n "$prefix" ]; then
                subject=$(awk -v p="$prefix" 'substr($0, 1, length(p)) != p' "$MSG_FILE" | grep -m1 . || true)
            else
                subject=$(grep -m1 . "$MSG_FILE" || true)
            fi
            ;;
        scissors)
            subject=$(sed '/ ------------------------ >8 ------------------------$/,$d' "$MSG_FILE" | grep -m1 . || true)
            ;;
        *)
            subject=$(grep -m1 . "$MSG_FILE" || true)
            ;;
    esac
elif [ -n "$MESSAGE" ]; then
    subject=$(printf '%s\n' "$MESSAGE" | grep -m1 . || true)
else
    usage
fi

# Trim trailing whitespace. For a stored message the leading whitespace is
# kept: git preserves indentation on a non-empty subject line and the history
# check would reject it, so the hook must too. A PR title is trimmed on both
# sides, as GitHub does.
if [ -n "$MSG_FILE" ]; then
    subject=$(printf '%s' "$subject" | sed 's/[[:space:]]*$//')
else
    subject=$(printf '%s' "$subject" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
fi

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
