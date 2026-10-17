#!/bin/bash
# Check: documentation lint — ADRs carry their required fields and relative
#        Markdown links resolve to a real file or directory inside the project.
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL (findings, empty scan, or self-test failure), 2=WARN
#
# Gate rules (proc-05 §7): the ADR validator and the link extractor self-test
# on every run against built-in fixtures that must trip them and must pass,
# and the check FAILs with "self-test failed" rather than reporting a clean
# result if either has rotted. A full scan that finds no Markdown at all FAILs
# and names the pathspec — every project is required to carry at least a
# README. A changed-file scope (`lint-standards.sh --since/--changed`) that
# contains no Markdown is a legitimate empty result and PASSes, saying so.
#
# Scope: candidate files come from scripts/lib/lint-files.sh — tracked files
# (or the runner's LINT_FILE_LIST when `--since/--changed` is in effect) plus
# untracked-but-not-ignored files, enumerated NUL-delimited by git, with the
# built-in directory exclusions and `.standards.yml` lint.exclude applied —
# filtered to any case of the .md extension. A Markdown filename containing a
# newline cannot be carried by the list and is reported as a finding rather
# than skipped. .standards-pending/ is always skipped.
#
# Code and comments are never content. An open HTML comment is consumed first
# (so a fence opener inside a comment is not a fence). Then, for the link scan,
# block-quote prefixes are removed so quoted fences and links are classified
# like top-level text; for the ADR checks, quoted lines are dropped entirely
# because a quoted example cannot satisfy the document's own structure. Fenced
# blocks (opener indented less than the current indented-code threshold,
# closed only by a fence of the same character and at least the same length),
# single-line HTML comments and indented code blocks (four columns past the
# innermost open list item's content column, or a tab, after a blank line,
# until a less-indented non-blank line; nested list items each raise the
# threshold) are removed. Inline code spans (any backtick run length) are
# removed per paragraph, so a span may continue onto later lines of the same
# paragraph and an unmatched backtick run stays literal text.
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
#               the value must start with a real calendar date (YYYY-MM-DD)
#   * Headings named Context, Decision and Consequences (any level; up to three
#     leading spaces as CommonMark allows)
#   For the heading form the value is the first non-blank line under the
#   heading, so an empty `## Status` section counts as missing.
#
# Link rules — inline `[text](target)`, `![alt](target)` and reference
# definitions `[label]: target` whose target is relative (no URL scheme, no
# leading `/`, not a bare `#anchor`) must resolve from the linking file's
# directory to a path that stays inside the project root (a `..` chain that
# climbs above the root is a broken link even when the host has such a file).
# Destinations follow CommonMark: optional whitespace after `(`, `<...>` may
# contain spaces, otherwise balanced parentheses are part of the target and
# the destination ends at whitespace (title) or the unbalanced `)`; a quoted
# or parenthesised title is parsed so a `)` inside it does not close the
# link; backslash escapes, percent-encoding and HTML character references are
# decoded. A `[` or `]` preceded by an odd number of backslashes is escaped
# and does not form a link; footnote definitions (`[^1]: …`) are not
# reference links. Fragments, query strings and titles are stripped.
#
# See standards/process/proc-01_documentation_standards.md §1 and §10.

PROJECT_ROOT="${1:-.}"
CHECK_NAME="doc-lint"

if ! PROJECT_ROOT="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd)"; then
    echo "WARN $CHECK_NAME Project root not found: ${1:-.}"
    exit 2
fi

LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../lib/lint-files.sh
source "$LINT_LIB"

MD_EXT_ERE='\.md$'

# ---------------------------------------------------------------------------
# Collect Markdown files (project-relative paths, one per line)
# ---------------------------------------------------------------------------
list_markdown_files() {
    lint_list_files "$PROJECT_ROOT" .standards-pending \
        | lint_strip_root "$PROJECT_ROOT" \
        | grep -iE -- "$MD_EXT_ERE" || true
}

