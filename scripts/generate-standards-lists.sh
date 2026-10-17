#!/bin/bash
# Generate the enumerable sections of agent configs from the standards/ tree,
# or (with --check) verify they are current and consistent.
#
# Every file in the repository that carries a generated region
# (<!-- BEGIN GENERATED: <id> --> ... <!-- END GENERATED: <id> -->) has that
# region's body re-rendered from the files actually present under standards/.
# Text outside the sentinels is never touched. Rendering rules live in
# scripts/lib/standards-lists.sh; optional descriptions and language triggers
# live in standards/catalog.tsv.
#
# Usage:
#   generate-standards-lists.sh [--root <dir>] [--check] [--quiet]
#
# Options:
#   --root <dir>  Repository root to operate on (default: this checkout).
#   --check       Validate only, never write. Emits PASS/WARN/FAIL lines and
#                 exits 1 on any FAIL:
#                   * a generated region whose content is stale
#                   * an agent config that references a standards file that
#                     does not exist on disk
#                   * an agent config or structure doc that omits a standards
#                     file that does exist
#                   * an agent config that lacks a generated region it is
#                     expected to carry (or carries it twice), or that does
#                     not exist at all
#                   * a file in a category directory that does not follow the
#                     <prefix>-NN_<name>.md naming convention, or two files
#                     sharing one <prefix>-NN identifier
#                   * a catalog row for a file that does not exist, or two
#                     rows for the same file
#                   * a language standard with no triggers column in the catalog
#   --quiet       Suppress per-file "unchanged" output in write mode.
#
# Temporary files live under <root>/.standards_tmp/ (per arch-02) and are
# removed on exit.
#
# Exit codes: 0 success / no drift, 1 drift or validation failure, 2 usage.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/standards-lists.sh
source "$SCRIPT_DIR/lib/standards-lists.sh"

ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK=false
QUIET=false

usage() {
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        --root)
            [ $# -ge 2 ] || { echo "ERROR: --root requires a directory" >&2; exit 2; }
            ROOT="$(cd "$2" 2>/dev/null && pwd)" || { echo "ERROR: no such directory: $2" >&2; exit 2; }
            shift 2
            ;;
        --check) CHECK=true; shift ;;
        --quiet) QUIET=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

STANDARDS_DIR="$ROOT/standards"
# Paths inside this repository are written relative to the repo root.
PATH_PREFIX="standards/"

if [ ! -d "$STANDARDS_DIR" ]; then
    echo "ERROR: no standards/ directory under $ROOT" >&2
    exit 2
fi

# The repo's own agent configs. Each must mention every standards file.
AGENT_CONFIGS=".cursorrules .github/copilot-instructions.md .gemini/GEMINI.md AGENTS.md CLAUDE.md"
# Hand-maintained indexes of the tree. Each must mention every standards file.
DOC_INDEXES="standards/README.md STRUCTURE.md docs/getting-started/project-structure.md"
# Files that may reference standards but are not required to be exhaustive.
REFERENCE_ONLY="standards/shared/core-standards.md"
# Generated regions each file must carry, as <path>:<id>[,<id>...]. Discovery
# alone would silently accept a region that was deleted wholesale; this is the
# manifest that --check and write mode validate against.
REQUIRED_REGIONS=".cursorrules:standards-list,language-detection \
.github/copilot-instructions.md:standards-list,language-detection \
.gemini/GEMINI.md:standards-list \
AGENTS.md:standards-list \
CLAUDE.md:standards-list \
standards/README.md:standards-list"

PASS_COUNT=0; WARN_COUNT=0; FAIL_COUNT=0
report_pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS $1 $2"; }
report_warn() { WARN_COUNT=$((WARN_COUNT + 1)); echo "WARN $1 $2"; }
report_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL $1 $2"; }

