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
# per line (`#` comments), matched against project-relative paths with the
# same semantics as `.standards.yml` lint.exclude: `*` matches within a path
# segment, `**` across segments (lint__glob_to_ere). Committed, so a
# deliberate tell is written down where review can see it. Files come from
# scripts/lib/lint-files.sh (default policy: built-in exclusions and
# lint.exclude apply) filtered to stylesheet and script extensions. Every hit
# is counted; up to five locations are named and the rest summarised. A line
# that starts with `//` or `/*` is a comment and not a hit; a bare `*` is a
# universal selector and is.

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

# Allowlist: one glob per line, lint.exclude semantics, joined into one ERE
# anchored to the whole project-relative path.
ALLOW_FILE="$PROJECT_ROOT/.standards-ui-allow"
ALLOW_ERE=""
if [ -f "$ALLOW_FILE" ]; then
    while IFS= read -r glob; do
        glob=$(printf '%s' "$glob" | sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$glob" ] || continue
        ALLOW_ERE="${ALLOW_ERE:+$ALLOW_ERE|}$(lint__glob_to_ere "$glob")"
    done < "$ALLOW_FILE"
fi

allowed() {
    [ -n "$ALLOW_ERE" ] || return 1
    printf '%s\n' "$1" | grep -qE "^($ALLOW_ERE)$"
}

PATTERN='cursor:[[:space:]]*pointer|scroll-behavior:[[:space:]]*smooth|behavior:[[:space:]]*["'"'"']smooth["'"'"']|user-select:[[:space:]]*text'

# Every matching line in every matching file (no per-file cap, unlike
# lint_grep_hits), minus lines that start with a comment opener. The per-file
# "<line>:" prefix anchors the comment test so neither the filename nor the
# content can forge a suppression.
LOCATIONS=""
COUNT=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#"$PROJECT_ROOT/"}"
    allowed "$rel" && continue
    while IFS= read -r numbered; do
        [ -n "$numbered" ] || continue
        COUNT=$((COUNT + 1))
        if [ "$COUNT" -le 5 ]; then
            LOCATIONS="${LOCATIONS:+$LOCATIONS, }$rel:${numbered%%:*}"
        fi
    done <<EOF_LINES
$(grep -InE -- "$PATTERN" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*(//|/\*)' || true)
EOF_LINES
done <<EOF_FILES
$(lint_grep_files "$FILES" -lE "$PATTERN")
EOF_FILES

if [ "$COUNT" -eq 0 ]; then
    echo "PASS $CHECK_NAME no web tells found (cursor: pointer, smooth scroll, selectable chrome)"
    exit 0
fi

MORE=""
[ "$COUNT" -gt 5 ] && MORE=" (+$((COUNT - 5)) more)"
echo "WARN $CHECK_NAME $COUNT hit(s): $LOCATIONS$MORE; fix, or record a ruled exception in .standards-ui-allow (arch-11 §3)"
exit 2
