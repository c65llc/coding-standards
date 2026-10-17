#!/bin/bash
# Check: documentation lint — ADRs carry their required fields and relative
#        Markdown links resolve to a real file or directory.
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# Scope: every tracked or untracked-but-not-ignored Markdown file (any case of
# the .md extension) in the project (via `git ls-files`), falling back to
# `find` with a fixed exclusion list outside a git checkout. The vendored
# standards checkout (.standards/) and the .standards-pending/ staging dir are
# always skipped.
#
# Code is never content: fenced blocks (opener indented at most three spaces,
# closed only by a fence of the same character and at least the same length)
# and indented code blocks (four spaces or a tab after a blank line, until a
# less-indented non-blank line) are removed before both the ADR checks and the
# link scan, so an example ADR or an example link inside a code block can
# neither satisfy nor fail a rule. Inline code spans (any backtick run length)
# are removed from the remaining lines.
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
#   * Headings named Context, Decision and Consequences (any level; up to three
#     leading spaces as CommonMark allows)
#   For the heading form the value is the first non-blank line under the
#   heading, so an empty `## Status` section counts as missing.
#
# Link rules — inline `[text](target)`, `![alt](target)` and reference
# definitions `[label]: target` whose target is relative (no URL scheme, no
# leading `/`, not a bare `#anchor`) must resolve from the linking file's
# directory. Destinations follow CommonMark: optional whitespace after `(`,
# `<...>` may contain spaces, otherwise balanced parentheses are part of the
# target and the destination ends at whitespace (title) or the unbalanced `)`;
# backslash escapes and percent-encoding are decoded. An escaped `\[` or `\]`
# does not form a link, and footnote definitions (`[^1]: …`) are not reference
# links. Fragments, query strings and titles are stripped.
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
        # never match a real file. :(icase) matches .md, .MD, .Md and .mD.
        git -C "$PROJECT_ROOT" -c core.quotePath=false ls-files \
            --cached --others --exclude-standard -- ':(icase)*.md' 2>/dev/null
    else
        ( cd "$PROJECT_ROOT" && find . -type f -iname '*.md' \
            -not -path '*/.git/*' -not -path '*/node_modules/*' \
            -not -path '*/vendor/*' -not -path '*/dist/*' -not -path '*/build/*' \
            -not -path '*/target/*' -not -path '*/.venv/*' -not -path '*/venv/*' \
            -not -path '*/.next/*' 2>/dev/null | sed 's|^\./||' )
    fi | grep -vE '^(\.standards|\.standards-pending|\.standards_tmp)/' || true
}