# All temporaries go under the repo's ignored .standards_tmp/ (arch-02). Keeping
# them inside ROOT also keeps replace_file's rename on the same filesystem.
STANDARDS_TMP="$ROOT/.standards_tmp"
mkdir -p "$STANDARDS_TMP" 2>/dev/null || { echo "ERROR: cannot create $STANDARDS_TMP" >&2; exit 2; }
TMP_DIR="$(mktemp -d "$STANDARDS_TMP/generate-standards-lists.XXXXXX")" \
    || { echo "ERROR: cannot create a work directory under $STANDARDS_TMP" >&2; exit 2; }
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Target discovery: every markdown-ish file under ROOT with a BEGIN sentinel.
# Uses git when ROOT is the top of a work tree (respects .gitignore, skips
# nested worktrees), else a pruned find. A ROOT nested inside a repository,
# such as a test fixture under .standards_tmp/, is ignored by git and so must
# take the find path. Paths are printed relative to ROOT.
# ---------------------------------------------------------------------------
root_is_git_toplevel() {
    local top
    top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || return 1
    [ "$top" = "$ROOT" ]
}

candidate_files() {
    if root_is_git_toplevel; then
        git -C "$ROOT" ls-files --cached --others --exclude-standard -z -- . 2>/dev/null \
            | tr '\0' '\n'
    else
        find "$ROOT" \( -name .git -o -name node_modules -o -name website \
                -o -name .standards_tmp -o -name .standards-pending \
                -o -name .worktrees -o -name .claude \) -prune \
             -o -type f -print 2>/dev/null \
            | sed "s|^$ROOT/||"
    fi
}

discover_targets() {
    local f
    candidate_files | while IFS= read -r f; do
        case "$f" in
            *.md|.cursorrules|*/.cursorrules) ;;
            *) continue ;;
        esac
        [ -f "$ROOT/$f" ] || continue
        if file_has_generated_regions "$ROOT/$f"; then
            printf '%s\n' "$f"
        fi
    done | LC_ALL=C sort -u
}

# Two kinds of reference are validated:
#   * a complete repository-relative path, "standards/<anything>.md", which
#     must exist at exactly that path (catches a misspelt directory, a wrong
#     category, or a typo anywhere in the name). The leading boundary keeps
#     ".standards/standards/..." consumer paths from being mis-captured.
#   * a bare basename, "<arch|lang|proc|sec>-NN_<name>.md" or the canonical
#     "core-standards.md", which may live in any category directory. Hyphens
#     are allowed in <name> so a typo such as lang-99_missing-standard.md is
#     still extracted and rejected.
STANDARDS_PATH_REGEX='(^|[^A-Za-z0-9_./-])standards/[A-Za-z0-9_./-]+\.md'
STANDARDS_BASENAME_REGEX='((arch|lang|proc|sec)-[0-9]+_[A-Za-z0-9_-]+|core-standards)\.md'

# standards_path_exists <standards/...md> — true when the path exists under ROOT.
standards_path_exists() {
    [ -f "$ROOT/$1" ]
}

