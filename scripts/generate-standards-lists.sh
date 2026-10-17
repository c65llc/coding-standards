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
#                     expected to carry
#                   * a catalog row for a file that does not exist
#   --quiet       Suppress per-file "unchanged" output in write mode.
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

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/generate-standards-lists.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Target discovery: every markdown-ish file under ROOT with a BEGIN sentinel.
# Uses git when available (respects .gitignore, skips nested worktrees), else
# a pruned find. Paths are printed relative to ROOT.
# ---------------------------------------------------------------------------
candidate_files() {
    if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
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

# Pattern for a standards-file reference: an optional category directory
# followed by a prefixed filename (arch-NN_*.md, lang-NN_*.md, ...) or the
# shared core-standards.md. grep -o is leftmost-longest, so a reference
# written with its directory is captured together with that directory.
STANDARDS_REF_REGEX='((architecture|languages|process|security|shared)/)?((arch|lang|proc|sec)-[0-9]+_[A-Za-z0-9_]+|core-standards)\.md'

# standards_file_exists <ref> — true when <ref> resolves to a standards file.
# A directory-qualified ref (languages/lang-01_python_standards.md) must exist
# at exactly that path; a bare basename may live in any category directory.
standards_file_exists() {
    case "$1" in
        */*) [ -f "$STANDARDS_DIR/$1" ] ;;
        *)
            set -- "$STANDARDS_DIR"/*/"$1"
            [ -f "$1" ]
            ;;
    esac
}

# missing_required_regions <relpath> — prints the region ids <relpath> is
# required to carry but does not, one per line. Prints nothing when the file
# is not in the manifest or carries every required region.
missing_required_regions() {
    local entry ids id
    for entry in $REQUIRED_REGIONS; do
        [ "${entry%%:*}" = "$1" ] || continue
        ids="${entry#*:}"
        for id in $(printf '%s' "$ids" | tr ',' ' '); do
            file_has_region "$ROOT/$1" "$id" || printf '%s\n' "$id"
        done
    done
}

# required_region_files — manifest paths that exist under ROOT.
required_region_files() {
    local entry
    for entry in $REQUIRED_REGIONS; do
        [ -f "$ROOT/${entry%%:*}" ] && printf '%s\n' "${entry%%:*}"
    done
    return 0
}

# replace_file <src> <dest> — atomically replace <dest> with the contents of
# <src>, preserving <dest>'s mode. Writes to a sibling temp file and renames,
# so a failed write (read-only tree, full disk) never truncates <dest>.
replace_file() {
    local src="$1" dest="$2" tmp
    tmp="$(dirname "$dest")/.$(basename "$dest").tmp.$$"
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
    local target out rc=0 changed=0 missing

    # A required region that was deleted wholesale has no sentinels left to
    # splice into, so it cannot be regenerated: fail loudly instead of
    # silently producing a config that will never list new standards.
    while IFS= read -r target; do
        [ -n "$target" ] || continue
        missing=$(missing_required_regions "$target" | tr '\n' ' ')
        if [ -n "$missing" ]; then
            echo "ERROR: $target is missing required generated region(s): ${missing% }— restore the BEGIN/END GENERATED sentinels" >&2
            rc=1
        fi
    done <<EOF
$(required_region_files)
EOF

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
    local f missing
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        missing=$(missing_required_regions "$f" | tr '\n' ' ')
        if [ -z "$missing" ]; then
            report_pass "required-region" "$f carries every required generated region"
        else
            report_fail "required-region" "$f is missing required generated region(s): ${missing% }— restore the BEGIN/END GENERATED sentinels and run 'make generate-standards-lists'"
        fi
    done <<EOF
$(required_region_files)
EOF
}

check_references() {
    local f ref missing
    for f in "$@"; do
        missing=""
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            standards_file_exists "$ref" || missing="$missing $ref"
        done <<EOF
$(grep -ohE "$STANDARDS_REF_REGEX" "$ROOT/$f" 2>/dev/null | LC_ALL=C sort -u)
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
