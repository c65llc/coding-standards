#!/bin/bash
# Check: documentation lint — ADRs carry their required fields and relative
#        Markdown links resolve to a real file or directory.
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# Scope: every tracked or untracked-but-not-ignored *.md in the project (via
# `git ls-files`), falling back to `find` with a fixed exclusion list outside a
# git checkout. The vendored standards checkout (.standards/) and the
# .standards-pending/ staging dir are always skipped.
#
# ADR rules — files under docs/adr/, docs/adrs/, docs/decisions/ or
# docs/architecture/decisions/ (README.md, index.md and *template* exempt):
#   * Status  — `- **Status:** ...`, a `## Status` heading, or a `Status:` line
#   * Date    — `- **Date:** ...`,   a `## Date` heading,   or a `Date:` line
#   * Headings named Context, Decision and Consequences (any level)
#
# Link rules — inline `[text](target)`, `![alt](target)` and reference
# definitions `[label]: target` whose target is relative (no URL scheme, no
# leading `/`, not a bare `#anchor`) must resolve from the linking file's
# directory. Fragments, query strings and titles are stripped; fenced code
# blocks and inline code spans are ignored.
#
# See standards/process/proc-01_documentation_standards.md §1 and §10.

PROJECT_ROOT="${1:-.}"
CHECK_NAME="doc-lint"

if ! PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)"; then
    echo "WARN $CHECK_NAME Project root not found: ${1:-.}"
    exit 2
fi

# ---------------------------------------------------------------------------
# Collect Markdown files (paths relative to PROJECT_ROOT, one per line)
# ---------------------------------------------------------------------------
list_markdown_files() {
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard \
            -- '*.md' '*.MD' 2>/dev/null
    else
        ( cd "$PROJECT_ROOT" && find . -type f \( -name '*.md' -o -name '*.MD' \) \
            -not -path '*/.git/*' -not -path '*/node_modules/*' \
            -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/build/*' \
            -not -path '*/target/*' -not -path '*/.venv/*' -not -path '*/venv/*' \
            -not -path '*/.next/*' 2>/dev/null | sed 's|^\./||' )
    fi | grep -vE '^(\.standards|\.standards-pending|\.standards_tmp)/' || true
}

# ---------------------------------------------------------------------------
# ADR required fields
# ---------------------------------------------------------------------------
is_adr_path() {
    case "$1" in
        docs/adr/*|docs/adrs/*|docs/decisions/*|docs/architecture/decisions/*) ;;
        *) return 1 ;;
    esac
    case "$(basename "$1" | tr '[:upper:]' '[:lower:]')" in
        readme.md|index.md|*template*) return 1 ;;
    esac
    return 0
}

# Prints the missing fields for one ADR (space-separated); empty = complete.
# Status/Date accept bullet metadata (`- **Status:** x`), a heading (`## Status`)
# or a bare `Status:` line, so legacy ADRs keep passing.
adr_missing_fields() {
    local file="$1" missing=""
    local meta_prefix='^[[:space:]]*([-*+][[:space:]]+)?(\*\*|__)?'
    local meta_suffix='(:(\*\*|__)?|(\*\*|__):)'

    if ! grep -qiE "${meta_prefix}status${meta_suffix}|^#{1,6}[[:space:]]+status([[:space:]]|$)" "$file"; then
        missing="$missing Status"
    fi
    if ! grep -qiE "${meta_prefix}date${meta_suffix}|^#{1,6}[[:space:]]+date([[:space:]]|$)" "$file"; then
        missing="$missing Date"
    fi
    for section in Context Decision Consequences; do
        if ! grep -qiE "^#{1,6}[[:space:]]+${section}([[:space:]]|$)" "$file"; then
            missing="$missing $section"
        fi
    done
    printf '%s' "${missing# }"
}

# ---------------------------------------------------------------------------
# Relative link extraction
# ---------------------------------------------------------------------------
# Prints the relative link targets in a Markdown file, one per line.
extract_relative_links() {
    awk '
        function emit(target) {
            sub(/^</, "", target); sub(/>$/, "", target)
            sub(/[[:space:]].*$/, "", target)     # drop link title
            sub(/[#?].*$/, "", target)            # drop fragment / query
            if (target == "") return
            if (target ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return   # URL scheme
            if (target ~ /^\//) return                         # site-absolute
            if (target ~ /\{\{/) return                        # template var
            print target
        }
        /^[[:space:]]*(```|~~~)/ { in_fence = !in_fence; next }
        in_fence { next }
        {
            line = $0
            gsub(/`[^`]*`/, "", line)             # drop inline code spans
            # Reference-style definition: [label]: target
            if (match(line, /^[[:space:]]*\[[^]]+\]:[[:space:]]*[^[:space:]]+/)) {
                def = substr(line, RSTART, RLENGTH)
                sub(/^[[:space:]]*\[[^]]+\]:[[:space:]]*/, "", def)
                emit(def)
                next
            }
            # Inline links and images: ](target)
            while (match(line, /\]\([^)]*\)/)) {
                emit(substr(line, RSTART + 2, RLENGTH - 3))
                line = substr(line, RSTART + RLENGTH)
            }
        }
    ' "$1"
}

