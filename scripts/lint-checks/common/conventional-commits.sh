#!/bin/bash
# Check: Conventional Commits on recent history
# Receives: [--since <ref>] [--window <n>] [project-root]
# Outputs:  PASS|WARN|FAIL <check-name> <message>
# Exit:     0=PASS, 1=FAIL, 2=WARN
#
# Range selection (first match wins; a range always beats a window):
#   1. --since <ref> / --window <n> flags
#   2. .standards.yml  commits.since: origin/main   # check <ref>..HEAD
#   3. STANDARDS_COMMITS_SINCE env (set by the standards-review action to the
#      PR base so a PR is judged on its own commits)
#   4. .standards.yml  commits.window: 50           # last N non-merge commits
#   5. default: last 50 non-merge commits
#
# Scope allow-list (optional):
#   commits:
#     scopes: [api, domain, ui]   # scoped commits must use one of these
#
# Merge commits are skipped (git writes their subjects); fixup!/squash!
# prefixes and `git revert` subjects are exempt.

CHECK_NAME="conventional-commits"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../../lib/conventional-commits.sh"
if [ ! -f "$LIB" ]; then
    echo "WARN $CHECK_NAME Shared helper lib/conventional-commits.sh not found — skipping"
    exit 2
fi
# shellcheck source=../../lib/conventional-commits.sh
source "$LIB"

PROJECT_ROOT="."
SINCE=""
WINDOW=""

while [ $# -gt 0 ]; do
    case "$1" in
        --since)
            SINCE="${2:-}"
            shift
            [ $# -gt 0 ] && shift
            ;;
        --since=*)
            SINCE="${1#--since=}"
            shift
            ;;
        --window)
            WINDOW="${2:-}"
            shift
            [ $# -gt 0 ] && shift
            ;;
        --window=*)
            WINDOW="${1#--window=}"
            shift
            ;;
        -*)
            echo "WARN $CHECK_NAME Unknown option '$1' (expected --since <ref> or --window <n>)"
            exit 2
            ;;
        *)
            PROJECT_ROOT="$1"
            shift
            ;;
    esac
done

# Ensure we're in a git repo
if ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "WARN $CHECK_NAME Not a git repository — skipping commit check"
    exit 2
fi

# Resolve the range: flags > commits.since > env (PR base) > commits.window > 50.
# A range from any source beats a configured window, otherwise a project that
# pins `window:` would make the action inspect the last N mainline commits
# instead of the PR's own commits.
yml_since=$(cc_config_get "$PROJECT_ROOT" since)
yml_window=$(cc_config_get "$PROJECT_ROOT" window)

if [ -z "$SINCE" ] && [ -z "$WINDOW" ]; then
    if [ -n "$yml_since" ]; then
        SINCE="$yml_since"
    elif [ -n "${STANDARDS_COMMITS_SINCE:-}" ]; then
        SINCE="$STANDARDS_COMMITS_SINCE"
    elif [ -n "$yml_window" ]; then
        WINDOW="$yml_window"
    fi
fi

if [ -z "$SINCE" ]; then
    case "$WINDOW" in
        '') WINDOW=50 ;;
        *[!0-9]*)
            echo "WARN $CHECK_NAME commits.window must be a positive integer (got '$WINDOW')"
            exit 2
            ;;
    esac
    if [ "$WINDOW" -lt 1 ]; then
        WINDOW=50
    fi
fi

SCOPES=$(cc_config_scopes "$PROJECT_ROOT")

# Collect subjects
if [ -n "$SINCE" ]; then
    if ! git -C "$PROJECT_ROOT" rev-parse --verify --quiet "${SINCE}^{commit}" >/dev/null 2>&1; then
        echo "WARN $CHECK_NAME Ref '$SINCE' not found — cannot check commits since it (fetch it, or fix commits.since)"
        exit 2
    fi
    subjects=$(git -C "$PROJECT_ROOT" log --no-merges --format='%H %s' "${SINCE}..HEAD" 2>/dev/null)
    range_desc="commits since $SINCE"
else
    subjects=$(git -C "$PROJECT_ROOT" log --no-merges --format='%H %s' -n "$WINDOW" 2>/dev/null)
    range_desc="commits (window $WINDOW)"
fi

total=0
bad_format=0
bad_scope=0
example=""
bad_scopes=""

# Each line is "<hash> <subject>" so a commit with an empty subject
# (--allow-empty-message) still occupies a line and is counted as a violation.
while IFS= read -r line; do
    [ -z "$line" ] && continue
    total=$((total + 1))
    subject="${line#* }"
    [ "$subject" = "$line" ] && subject=""
    if [ -z "$subject" ]; then
        bad_format=$((bad_format + 1))
        [ -z "$example" ] && example="(empty subject)"
        continue
    fi
    if cc_is_exempt "$subject"; then
        continue
    fi
    if ! cc_is_conventional "$subject"; then
        bad_format=$((bad_format + 1))
        if [ -z "$example" ]; then
            example=$(printf '%s' "$subject" | cut -c1-60 | tr -d '"')
        fi
        continue
    fi
    if [ -n "$SCOPES" ]; then
        scope=$(cc_scope "$subject")
        if ! cc_scope_allowed "$scope" "$SCOPES"; then
            bad_scope=$((bad_scope + 1))
            case " $bad_scopes " in
                *" $scope "*) ;;
                *) bad_scopes="${bad_scopes:+$bad_scopes }$scope" ;;
            esac
        fi
    fi
done << EOF
$subjects
EOF

if [ "$total" -eq 0 ]; then
    if [ -n "$SINCE" ]; then
        echo "PASS $CHECK_NAME No commits since $SINCE to check"
        exit 0
    fi
    echo "WARN $CHECK_NAME No commits found to check"
    exit 2
fi

bad=$((bad_format + bad_scope))

if [ "$bad" -eq 0 ]; then
    scope_note=""
    if [ -n "$SCOPES" ]; then
        scope_note=" (scopes restricted to: $(printf '%s' "$SCOPES" | tr ' ' ','))"
    fi
    echo "PASS $CHECK_NAME All $total $range_desc follow Conventional Commits$scope_note"
    exit 0
fi

message=""
if [ "$bad_format" -gt 0 ]; then
    message="$bad_format of $total $range_desc don't follow Conventional Commits (e.g. '$example')"
fi
if [ "$bad_scope" -gt 0 ]; then
    scope_msg="$bad_scope of $total $range_desc use a scope outside commits.scopes ($(printf '%s' "$bad_scopes" | tr ' ' ','))"
    message="${message:+$message; }$scope_msg"
fi

# Tolerance scales with the range: up to max(3, 10% of total) violations WARN,
# anything above that FAILs. The floor of 3 keeps a short PR range from failing
# on a single straggler; the 10% keeps long histories from hiding drift.
threshold=$((total / 10))
if [ "$threshold" -lt 3 ]; then
    threshold=3
fi

if [ "$bad" -le "$threshold" ]; then
    echo "WARN $CHECK_NAME $message"
    exit 2
fi

echo "FAIL $CHECK_NAME $message"
exit 1
