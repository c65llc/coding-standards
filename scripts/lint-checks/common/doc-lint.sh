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
# docs/architecture/decisions/. README.md, index.md and the template file
# itself (template.md, adr-template.md, 0000-template.md, NNNN-template.md …)
# are exempt; a numbered decision whose subject merely mentions "template" is
# not.
#   * Status  — `- **Status:** <value>`, a `## Status` heading, or a `Status:`
#               line; the value must start with Proposed, Accepted, Rejected,
#               Deprecated or Superseded (proc-01 §1 vocabulary)
#   * Date    — `- **Date:** <value>`, a `## Date` heading, or a `Date:` line;
#               the value must start with an ISO date (YYYY-MM-DD)
#   * Headings named Context, Decision and Consequences (any level)
#   For the heading form the value is the first non-blank line under the
#   heading, so an empty `## Status` section counts as missing.
#
# Link rules — inline `[text](target)`, `![alt](target)` and reference
# definitions `[label]: target` whose target is relative (no URL scheme, no
# leading `/`, not a bare `#anchor`) must resolve from the linking file's
# directory. Destinations follow CommonMark: `<...>` may contain spaces,
# otherwise balanced parentheses are part of the target and the destination
# ends at whitespace (title) or the unbalanced `)`. Fragments, query strings
# and titles are stripped; fenced code blocks (matched by delimiter character
# and length, so a shorter fence inside a longer one is content) and inline
# code spans are ignored.
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
        # core.quotePath=false: emit non-ASCII names verbatim instead of the
        # C-escaped, double-quoted form ("docs/\346\227\245.md") that would
        # never match a real file.
        git -C "$PROJECT_ROOT" -c core.quotePath=false ls-files \
            --cached --others --exclude-standard -- '*.md' '*.MD' 2>/dev/null
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
    local base
    case "$1" in
        docs/adr/*|docs/adrs/*|docs/decisions/*|docs/architecture/decisions/*) ;;
        *) return 1 ;;
    esac
    base="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
    case "$base" in
        readme.md|index.md) return 1 ;;
    esac
    # The template file only: template.md, adr-template.md, adr_template.md,
    # _template.md, 0000-template.md, nnnn-adr-template.md, xxxx-template.md.
    # "0007-select-template-engine.md" is a real decision and stays in scope.
    if [[ "$base" =~ ^(0000|nnnn|xxxx|_)?[-_]?(adr[-_])?template\.md$ ]]; then
        return 1
    fi
    return 0
}

# Prints the value of a Status/Date-style metadata field (trimmed), or nothing
# when the field is absent or empty. Accepts:
#   - **Field:** value   |   **Field**: value   |   Field: value
#   ## Field            (value = first non-blank line below, unless a heading)
adr_field_value() {
    local file="$1" field="$2"
    LC_ALL=C awk -v field="$field" '
        function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
        {
            low = tolower($0)
            if (match(low, "^[[:space:]]*([-*+][[:space:]]+)?(\\*\\*|__)?" field "(:(\\*\\*|__)?|(\\*\\*|__):)")) {
                v = substr($0, RSTART + RLENGTH)
                print trim(v); exit
            }
            if (match(low, "^#+[[:space:]]+" field "([[:space:]]|$)")) { want = 1; next }
            if (want) {
                if ($0 ~ /^[[:space:]]*$/) next
                if ($0 ~ /^[[:space:]]*#/) exit            # empty section
                print trim($0); exit
            }
        }
    ' "$file"
}

# Prints the missing or invalid fields for one ADR (space-separated);
# empty = complete.
adr_missing_fields() {
    local file="$1" missing="" status date
    status="$(adr_field_value "$file" status)"
    if ! printf '%s\n' "$status" \
        | grep -qiE '^(proposed|accepted|rejected|deprecated|superseded)([^a-z]|$)'; then
        missing="$missing Status"
    fi
    date="$(adr_field_value "$file" date)"
    if ! printf '%s\n' "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}([^0-9]|$)'; then
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
# LC_ALL=C: the destination parser walks the line one position at a time, and
# in a UTF-8 locale macOS awk aborts ("multibyte conversion failure") when a
# single byte of a multibyte character is tested against a regex. Byte
# semantics are safe here because every cut point is an ASCII delimiter.
extract_relative_links() {
    LC_ALL=C awk '
        # angle=1: the destination came from <...> and may contain spaces.
        function emit(target, angle) {
            if (!angle) sub(/[[:space:]].*$/, "", target)   # drop link title
            sub(/[#?].*$/, "", target)                      # drop fragment / query
            if (target == "") return
            if (target ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return   # URL scheme
            if (target ~ /^\//) return                         # site-absolute
            if (target ~ /\{\{/) return                        # template var
            print target
        }
        # Parse one destination starting at the first character of rest.
        # Sets DEST and DEST_ANGLE; returns the number of characters consumed
        # up to and including the closing ")" of the link, or 0 if the link
        # does not close on this line.
        function parse_dest(rest,    n, j, k, c, depth) {
            n = length(rest)
            if (substr(rest, 1, 1) == "<") {
                j = index(rest, ">")
                if (j == 0) return 0
                DEST = substr(rest, 2, j - 2); DEST_ANGLE = 1
                k = index(substr(rest, j + 1), ")")
                if (k == 0) return 0
                return j + k
            }
            depth = 0; j = 1
            while (j <= n) {
                c = substr(rest, j, 1)
                if (c == "\\") { j += 2; continue }
                if (c == "(") depth++
                else if (c == ")") { if (depth == 0) break; depth-- }
                else if (c == " " || c == "\t") break
                j++
            }
            if (j > n) return 0
            DEST = substr(rest, 1, j - 1); DEST_ANGLE = 0
            if (c == ")") return j
            k = index(substr(rest, j), ")")
            if (k == 0) return 0
            return j + k - 1
        }
        # Fenced code: remember the opening delimiter character and run length;
        # only a fence of the same character and at least that length closes it.
        /^[[:space:]]*(```|~~~)/ {
            match($0, /^[[:space:]]*/); rest = substr($0, RLENGTH + 1)
            ch = substr(rest, 1, 1); n = 0
            while (substr(rest, n + 1, 1) == ch) n++
            if (!in_fence) { in_fence = 1; fence_ch = ch; fence_len = n; next }
            if (ch == fence_ch && n >= fence_len && substr(rest, n + 1) ~ /^[[:space:]]*$/) {
                in_fence = 0; next
            }
        }
        in_fence { next }
        {
            line = $0
            gsub(/`[^`]*`/, "", line)             # drop inline code spans
            # Reference-style definition: [label]: target
            if (match(line, /^[[:space:]]*\[[^]]+\]:[[:space:]]*/)) {
                rest = substr(line, RLENGTH + 1)
                if (substr(rest, 1, 1) == "<") {
                    j = index(rest, ">")
                    if (j > 1) emit(substr(rest, 2, j - 2), 1)
                } else if (match(rest, /^[^[:space:]]+/)) {
                    emit(substr(rest, 1, RLENGTH), 0)
                }
                next
            }
            # Inline links and images: ](destination "title")
            pos = 1
            while ((i = index(substr(line, pos), "](")) > 0) {
                start = pos + i + 1                       # first char after "]("
                used = parse_dest(substr(line, start))
                if (used == 0) { pos = start; continue }  # unterminated; keep scanning
                emit(DEST, DEST_ANGLE)
                pos = start + used
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
                ADR_EXAMPLES="${ADR_EXAMPLES}${rel} (missing/invalid: ${missing// /, }); "
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
    MSG="${MSG}${ADR_BAD_COUNT} ADR(s) missing or invalid required fields: ${ADR_EXAMPLES%; }; "
fi
if [ "$BROKEN_COUNT" -gt 0 ]; then
    MSG="${MSG}${BROKEN_COUNT} broken relative link(s): ${BROKEN_EXAMPLES%; }; "
fi
echo "FAIL $CHECK_NAME ${MSG%; } — fix the link target or add the missing ADR field, then re-run lint-standards"
exit 1