# standards_basename_exists <basename> — true when standards/*/<basename> exists.
standards_basename_exists() {
    set -- "$STANDARDS_DIR"/*/"$1"
    [ -f "$1" ]
}

# standards_refs <file> — every reference in <file>, one per line, deduplicated:
# complete paths first (boundary stripped), then bare basenames.
standards_refs() {
    {
        grep -ohE "$STANDARDS_PATH_REGEX" "$1" 2>/dev/null | sed -E 's/^[^s]*(standards\/)/\1/'
        grep -ohE "$STANDARDS_BASENAME_REGEX" "$1" 2>/dev/null
    } | LC_ALL=C sort -u
}

# required_region_problems <relpath> — one line per required region that
# <relpath> does not carry exactly once: "<id> missing" or "<id> duplicated
# (N copies)". A duplicated block would be regenerated identically in both
# places and still pass the drift check, so it has to be rejected here.
# Prints nothing when the file is not in the manifest or is well-formed.
required_region_problems() {
    local entry ids id n
    for entry in $REQUIRED_REGIONS; do
        [ "${entry%%:*}" = "$1" ] || continue
        ids="${entry#*:}"
        for id in $(printf '%s' "$ids" | tr ',' ' '); do
            n=$(file_region_count "$ROOT/$1" "$id")
            if [ "${n:-0}" -eq 0 ]; then
                printf '%s missing\n' "$id"
            elif [ "$n" -gt 1 ]; then
                printf '%s duplicated (%s copies)\n' "$id" "$n"
            fi
        done
    done
}

# required_region_files — every manifest path, whether or not it exists. A
# missing one is a failure for the callers, never something to skip.
required_region_files() {
    local entry
    for entry in $REQUIRED_REGIONS; do
        printf '%s\n' "${entry%%:*}"
    done
}

# replace_file <src> <dest> — atomically replace <dest> with the contents of
# <src>, preserving <dest>'s mode. Stages the new content in TMP_DIR (under
# ROOT/.standards_tmp, same filesystem) and renames it into place, so a failed
# write (read-only tree, full disk) never truncates <dest>.
replace_file() {
    local src="$1" dest="$2" tmp
    tmp="$TMP_DIR/replace_$(basename "$dest").$$"
    if cp -p "$dest" "$tmp" 2>/dev/null \
        && cat "$src" > "$tmp" 2>/dev/null \
        && mv -f "$tmp" "$dest" 2>/dev/null; then
        return 0
    fi
    rm -f "$tmp" 2>/dev/null
    return 1
}

# unique_existing <space-separated relpaths...> — echo those present under ROOT.
unique_existing() {
    local f
    for f in "$@"; do
        [ -f "$ROOT/$f" ] && printf '%s\n' "$f"
    done
}

# ---------------------------------------------------------------------------
# Write mode
# ---------------------------------------------------------------------------
run_write() {
    local target out rc=0 changed=0 problems

    # A required region that was deleted wholesale has no sentinels left to
    # splice into, so it cannot be regenerated: fail loudly instead of
    # silently producing a config that will never list new standards.
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        if [ ! -f "$ROOT/$target" ]; then
            echo "ERROR: required agent config $target does not exist" >&2
            rc=1
            continue
        fi
        problems=$(required_region_problems "$target" | tr '\n' ';')
        if [ -n "$problems" ]; then
            echo "ERROR: $target has malformed required generated region(s): ${problems%;} — each must appear exactly once between its BEGIN/END GENERATED sentinels" >&2
            rc=1
        fi
    done <<EOF
$(required_region_files)
EOF
    if [ "$rc" -ne 0 ]; then
        echo "ERROR: preflight failed; no files were rewritten" >&2
        return "$rc"
    fi

    while IFS= read -r target; do
        [ -n "$target" ] || continue
        out="$TMP_DIR/$(echo "$target" | tr '/' '_')"
        if ! splice_generated_regions "$ROOT/$target" "$out" "$STANDARDS_DIR" "$PATH_PREFIX"; then
            echo "ERROR: left $target untouched" >&2
            rc=1
            continue
        fi
        if cmp -s "$ROOT/$target" "$out"; then
            [ "$QUIET" = true ] || echo "unchanged: $target"
        elif replace_file "$out" "$ROOT/$target"; then
            echo "updated:   $target"
            changed=$((changed + 1))
        else
            echo "ERROR: could not write $target (left untouched)" >&2
            rc=1
        fi
    done <<EOF
$(discover_targets)
EOF

    if [ "$rc" -eq 0 ]; then
        echo "Regenerated $changed file(s) from $STANDARDS_DIR. Verify with: $(basename "$0") --check"
    fi
    return "$rc"
}

# ---------------------------------------------------------------------------
# Check mode
# ---------------------------------------------------------------------------
check_drift() {
    local target out
    local found=0

    while IFS= read -r target; do
        [ -n "$target" ] || continue
        found=$((found + 1))
        out="$TMP_DIR/check_$(echo "$target" | tr '/' '_')"
        if ! splice_generated_regions "$ROOT/$target" "$out" "$STANDARDS_DIR" "$PATH_PREFIX" 2>"$TMP_DIR/err"; then
            report_fail "generated-region" "$target cannot be regenerated: $(tr '\n' ' ' < "$TMP_DIR/err")"
        elif cmp -s "$ROOT/$target" "$out"; then
            report_pass "generated-region" "$target is current"
        else
            report_fail "generated-region" "$target has stale generated content — run 'make generate-standards-lists' and commit the result"
        fi
    done <<EOF
$(discover_targets)
EOF

    if [ "$found" -eq 0 ]; then
        report_warn "generated-region" "no files with generated regions found under $ROOT"
    fi
}

check_required_regions() {
    local f problems
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if [ ! -f "$ROOT/$f" ]; then
            report_fail "required-file" "$f does not exist — every agent config in the manifest must be present"
            continue
        fi
        problems=$(required_region_problems "$f" | tr '\n' ';')
        if [ -z "$problems" ]; then
            report_pass "required-region" "$f carries every required generated region exactly once"
        else
            report_fail "required-region" "$f has malformed required generated region(s): ${problems%;} — each must appear exactly once; fix the BEGIN/END GENERATED sentinels and run 'make generate-standards-lists'"
        fi
    done <<EOF
$(required_region_files)
EOF
}

# check_naming — every .md in a category directory (other than README.md) must
# be <prefix>-NN_<name>.md. The generator only enumerates files that match, so
# a malformed name would otherwise be silently dropped from every list.
check_naming() {
    local cat prefix f base id ids bad="" dup=""
    for cat in $STANDARDS_LIST_CATEGORIES; do
        prefix=$(standards_category_prefix "$cat")
        [ -d "$STANDARDS_DIR/$cat" ] || continue
        ids=""
        for f in "$STANDARDS_DIR/$cat"/*.md; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            [ "$base" = "README.md" ] && continue
            if ! printf '%s\n' "$base" | grep -qE "^${prefix}-[0-9][0-9]_[A-Za-z0-9_]+\.md\$"; then
                bad="$bad $cat/$base"
                continue
            fi
            # <prefix>-NN must be unique within its category: two files sharing
            # an identifier would both be enumerated under the same number.
            id="${base%%_*}"
            case " $ids " in
                *" $id "*) dup="$dup $cat/$id" ;;
                *) ids="$ids $id" ;;
            esac
        done
    done
    if [ -z "$bad" ]; then
        report_pass "standards-naming" "every standards file follows <prefix>-NN_<name>.md"
    else
        report_fail "standards-naming" "file(s) in standards/ do not follow <prefix>-NN_<name>.md and are not enumerated:$bad"
    fi
    if [ -z "$dup" ]; then
        report_pass "standards-naming" "every <prefix>-NN identifier is unique within its category"
    else
        report_fail "standards-naming" "identifier(s) reused by more than one file:$dup"
    fi
}

check_references() {
    local f ref missing
    for f in "$@"; do
        missing=""
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            case "$ref" in
                standards/*) standards_path_exists "$ref" || missing="$missing $ref" ;;
                *)           standards_basename_exists "$ref" || missing="$missing $ref" ;;
            esac
        done <<EOF
$(standards_refs "$ROOT/$f")
EOF
        if [ -z "$missing" ]; then
            report_pass "standards-reference" "$f references only existing standards files"
        else
            report_fail "standards-reference" "$f references standards file(s) that do not exist:$missing"
        fi
    done
}

check_completeness() {
    local f rel omitted
    for f in "$@"; do
        omitted=""
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            grep -qF -- "$(basename "$rel")" "$ROOT/$f" || omitted="$omitted $(basename "$rel")"
        done <<EOF
$(list_standards_files "$STANDARDS_DIR")
EOF
        if [ -z "$omitted" ]; then
            report_pass "standards-complete" "$f mentions every standards file"
        else
            report_fail "standards-complete" "$f omits standards file(s):$omitted"
        fi
    done
}

check_catalog() {
    local catalog="$STANDARDS_DIR/$STANDARDS_CATALOG_FILE"
    local p rel stale="" uncatalogued=""

    if [ ! -f "$catalog" ]; then
        report_warn "catalog" "standards/$STANDARDS_CATALOG_FILE not found (descriptions fall back to H1 titles)"
        return
    fi

    while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ -f "$STANDARDS_DIR/$p" ] || stale="$stale $p"
    done <<EOF
$(standards_catalog_paths "$STANDARDS_DIR")
EOF
    if [ -z "$stale" ]; then
        report_pass "catalog" "every catalog row points at an existing standards file"
    else
        report_fail "catalog" "standards/$STANDARDS_CATALOG_FILE lists file(s) that do not exist:$stale"
    fi

    # Lookups take the first matching row, so a duplicate path would have its
    # later description/triggers silently ignored.
    local dups
    dups=$(standards_catalog_paths "$STANDARDS_DIR" | LC_ALL=C sort | uniq -d | tr '\n' ' ')
    if [ -z "$dups" ]; then
        report_pass "catalog" "every catalog path is unique"
    else
        report_fail "catalog" "standards/$STANDARDS_CATALOG_FILE has duplicate row(s) for: ${dups% }"
    fi

    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if [ -z "$(standards_catalog_field "$STANDARDS_DIR" "$rel" 2)" ]; then
            uncatalogued="$uncatalogued $rel"
        fi
    done <<EOF
$(list_standards_files "$STANDARDS_DIR")
EOF
    if [ -n "$uncatalogued" ]; then
        report_warn "catalog" "no catalog description (H1 title used) for:$uncatalogued"
    fi

    # Language-detection maps need real file triggers. The renderer falls back
    # to "<Language> source files" so a list is never empty, but shipping that
    # fallback is a failure, not a warning.
    local untriggered=""
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        if [ -z "$(standards_catalog_field "$STANDARDS_DIR" "$rel" 3)" ]; then
            untriggered="$untriggered $rel"
        fi
    done <<EOF
$(list_standards_files "$STANDARDS_DIR" languages)
EOF
    if [ -z "$untriggered" ]; then
        report_pass "catalog" "every language standard has catalog triggers"
    else
        report_fail "catalog" "language standard(s) without a triggers column in standards/$STANDARDS_CATALOG_FILE (detection maps would say '<Language> source files'):$untriggered"
    fi
}

run_check() {
    local targets configs indexes ref_set complete_set

    targets=$(discover_targets)
    # shellcheck disable=SC2086
    configs=$(unique_existing $AGENT_CONFIGS)
    # shellcheck disable=SC2086
    indexes=$(unique_existing $DOC_INDEXES)

    check_drift
    check_required_regions
    check_naming

    # Reference check: everything that enumerates or cites standards files,
    # plus the consumer base templates (which carry no lists but may cite files).
    local templates="" tpl
    for tpl in "$ROOT"/standards/agents/*/base-*.md; do
        [ -f "$tpl" ] && templates="$templates
${tpl#"$ROOT"/}"
    done
    # shellcheck disable=SC2086
    ref_set=$(printf '%s\n%s\n%s\n%s\n%s\n' "$targets" "$configs" "$indexes" \
        "$(unique_existing $REFERENCE_ONLY)" "$templates" \
        | LC_ALL=C sort -u | grep -v '^$' || true)
    # shellcheck disable=SC2086
    check_references $ref_set

    # Completeness check: agent configs, hand-maintained indexes, and any other
    # file that opted in by carrying a standards-list region.
    complete_set=$(printf '%s\n%s\n' "$configs" "$indexes" | LC_ALL=C sort -u | grep -v '^$' || true)
    while IFS= read -r t; do
        [ -n "$t" ] || continue
        if file_has_region "$ROOT/$t" standards-list; then
            complete_set=$(printf '%s\n%s\n' "$complete_set" "$t" | LC_ALL=C sort -u | grep -v '^$')
        fi
    done <<EOF
$targets
EOF
    # shellcheck disable=SC2086
    check_completeness $complete_set

    check_catalog

    echo ""
    echo "Summary: $PASS_COUNT pass, $WARN_COUNT warn, $FAIL_COUNT fail"
    [ "$FAIL_COUNT" -eq 0 ]
}

if [ "$CHECK" = true ]; then
    run_check
else
    run_write
fi