# ---------------------------------------------------------------------------
# Shared awk rules: skip fenced and indented code blocks
# ---------------------------------------------------------------------------
# Prepended to every awk program below. Lines inside code blocks are consumed
# with `next`; everything else falls through to the program's own rules.
#
# All awk programs run under LC_ALL=C: they walk lines one position at a time,
# and in a UTF-8 locale macOS awk aborts ("multibyte conversion failure") when
# a single byte of a multibyte character is tested against a regex. Byte
# semantics are safe here because every cut point is an ASCII delimiter.
# shellcheck disable=SC2016  # awk program text, not shell expansion
AWK_SKIP_CODE='
    BEGIN { prev_blank = 1 }
    # Fenced code: an opener may be indented at most three spaces (four make
    # it indented code). Remember the delimiter character and run length;
    # only a fence of the same character and at least that length, with
    # nothing but whitespace after it, closes the block.
    /^[ \t]*(```|~~~)/ {
        match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH); rest = substr($0, RLENGTH + 1)
        if (length(ind) <= 3 && index(ind, "\t") == 0) {
            ch = substr(rest, 1, 1); n = 0
            while (substr(rest, n + 1, 1) == ch) n++
            if (!in_fence) { in_fence = 1; fence_ch = ch; fence_len = n; prev_blank = 0; next }
            if (ch == fence_ch && n >= fence_len && substr(rest, n + 1) ~ /^[[:space:]]*$/) {
                in_fence = 0; prev_blank = 1; next
            }
        }
    }
    in_fence { next }
    # Indented code: four spaces or a tab at line start, opened only after a
    # blank line (an indented line cannot interrupt a paragraph), running
    # through blank lines until a less-indented non-blank line.
    {
        blank = ($0 ~ /^[[:space:]]*$/)
        if (in_indented) {
            if (blank || $0 ~ /^(    |\t)/) next
            in_indented = 0
        } else if (prev_blank && !blank && $0 ~ /^(    |\t)/) {
            in_indented = 1; next
        }
        prev_blank = blank
    }
'

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

# Prints a Markdown file with fenced and indented code blocks removed.
strip_code_blocks() {
    LC_ALL=C awk "$AWK_SKIP_CODE"' { print }' "$1"
}

# Reads a code-stripped ADR on stdin and prints the value of a Status/Date-style
# metadata field (trimmed), or nothing when the field is absent or empty.
# Accepts:
#   - **Field:** value   |   **Field**: value   |   Field: value
#   ## Field            (value = first non-blank line below, unless a heading)
adr_field_value() {
    local field="$1"
    LC_ALL=C awk -v field="$field" '
        function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
        {
            low = tolower($0)
            if (match(low, "^[[:space:]]*([-*+][[:space:]]+)?(\\*\\*|__)?" field "(:(\\*\\*|__)?|(\\*\\*|__):)")) {
                v = substr($0, RSTART + RLENGTH)
                print trim(v); exit
            }
            if (match(low, "^ ? ? ?#+[[:space:]]+" field "([[:space:]]|$)")) { want = 1; next }
            if (want) {
                if ($0 ~ /^[[:space:]]*$/) next
                if ($0 ~ /^[[:space:]]*#/) exit            # empty section
                print trim($0); exit
            }
        }
    '
}

# Prints the missing or invalid fields for one ADR (space-separated);
# empty = complete. Code blocks are removed first so an embedded example
# cannot satisfy the structure.
adr_missing_fields() {
    local file="$1" missing="" body status date
    body="$(strip_code_blocks "$file")"
    status="$(printf '%s\n' "$body" | adr_field_value status)"
    if ! printf '%s\n' "$status" \
        | grep -qiE '^(proposed|accepted|rejected|deprecated|superseded)([^a-z]|$)'; then
        missing="$missing Status"
    fi
    date="$(printf '%s\n' "$body" | adr_field_value date)"
    if ! printf '%s\n' "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}([^0-9]|$)'; then
        missing="$missing Date"
    fi
    for section in Context Decision Consequences; do
        if ! printf '%s\n' "$body" \
            | grep -qiE "^ {0,3}#{1,6}[[:space:]]+${section}([[:space:]]|$)"; then
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
    LC_ALL=C awk "$AWK_SKIP_CODE"'
        # Remove the first unescaped "#" or "?" and everything after it,
        # honouring backslash escapes (a "\#" is part of the path).
        function strip_fragment(t,    i, L, c) {
            L = length(t); i = 1
            while (i <= L) {
                c = substr(t, i, 1)
                if (c == "\\") { i += 2; continue }
                if (c == "#" || c == "?") return substr(t, 1, i - 1)
                i++
            }
            return t
        }
        # Decode CommonMark backslash escapes: "\" before ASCII punctuation
        # yields the punctuation character; any other "\" is literal.
        function unescape(t,    out, i, L, c, d) {
            out = ""; L = length(t); i = 1
            while (i <= L) {
                c = substr(t, i, 1)
                if (c == "\\" && i < L) {
                    d = substr(t, i + 1, 1)
                    if (d ~ /[!-\/:-@\[-`{-~]/) { out = out d; i += 2; continue }
                }
                out = out c; i++
            }
            return out
        }
        # Decode %XX percent-encoding (any byte, so UTF-8 sequences survive).
        function percent_decode(t,    out, i, L, h, hex) {
            hex = "0123456789abcdef"; out = ""; L = length(t); i = 1
            while (i <= L) {
                if (substr(t, i, 1) == "%" && i + 2 <= L) {
                    h = tolower(substr(t, i + 1, 2))
                    if (h ~ /^[0-9a-f][0-9a-f]$/) {
                        out = out sprintf("%c", (index(hex, substr(h, 1, 1)) - 1) * 16 + index(hex, substr(h, 2, 1)) - 1)
                        i += 3; continue
                    }
                }
                out = out substr(t, i, 1); i++
            }
            return out
        }
        # angle=1: the destination came from <...> and may contain spaces.
        function emit(target, angle) {
            if (!angle) sub(/[[:space:]].*$/, "", target)   # drop link title
            target = percent_decode(unescape(strip_fragment(target)))
            if (target == "") return
            if (target ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return   # URL scheme
            if (target ~ /^\//) return                         # site-absolute
            if (target ~ /\{\{/) return                        # template var
            print target
        }
        # Drop inline code spans. A span opens with a run of N backticks and
        # closes at the next run of exactly N; an unmatched run is literal
        # text. "\`" outside a span is a literal backtick.
        function strip_code_spans(s,    out, i, L, c, n, j, m, found) {
            out = ""; L = length(s); i = 1
            while (i <= L) {
                c = substr(s, i, 1)
                if (c == "\\" && i < L) { out = out substr(s, i, 2); i += 2; continue }
                if (c != "`") { out = out c; i++; continue }
                n = 0; while (substr(s, i + n, 1) == "`") n++
                j = i + n; found = 0
                while (j <= L) {
                    if (substr(s, j, 1) == "`") {
                        m = 0; while (substr(s, j + m, 1) == "`") m++
                        if (m == n) { found = 1; break }
                        j += m
                    } else j++
                }
                if (found) i = j + n
                else { out = out substr(s, i, n); i += n }
            }
            return out
        }
        # Index of the unescaped "[" that opens the link whose "]" is at b,
        # or 0 when there is none (a bare or escaped "](" is not a link).
        function find_opener(s, b,    k, depth, c) {
            depth = 0
            for (k = b - 1; k >= 1; k--) {
                c = substr(s, k, 1)
                if (k > 1 && substr(s, k - 1, 1) == "\\") { k--; continue }
                if (c == "]") depth++
                else if (c == "[") { if (depth == 0) return k; depth-- }
            }
            return 0
        }
        # Parse one destination starting right after "](". Sets DEST and
        # DEST_ANGLE; returns the number of characters consumed up to and
        # including the closing ")" of the link, or 0 if the link does not
        # close on this line.
        function parse_dest(rest,    lead, n, j, k, c, depth) {
            lead = 0
            while (substr(rest, lead + 1, 1) == " " || substr(rest, lead + 1, 1) == "\t") lead++
            if (lead) rest = substr(rest, lead + 1)
            n = length(rest)
            if (substr(rest, 1, 1) == "<") {
                j = index(rest, ">")
                if (j == 0) return 0
                DEST = substr(rest, 2, j - 2); DEST_ANGLE = 1
                k = index(substr(rest, j + 1), ")")
                if (k == 0) return 0
                return lead + j + k
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
            if (c == ")") return lead + j
            k = index(substr(rest, j), ")")
            if (k == 0) return 0
            return lead + j + k - 1
        }
        {
            line = strip_code_spans($0)
            # Reference-style definition: [label]: target  (not footnotes [^1]:)
            if (match(line, /^[[:space:]]*\[[^]^][^]]*\]:[[:space:]]*/)) {
                rest = substr(line, RLENGTH + 1)
                if (substr(rest, 1, 1) == "<") {
                    j = index(rest, ">")
                    if (j > 1) emit(substr(rest, 2, j - 2), 1)
                } else if (match(rest, /^[^[:space:]]+/)) {
                    emit(substr(rest, 1, RLENGTH), 0)
                }
                next
            }
            # Inline links and images: [text](destination "title")
            pos = 1
            while ((i = index(substr(line, pos), "](")) > 0) {
                b = pos + i - 1                           # index of "]"
                start = b + 2                             # first char after "]("
                if (b > 1 && substr(line, b - 1, 1) == "\\") { pos = start; continue }   # escaped "]"
                if (!find_opener(line, b)) { pos = start; continue }                    # no unescaped "["
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
