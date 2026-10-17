#!/bin/bash
# Check: every pull_request workflow bounds its cost (arch-08 §3) — it declares
#        `concurrency` with `cancel-in-progress` (at workflow level, or on every
#        job), every job that runs steps sets `timeout-minutes`, and the
#        workflow scopes itself to changed paths (`paths:`/`paths-ignore:` on
#        the pull_request trigger itself, a paths-filter/changed-files action
#        feeding an always-run gate job, or an explicit
#        `# ci-hygiene: paths-exempt <reason>` marker).
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="ci-workflow-hygiene"
WORKFLOW_DIR="$PROJECT_ROOT/.github/workflows"

if [ ! -d "$WORKFLOW_DIR" ]; then
    echo "PASS $CHECK_NAME No GitHub Actions workflows found (nothing to check)"
    exit 0
fi

WORKFLOW_FILES=$(find "$WORKFLOW_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)

if [ -z "$WORKFLOW_FILES" ]; then
    echo "PASS $CHECK_NAME No GitHub Actions workflows found (nothing to check)"
    exit 0
fi

# Does this workflow run on pull_request / pull_request_target? Matches the
# inline form (`on: pull_request`, `on: [push, pull_request]`), the mapping
# form (`  pull_request:`), and the list form (`  - pull_request`).
is_pr_workflow() {
    grep -qE '^on:[[:space:]]*(\[[^]]*)?pull_request(_target)?|^[[:space:]]+(-[[:space:]]+)?pull_request(_target)?:?([[:space:]]|$)' "$1" 2>/dev/null
}

# Does the `on:` block scope the pull_request / pull_request_target trigger
# with `paths:` or `paths-ignore:`? Only keys nested under that trigger count:
# a `paths:` under `push:` does not scope the PR run, and a `paths:` input to
# some action deep inside `jobs:` is not a trigger filter at all.
has_trigger_paths() {
    awk '
        /^on:[[:space:]]*(#.*)?$/ { inon = 1; next }
        inon && /^[^[:space:]#]/ { inon = 0 }
        inon {
            if ($0 ~ /^[[:space:]]*(#|$)/) next
            match($0, /^[[:space:]]*/); ind = RLENGTH
            if ($0 ~ /^[[:space:]]+pull_request(_target)?:[[:space:]]*(#.*)?$/) { trig = ind; intrig = 1; next }
            if (intrig && ind <= trig) intrig = 0
            if (intrig && $0 ~ /^[[:space:]]+paths(-ignore)?:/) { found = 1; exit }
        }
        END { exit found ? 0 : 1 }
    ' "$1" 2>/dev/null
}

# Walk the jobs under `jobs:` and count how many lack a job-level
# `timeout-minutes` and how many lack job-level `concurrency` with
# `cancel-in-progress`. Jobs that call a reusable workflow (`uses:` at job
# level) cannot declare `timeout-minutes` and are excluded from that count
# only; the called workflow's jobs declare theirs. Assumes the conventional
# 2-space indent; prints "<total> <missing-timeout> <missing-concurrency>".
count_job_gaps() {
    awk '
        function flush() {
            if (injob) {
                total++
                if (!has_timeout && !is_reusable) missing_t++
                if (!has_conc || !has_cancel) missing_c++
            }
            injob = 0; has_timeout = 0; is_reusable = 0; has_conc = 0; has_cancel = 0
        }
        /^jobs:[[:space:]]*(#.*)?$/ { injobs = 1; next }
        injobs && /^[^[:space:]#]/ { flush(); injobs = 0 }
        injobs && /^  [A-Za-z0-9_-]+:[[:space:]]*(#.*)?$/ { flush(); injob = 1; next }
        injobs && injob && /^    timeout-minutes:/ { has_timeout = 1 }
        injobs && injob && /^    uses:/ { is_reusable = 1 }
        injobs && injob && /^    concurrency:/ { has_conc = 1 }
        injobs && injob && has_conc && /^      cancel-in-progress:/ { has_cancel = 1 }
        END { flush(); printf "%d %d %d\n", total + 0, missing_t + 0, missing_c + 0 }
    ' "$1" 2>/dev/null
}

PR_COUNT=0
FINDINGS=""

while IFS= read -r file; do
    [ -n "$file" ] || continue
    is_pr_workflow "$file" || continue
    PR_COUNT=$((PR_COUNT + 1))

    gaps=""

    counts=$(count_job_gaps "$file")
    set -- $counts
    total=${1:-0}
    missing_t=${2:-0}
    missing_c=${3:-0}

    # 1. concurrency + cancel-in-progress. Workflow-level covers every job;
    #    otherwise every job must carry its own, or the siblings without one
    #    keep running after a superseding push and the cost bound is fiction.
    if grep -qE '^concurrency:' "$file" 2>/dev/null; then
        if ! grep -qE '^  cancel-in-progress:' "$file" 2>/dev/null; then
            gaps="${gaps}${gaps:+, }concurrency without cancel-in-progress"
        fi
    elif [ "$total" -gt 0 ] && [ "$missing_c" -eq 0 ]; then
        : # job-level concurrency + cancel-in-progress on every job
    elif grep -qE '^[[:space:]]+concurrency:' "$file" 2>/dev/null; then
        gaps="${gaps}${gaps:+, }${missing_c}/${total} job(s) lack concurrency with cancel-in-progress (declare it at workflow level or on every job)"
    else
        gaps="${gaps}${gaps:+, }missing concurrency"
    fi

    # 2. timeout-minutes on every job that runs steps.
    if [ "$total" -gt 0 ]; then
        if [ "$missing_t" -gt 0 ]; then
            gaps="${gaps}${gaps:+, }${missing_t}/${total} job(s) missing timeout-minutes"
        fi
    elif ! grep -qE '^[[:space:]]*timeout-minutes:' "$file" 2>/dev/null; then
        gaps="${gaps}${gaps:+, }missing timeout-minutes"
    fi

    # 3. Path scoping: a paths filter on the PR trigger, a paths-filter /
    #    changed-files action, or an explicit exemption with a reason.
    if ! has_trigger_paths "$file" \
       && ! grep -qE 'paths-filter|changed-files' "$file" 2>/dev/null \
       && ! grep -qE '#[[:space:]]*ci-hygiene:[[:space:]]*paths-exempt' "$file" 2>/dev/null; then
        gaps="${gaps}${gaps:+, }no path scoping (paths: on the pull_request trigger, paths-filter + gate job, or '# ci-hygiene: paths-exempt <reason>')"
    fi

    if [ -n "$gaps" ]; then
        rel="${file#"$PROJECT_ROOT"/}"
        FINDINGS="${FINDINGS}${FINDINGS:+; }${rel}: ${gaps}"
    fi
done <<EOF
$WORKFLOW_FILES
EOF

if [ "$PR_COUNT" -eq 0 ]; then
    echo "PASS $CHECK_NAME No pull_request workflows to check"
    exit 0
fi

if [ -z "$FINDINGS" ]; then
    echo "PASS $CHECK_NAME $PR_COUNT pull_request workflow(s) declare concurrency, timeout-minutes, and path scoping"
    exit 0
fi

echo "WARN $CHECK_NAME pull_request workflows missing cost bounds (arch-08 §3) — $FINDINGS"
exit 2