# ---------------------------------------------------------------------------
# Walk the files
# ---------------------------------------------------------------------------
FILE_COUNT=0
ADR_COUNT=0
ADR_BAD_COUNT=0
ADR_EXAMPLES=""
BROKEN_COUNT=0
BROKEN_EXAMPLES=""

while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    file="$PROJECT_ROOT/$rel"
    [ -f "$file" ] || continue
    FILE_COUNT=$((FILE_COUNT + 1))
    dir="$(dirname "$file")"

    if is_adr_path "$rel"; then
        ADR_COUNT=$((ADR_COUNT + 1))
        missing="$(adr_missing_fields "$file")"
        if [ -n "$missing" ]; then
            ADR_BAD_COUNT=$((ADR_BAD_COUNT + 1))
            if [ "$ADR_BAD_COUNT" -le 3 ]; then
                ADR_EXAMPLES="${ADR_EXAMPLES}${rel} (missing: ${missing// /, }); "
            fi
        fi
    fi

    while IFS= read -r target; do
        [ -n "$target" ] || continue
        target="${target//%20/ }"
        if [ ! -e "$dir/$target" ]; then
            BROKEN_COUNT=$((BROKEN_COUNT + 1))
            if [ "$BROKEN_COUNT" -le 3 ]; then
                BROKEN_EXAMPLES="${BROKEN_EXAMPLES}${rel} -> ${target}; "
            fi
        fi
    done <<EOF
$(extract_relative_links "$file")
EOF
done <<EOF
$(list_markdown_files)
EOF

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [ "$FILE_COUNT" -eq 0 ]; then
    echo "PASS $CHECK_NAME No Markdown documents found (nothing to lint)"
    exit 0
fi

if [ "$ADR_BAD_COUNT" -eq 0 ] && [ "$BROKEN_COUNT" -eq 0 ]; then
    echo "PASS $CHECK_NAME $FILE_COUNT Markdown file(s) checked; $ADR_COUNT ADR(s) complete; all relative links resolve"
    exit 0
fi

MSG=""
if [ "$ADR_BAD_COUNT" -gt 0 ]; then
    MSG="${MSG}${ADR_BAD_COUNT} ADR(s) missing required fields: ${ADR_EXAMPLES%; }; "
fi
if [ "$BROKEN_COUNT" -gt 0 ]; then
    MSG="${MSG}${BROKEN_COUNT} broken relative link(s): ${BROKEN_EXAMPLES%; }; "
fi
echo "FAIL $CHECK_NAME ${MSG%; } — fix the link target or add the missing ADR field, then re-run lint-standards"
exit 1
