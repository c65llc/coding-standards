#!/bin/bash
# Check: web tells — CSS and script idioms that make an installed web app or a
#        web-rendered surface read as "a web page in a frame" (arch-11 §3, §5).
# Receives: $1 = project root
# Outputs: PASS|WARN <check-name> <message>
# Exit:    0=PASS, 2=WARN. Never FAILs: a tell is a design call, and the
#          remedy is either a fix or a ruled exception in .standards-ui-allow.
#
# Runs only for projects that declare the ui-surface profile (#227): the
# runner invokes lint-checks/profiles/<profile>/ per declared profile.
#
# Patterns (arch-11 §3 items 1, 2, 28):
#   cursor: pointer           native rows, tabs and buttons do not change the cursor
#   scroll-behavior: smooth   a smooth-scroll override the platform did not ask for
#   behavior: 'smooth'        the same, from script
#   user-select: text         chrome made selectable; only content is
#
# Exemptions: .standards-ui-allow at the project root, one shell-style glob
# per line (`#` comments), matched against project-relative paths. Committed,
# so a deliberate tell is written down where review can see it. Files come
# from scripts/lib/lint-files.sh (default policy: built-in exclusions and
# .standards.yml lint.exclude apply) filtered to stylesheet and script
# extensions. Up to five locations are named; the rest are counted.

PROJECT_ROOT="${1:-.}"
CHECK_NAME="web-tells"

LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../../lib/lint-files.sh
source "$LINT_LIB"

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "WARN $CHECK_NAME Project root '$PROJECT_ROOT' not found"
    exit 2
fi

EXT_ERE='\.(css|scss|tsx|jsx|vue|svelte|ts|js)$'
FILES=$(lint_list_files "$PROJECT_ROOT" docs | grep -E "$EXT_ERE" | grep -vE '\.(min\.js|d\.ts)$' || true)

if [ -z "$FILES" ]; then
    echo "PASS $CHECK_NAME no stylesheet or script files to check"
    exit 0
fi

# Allowlist: one glob per line; a path matching any glob is exempt.
ALLOW_FILE="$PROJECT_ROOT/.standards-ui-allow"
ALLOW_GLOBS=""
if [ -f "$ALLOW_FILE" ]; then
    ALLOW_GLOBS=$(sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$ALLOW_FILE" | grep -v '^$' || true)
fi

allowed() {
    local rel="$1" glob
    [ -n "$ALLOW_GLOBS" ] || return 1
    while IFS= read -r glob; do
        [ -n "$glob" ] || continue
        # shellcheck disable=SC2254 # the glob is the point
        case "$rel" in $glob) return 0 ;; esac
    done <<EOF_GLOBS
$ALLOW_GLOBS
EOF_GLOBS
    return 1
}

PATTERN='cursor:[[:space:]]*pointer|scroll-behavior:[[:space:]]*smooth|behavior:[[:space:]]*["'"'"']smooth["'"'"']|user-select:[[:space:]]*text'

# lint_grep_hits yields "<rel>:<line>:<content>"; the third argument drops
# lines that start with a line comment so a commented-out tell is not a tell.
HITS=$(lint_grep_hits "$FILES" "$PROJECT_ROOT" '//|/\*|\*' "$PATTERN" || true)

LOCATIONS=""
COUNT=0
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    rel="${hit%%:*}"
    rest="${hit#*:}"
    line="${rest%%:*}"
    allowed "$rel" && continue
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -le 5 ]; then
        LOCATIONS="${LOCATIONS:+$LOCATIONS, }$rel:$line"
    fi
done <<EOF_HITS
$HITS
EOF_HITS

if [ "$COUNT" -eq 0 ]; then
    echo "PASS $CHECK_NAME no web tells found (cursor: pointer, smooth scroll, selectable chrome)"
    exit 0
fi

MORE=""
[ "$COUNT" -gt 5 ] && MORE=" (+$((COUNT - 5)) more)"
echo "WARN $CHECK_NAME $COUNT hit(s): $LOCATIONS$MORE; fix, or record a ruled exception in .standards-ui-allow (arch-11 §3)"
exit 2