# Markdown filenames that contain a newline: the list cannot carry them, so
# they are reported instead of being skipped.
list_unscannable_markdown() {
    lint_unscannable_files "$PROJECT_ROOT" .standards-pending \
        | grep -iE -- "$MD_EXT_ERE" || true
}

# ---------------------------------------------------------------------------
# Shared awk rules: consume HTML comments, handle block quotes, skip fenced and
# indented code
# ---------------------------------------------------------------------------
# Prepended to every awk program below. Lines inside code blocks or comments
# are consumed with `next`; everything else falls through to the program's own
# rules with $0 rewritten to the line's content. `-v adr_mode=1` drops quoted
# lines instead of unwrapping them. A fence opener or indented-code block sets
# para_break so the link scanner can end the current paragraph.
#
# All awk programs run under LC_ALL=C: they walk lines one position at a time,
# and in a UTF-8 locale macOS awk aborts ("multibyte conversion failure") when
# a single byte of a multibyte character is tested against a regex. Byte
# semantics are safe here because every cut point is an ASCII delimiter.
# shellcheck disable=SC2016  # awk program text, not shell expansion
AWK_SKIP_CODE='
    function indent_of(s,    n, i, c) {
        n = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == " ") n++
            else if (c == "\t") n += 4 - (n % 4)
            else break
        }
        return n
    }
    BEGIN { prev_blank = 1; code_indent = 4; depth = 0 }
    # An open multi-line HTML comment is consumed before anything else, so a
    # fence opener or heading inside it is never recognised.
    {
        if (in_comment) {
            k = index($0, "-->")
            if (k == 0) next
            $0 = substr($0, k + 3); in_comment = 0
        }
    }
    # Block quotes: for the ADR checks a quoted line is never the document'"'"'s
    # own structure, so it is dropped; for the link scan the markers are
    # removed and the content is classified like top-level text.
    {
        if (adr_mode) { if ($0 ~ /^ ? ? ?>/) next }
        else { while (match($0, /^ ? ? ?> ?/)) $0 = substr($0, RLENGTH + 1) }
    }
    # Fenced code: the opener may be indented up to three columns past the
    # innermost list item content column (deeper is indented code). Remember
    # the delimiter character and run length; only a fence of the same
    # character and at least that length, with nothing but whitespace after
    # it, closes the block.
    /^[ \t]*(```|~~~)/ {
        ind = indent_of($0)
        if (ind < code_indent) {
            match($0, /^[ \t]*/); rest = substr($0, RLENGTH + 1)
            ch = substr(rest, 1, 1); n = 0
            while (substr(rest, n + 1, 1) == ch) n++
            if (!in_fence) { in_fence = 1; fence_ch = ch; fence_len = n; prev_blank = 0; para_break = 1; next }
            if (ch == fence_ch && n >= fence_len && substr(rest, n + 1) ~ /^[[:space:]]*$/) {
                in_fence = 0; prev_blank = 1; next
            }
        }
    }
    in_fence { next }
    # HTML comments opened on this line: remove <!-- ... --> in place; an
    # unterminated opener drops the rest of the line and arms in_comment.
    {
        while ((k = index($0, "<!--")) > 0) {
            e = index(substr($0, k + 4), "-->")
            if (e == 0) { $0 = substr($0, 1, k - 1); in_comment = 1; break }
            $0 = substr($0, 1, k - 1) substr($0, k + 4 + e + 2)
        }
    }
    # Indented code: at least code_indent columns (four past the innermost
    # open list item content column, or four at top level), opened only after
    # a blank line (an indented line cannot interrupt a paragraph), running
    # through blank lines until a less-indented non-blank line. List items are
    # tracked as a stack so nested items each raise the threshold and a
    # 4-space continuation paragraph inside any item is content.
    {
        blank = ($0 ~ /^[[:space:]]*$/)
        ind = indent_of($0)
        if (in_indented) {
            if (blank || ind >= code_indent) next
            in_indented = 0
        } else if (prev_blank && !blank && ind >= code_indent) {
            in_indented = 1; para_break = 1; next
        }
        if (!blank) {
            if (ind < code_indent && match($0, /^[ \t]*([-*+]|[0-9]+[.)])([ ]+|\t)/)) {
                content = RLENGTH
                if (content - ind > 6) content = ind + 2   # 5+ spaces after marker: content starts after one space
                while (depth > 0 && mark[depth] >= ind) depth--   # close siblings and deeper items
                depth++; mark[depth] = ind; cont[depth] = content
            } else {
                while (depth > 0 && ind < cont[depth]) depth--     # a less-indented line closes the item
            }
            code_indent = (depth > 0 ? cont[depth] : 0) + 4
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

# Prints an ADR with comments, quoted lines, fenced and indented code removed.
strip_code_blocks() {
    LC_ALL=C awk -v adr_mode=1 "$AWK_SKIP_CODE"' { print }' "$1"
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

# True when $1 starts with a real calendar date (YYYY-MM-DD, Gregorian leap
# rules), optionally followed by a non-digit.
starts_with_valid_date() {
    local v="$1" y m d dim
    [[ "$v" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})([^0-9]|$) ]] || return 1
    y=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); d=$((10#${BASH_REMATCH[3]}))
    [ "$m" -ge 1 ] && [ "$m" -le 12 ] || return 1
    case "$m" in
        1|3|5|7|8|10|12) dim=31 ;;
        4|6|9|11) dim=30 ;;
        2) if [ $((y % 4)) -eq 0 ] && { [ $((y % 100)) -ne 0 ] || [ $((y % 400)) -eq 0 ]; }; then dim=29; else dim=28; fi ;;
    esac
    [ "$d" -ge 1 ] && [ "$d" -le "$dim" ]
}

# Prints the missing or invalid fields for one ADR (space-separated);
# empty = complete. Code, comments and quoted lines are removed first so an
# embedded example cannot satisfy the structure.
adr_missing_fields() {
    local file="$1" missing="" body status date
    body="$(strip_code_blocks "$file")"
    status="$(printf '%s\n' "$body" | adr_field_value status)"
    if ! printf '%s\n' "$status" \
        | grep -qiE '^(proposed|accepted|rejected|deprecated|superseded)([^a-z]|$)'; then
        missing="$missing Status"
    fi
    date="$(printf '%s\n' "$body" | adr_field_value date)"
    if ! starts_with_valid_date "$date"; then
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
        # 1 when the character at position k is preceded by an odd number of
        # backslashes (and is therefore escaped), else 0.
        function escaped(s, k,    c) {
            c = 0; k--
            while (k >= 1 && substr(s, k, 1) == "\\") { c++; k-- }
            return c % 2
        }
        # Remove the first unescaped "#" or "?" and everything after it,
        # honouring backslash escapes (a "\#" is part of the path) and
        # skipping character references (the "#" in "&#38;" is not a fragment).
        function strip_fragment(t,    i, L, c) {
            L = length(t); i = 1
            while (i <= L) {
                c = substr(t, i, 1)
                if (c == "\\") { i += 2; continue }
                if (c == "&" && match(substr(t, i), /^&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);/)) { i += RLENGTH; continue }
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
        function hexval(h,    v, i) {
            v = 0
            for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
            return v
        }
        # UTF-8 encode a code point (bytes; LC_ALL=C keeps them intact).
        function utf8(cp) {
            if (cp < 128) return sprintf("%c", cp)
            if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
            if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
            return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
        }
        # Decode HTML character references: the XML named set plus numeric
        # decimal/hex forms. Unknown names stay literal.
        function decode_entities(t,    out, i, L, rest, name) {
            out = ""; L = length(t); i = 1
            while (i <= L) {
                if (substr(t, i, 1) == "&") {
                    rest = substr(t, i)
                    if (match(rest, /^&(#[0-9]+|#[xX][0-9a-fA-F]+|[A-Za-z][A-Za-z0-9]*);/)) {
                        name = substr(rest, 2, RLENGTH - 2)
                        if (name ~ /^#[xX]/) { out = out utf8(hexval(substr(name, 3))); i += RLENGTH; continue }
                        if (name ~ /^#/) { out = out utf8(substr(name, 2) + 0); i += RLENGTH; continue }
                        if (name == "amp") { out = out "&"; i += RLENGTH; continue }
                        if (name == "lt") { out = out "<"; i += RLENGTH; continue }
                        if (name == "gt") { out = out ">"; i += RLENGTH; continue }
                        if (name == "quot") { out = out "\""; i += RLENGTH; continue }
                        if (name == "apos") { out = out "\047"; i += RLENGTH; continue }
                        if (name == "nbsp") { out = out " "; i += RLENGTH; continue }
                    }
                }
                out = out substr(t, i, 1); i++
            }
            return out
        }
        # Decode %XX percent-encoding (any byte, so UTF-8 sequences survive).
        function percent_decode(t,    out, i, L, h) {
            out = ""; L = length(t); i = 1
            while (i <= L) {
                if (substr(t, i, 1) == "%" && i + 2 <= L) {
                    h = substr(t, i + 1, 2)
                    if (h ~ /^[0-9a-fA-F][0-9a-fA-F]$/) { out = out sprintf("%c", hexval(h)); i += 3; continue }
                }
                out = out substr(t, i, 1); i++
            }
            return out
        }
        # angle=1: the destination came from <...> and may contain spaces.
        function emit(target, angle) {
            if (!angle) sub(/[[:space:]].*$/, "", target)   # drop link title
            target = percent_decode(decode_entities(unescape(strip_fragment(target))))
            if (target == "") return
            if (target ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) return   # URL scheme
            if (target ~ /^\//) return                         # site-absolute
            if (target ~ /\{\{/) return                        # template var
            print target
        }
        # Drop inline code spans from a whole paragraph (lines joined with
        # "\n"). A span opens with a run of N backticks and closes at the next
        # run of exactly N, possibly on a later line; a run with no matching
        # close is literal text and stays. "\`" is a literal backtick.
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
        function find_opener(s, b,    k, depth2, c) {
            depth2 = 0
            for (k = b - 1; k >= 1; k--) {
                c = substr(s, k, 1)
                if ((c == "[" || c == "]") && escaped(s, k)) continue
                if (c == "]") depth2++
                else if (c == "[") { if (depth2 == 0) return k; depth2-- }
            }
            return 0
        }
        # Given rest starting at the first character after the destination,
        # skip whitespace and an optional quoted/parenthesised title, then
        # return the 1-based index in rest of the link-closing ")" or 0.
        function close_after_title(rest,    j, n, q, closer, c) {
            n = length(rest); j = 1
            while (j <= n && (substr(rest, j, 1) == " " || substr(rest, j, 1) == "\t")) j++
            if (j > n) return 0
            q = substr(rest, j, 1)
            if (q == ")") return j
            if (q == "\"" || q == "\047" || q == "(") {
                closer = (q == "(") ? ")" : q
                j++
                while (j <= n) {
                    c = substr(rest, j, 1)
                    if (c == "\\") { j += 2; continue }
                    if (c == closer) break
                    j++
                }
                if (j > n) return 0
                j++
                while (j <= n && (substr(rest, j, 1) == " " || substr(rest, j, 1) == "\t")) j++
                if (j <= n && substr(rest, j, 1) == ")") return j
                return 0
            }
            # Not a well-formed title: fall back to the next ")".
            j = index(rest, ")")
            return j
        }
        # Parse one destination starting right after "](". Sets DEST and
        # DEST_ANGLE; returns the number of characters consumed up to and
        # including the closing ")" of the link, or 0 if the link does not
        # close on this line.
        function parse_dest(rest,    lead, n, j, k, c, pdepth) {
            lead = 0
            while (substr(rest, lead + 1, 1) == " " || substr(rest, lead + 1, 1) == "\t") lead++
            if (lead) rest = substr(rest, lead + 1)
            n = length(rest)
            if (substr(rest, 1, 1) == "<") {
                j = index(rest, ">")
                if (j == 0) return 0
                DEST = substr(rest, 2, j - 2); DEST_ANGLE = 1
                k = close_after_title(substr(rest, j + 1))
                if (k == 0) return 0
                return lead + j + k
            }
            pdepth = 0; j = 1
            while (j <= n) {
                c = substr(rest, j, 1)
                if (c == "\\") { j += 2; continue }
                if (c == "(") pdepth++
                else if (c == ")") { if (pdepth == 0) break; pdepth-- }
                else if (c == " " || c == "\t") break
                j++
            }
            if (j > n) return 0
            DEST = substr(rest, 1, j - 1); DEST_ANGLE = 0
            if (c == ")") return lead + j
            k = close_after_title(substr(rest, j))
            if (k == 0) return 0
            return lead + j + k - 1
        }
        # Scan one code-span-free line for reference definitions and inline
        # links / images.
        function scan_line(line,    rest, j, pos, i, b, start, used) {
            # Reference-style definition: [label]: target  (not footnotes [^1]:)
            if (match(line, /^[[:space:]]*\[[^]^][^]]*\]:[[:space:]]*/)) {
                rest = substr(line, RLENGTH + 1)
                if (substr(rest, 1, 1) == "<") {
                    j = index(rest, ">")
                    if (j > 1) emit(substr(rest, 2, j - 2), 1)
                } else if (match(rest, /^[^[:space:]]+/)) {
                    emit(substr(rest, 1, RLENGTH), 0)
                }
                return
            }
            # Inline links and images: [text](destination "title")
            pos = 1
            while ((i = index(substr(line, pos), "](")) > 0) {
                b = pos + i - 1                           # index of "]"
                start = b + 2                             # first char after "]("
                if (escaped(line, b)) { pos = start; continue }           # escaped "]"
                if (!find_opener(line, b)) { pos = start; continue }      # no unescaped "["
                used = parse_dest(substr(line, start))
                if (used == 0) { pos = start; continue }  # unterminated; keep scanning
                emit(DEST, DEST_ANGLE)
                pos = start + used
            }
        }
        # A paragraph is buffered until a blank line, a code block or EOF, then
        # code spans are removed across the whole paragraph and each remaining
        # line is scanned.
        function flush_para(    text, nl, i, plines) {
            if (para == "") return
            text = strip_code_spans(para)
            nl = split(text, plines, "\n")
            for (i = 1; i <= nl; i++) scan_line(plines[i])
            para = ""
        }
        {
            if (para_break) { flush_para(); para_break = 0 }
            if ($0 ~ /^[[:space:]]*$/) { flush_para(); next }
            para = (para == "") ? $0 : para "\n" $0
        }
        END { flush_para() }
    ' "$1"
}

# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------
# Prints the lexically normalised project-relative path for <dir>/<target>,
# or returns 1 when the path climbs above the project root.
resolve_in_project() {
    local path="$1" part
    local -a parts out=()
    IFS='/' read -r -a parts <<< "$path"
    for part in "${parts[@]}"; do
        case "$part" in
            ''|.) ;;
            ..) [ "${#out[@]}" -gt 0 ] || return 1
                unset "out[$((${#out[@]} - 1))]" ;;
            *)  out+=("$part") ;;
        esac
    done
    local IFS='/'
    printf '%s' "${out[*]}"
}

# True when <rel-dir>/<target> exists inside the project.
link_resolves() {
    local rel_dir="$1" target="$2" norm
    norm="$(resolve_in_project "$rel_dir/$target")" || return 1
    [ -e "$PROJECT_ROOT/$norm" ]
}

# ---------------------------------------------------------------------------
# Self-test (proc-05 §7.1): the detectors must trip on a rejecting fixture and
# stay quiet on a clean one, or the check refuses to report.
# ---------------------------------------------------------------------------
self_test() {
    local dir out
    dir="$(mktemp -d "${TMPDIR:-/tmp}/doc-lint-selftest.XXXXXX")" || return 1
    # shellcheck disable=SC2064  # expand $dir now; it is fixed for this call
    trap "rm -rf '$dir'" RETURN

    cat > "$dir/bad-adr.md" <<'EOF'
# ADR 0009: Broken

- **Status:** Maybe
- **Date:** 2026-02-31

```markdown
- **Status:** Accepted
- **Date:** 2026-01-01
## Context
## Decision
## Consequences
```

> - **Status:** Accepted
> ## Decision

<!-- ## Decision -->

## Context
EOF
    out="$(adr_missing_fields "$dir/bad-adr.md")"
    if [ "$out" != "Status Date Decision Consequences" ]; then
        echo "rejecting ADR fixture reported '$out' instead of 'Status Date Decision Consequences'"; return 1
    fi

    cat > "$dir/good-adr.md" <<'EOF'
# ADR 0010: Fine

- **Status:** Accepted
- **Date:** 2026-10-17

## Context

## Decision

## Consequences
EOF
    out="$(adr_missing_fields "$dir/good-adr.md")"
    if [ -n "$out" ]; then echo "clean ADR fixture reported missing '$out'"; return 1; fi

    cat > "$dir/links.md" <<'EOF'
# Links

Prose [one](missing-one.md) and `[code](ignored.md)` and [two](<missing two.md> "t").

```md
[fenced](ignored.md)
```

    [indented](ignored.md)

<!-- [commented](ignored.md) -->
A span that `continues
[across](ignored.md) lines` ends here, and a stray ` then [three](missing-three.md).

<!--
```md
-->
[four](missing-four.md)

[five]: missing-five.md
[^1]: footnote, not a link
EOF
    out="$(extract_relative_links "$dir/links.md" | tr '\n' '|')"
    if [ "$out" != "missing-one.md|missing two.md|missing-three.md|missing-four.md|missing-five.md|" ]; then
        echo "link fixture extracted '$out' instead of 'missing-one.md|missing two.md|missing-three.md|missing-four.md|missing-five.md|'"; return 1
    fi

    if resolve_in_project "docs/../../etc/passwd" >/dev/null; then
        echo "path resolver accepted a target above the project root"; return 1
    fi
    if [ "$(resolve_in_project "docs/guides/../specs/./x.md")" != "docs/specs/x.md" ]; then
        echo "path resolver normalised docs/guides/../specs/./x.md incorrectly"; return 1
    fi
    return 0
}

if ! self_test_msg="$(self_test)"; then
    echo "FAIL $CHECK_NAME self-test failed (detector rot, refusing to report): $self_test_msg"
    exit 1
fi

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
    rel_dir="$(dirname "$rel")"

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
        if ! link_resolves "$rel_dir" "$target"; then
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

UNSCANNABLE="$(list_unscannable_markdown)"
UNSCANNABLE_COUNT=0
if [ -n "$UNSCANNABLE" ]; then
    UNSCANNABLE_COUNT=$(printf '%s\n' "$UNSCANNABLE" | grep -c .)
fi

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
if [ "$FILE_COUNT" -eq 0 ] && [ "$UNSCANNABLE_COUNT" -eq 0 ]; then
    if lint_scope_is_changed; then
        echo "PASS $CHECK_NAME No Markdown files in the changed-file scope (--since/--changed) — nothing to lint"
        exit 0
    fi
    # proc-05 §7.2: an empty full scan is a configuration error, not a clean result.
    echo "FAIL $CHECK_NAME No Markdown files matched '*.md' (any case) under $PROJECT_ROOT — every project carries at least a README.md; check the working directory or the ignore rules"
    exit 1
fi

if [ "$ADR_BAD_COUNT" -eq 0 ] && [ "$BROKEN_COUNT" -eq 0 ] && [ "$UNSCANNABLE_COUNT" -eq 0 ]; then
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
if [ "$UNSCANNABLE_COUNT" -gt 0 ]; then
    MSG="${MSG}${UNSCANNABLE_COUNT} Markdown file(s) cannot be scanned because the name contains a newline: $(printf '%s\n' "$UNSCANNABLE" | head -3 | tr '\n' ' ')— rename them; "
fi
echo "FAIL $CHECK_NAME ${MSG%; } — fix the link target or add the missing ADR field, then re-run lint-standards"
exit 1
