#!/bin/bash
# scripts/lib/migrate.sh — pre-1.2 consumer migration (#184).
#
# Source this file; do not execute it directly.
#
# A consumer installed before the 1.2 safe-setup carries hand-rolled agent
# configs copied from the old templates. They cite standards paths that no
# release has carried since the #21 renumbering (00_project_standards_… →
# arch-01_…, 03_python_standards.md → lang-01_…, 12_* → proc-01_…), the v1.0
# .cursorrules cites arch-03 (deleted in #40), Codex still reads a .codexrc
# (it now reads AGENTS.md), and there is no .standards.yml and no
# .standards-checksums. sync-standards sees a file with no assembly header
# and no stored hash, calls it "manually created" and skips it, so the dead
# references never go away.
#
# setup.sh --migrate consumes docs/reference/renamed-files.md (the table
# between the BEGIN/END RENAME MAP markers) to rewrite those references in
# place, converts .codexrc to AGENTS.md, and lets the regular safe setup stage
# the assembled configs and write checksums. doctor.sh and sync-standards.sh
# use pre12_shape to recognise the shape and point at that one command.
#
# Globals set by the rewriters for the caller's report and MERGE_PLAN:
#   MIGRATE_REWRITES    number of references rewritten so far
#   MIGRATE_DROPPED     lines "<file>:<line>: <old>" removed because they only
#                       cited a removed standard
#   MIGRATE_UNRESOLVED  lines "<file>:<line>: <old>" that still cite a removed
#                       standard (running text: left for a manual decision)
#   MIGRATE_NOTES       Markdown bullets for the MERGE_PLAN Migration section

MIGRATE_REWRITES=0
MIGRATE_DROPPED=""
MIGRATE_UNRESOLVED=""
MIGRATE_NOTES=""

# Project-relative agent config paths the migration inspects, in report order.
MIGRATE_AGENT_CONFIGS="CLAUDE.md .cursorrules .github/copilot-instructions.md .gemini/GEMINI.md AGENTS.md .aider-instructions.md .aiderrc .codexrc"

# Models the old .aiderrc templates pinned. A consumer's `model =` line naming
# one of these is template residue and is dropped; any other value is the
# project's own choice and stays.
MIGRATE_TEMPLATE_MODELS='claude-3-5-sonnet-20241022|claude-sonnet-4-20250514|claude-sonnet-4-6'

# Append one line to a newline-delimited global (bash 3.2: no namerefs).
# $1 = variable name, $2 = line
_migrate_append() {
    local cur
    eval "cur=\${$1}"
    if [ -z "$cur" ]; then
        eval "$1=\$2"
    else
        eval "$1=\"\$cur
\$2\""
    fi
}

# ---------------------------------------------------------------------------
# rename_map_path <standards_dir> <script_dir>
#
# Prints the path of docs/reference/renamed-files.md: the consumer's
# .standards/ checkout first, then the repo the running script belongs to.
# Returns 1 (prints nothing) when neither has it.
# ---------------------------------------------------------------------------
rename_map_path() {
    local c
    for c in "${1:-}/docs/reference/renamed-files.md" "${2:-}/../docs/reference/renamed-files.md"; do
        case "$c" in /docs/*|/../*) continue ;; esac
        if [ -f "$c" ]; then
            printf '%s\n' "$c"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# load_rename_map <map_file>
#
# Prints "<old path><TAB><new path>" for every row between the BEGIN/END
# RENAME MAP markers; a removed file prints "-" as its new path.
# ---------------------------------------------------------------------------
load_rename_map() {
    local map="$1"
    [ -f "$map" ] || return 1
    awk '
        /BEGIN RENAME MAP/ { inmap = 1; next }
        /END RENAME MAP/   { inmap = 0; next }
        !inmap || $0 !~ /^\|/ { next }
        {
            split($0, c, "|")
            old = c[2]; new = c[3]
            gsub(/[` ]/, "", old); gsub(/[` ]/, "", new)
            if (old == "" || old ~ /^-+$/ || tolower(old) == "oldpath") next
            if (new ~ /removed/) new = "-"
            printf "%s\t%s\n", old, new
        }
    ' "$map"
}

# load_rename_basenames <map_file>
# Like load_rename_map but on file names: "<old base><TAB><new base or ->".
# Renames stay inside their category directory, so the file name is the unit
# the rewriter swaps; the config's own prefix (standards/…, .standards/…, or
# none at all, as in .codexrc) is left as it was.
load_rename_basenames() {
    load_rename_map "$1" | awk -F'\t' '{
        o = $1; sub(/.*\//, "", o)
        n = $2; if (n != "-") sub(/.*\//, "", n)
        printf "%s\t%s\n", o, n
    }'
}

# Escape a file name for use in an ERE (only "." needs it here).
_migrate_re_escape() {
    printf '%s' "$1" | sed 's/\./\\./g'
}

# ---------------------------------------------------------------------------
# dead_refs_in_file <file> <map_file>
#
# Prints each old file name the file cites (one per line, map order). A name
# counts only when the character before it is not part of a longer name, so
# "lang-03_kotlin_standards.md" never matches a row for "03_kotlin_…".
# ---------------------------------------------------------------------------
dead_refs_in_file() {
    local file="$1" map="$2" old new
    [ -f "$file" ] || return 0
    while IFS="$(printf '\t')" read -r old new; do
        [ -n "$old" ] || continue
        if grep -qE "(^|[^A-Za-z0-9_-])$(_migrate_re_escape "$old")" "$file" 2>/dev/null; then
            printf '%s\n' "$old"
        fi
    done <<EOF
$(load_rename_basenames "$map")
EOF
}

# ---------------------------------------------------------------------------
# pre12_shape <project_root> <map_file>
#
# Recognises a pre-1.2 install: no .standards-checksums, and at least one of
#   - an agent config cites renamed or removed standards paths
#   - a .codexrc is present (Codex reads AGENTS.md)
#   - a legacy .standards-config exists and no .standards.yml
# Prints one reason per line and returns 0 when the shape matches; prints
# nothing and returns 1 otherwise (a 1.2+ install, or a greenfield project).
# ---------------------------------------------------------------------------
pre12_shape() {
    local root="$1" map="${2:-}" rel n reasons=""
    [ -f "$root/.standards-checksums" ] && return 1
    if [ -n "$map" ] && [ -f "$map" ]; then
        for rel in $MIGRATE_AGENT_CONFIGS; do
            [ -f "$root/$rel" ] || continue
            n=$(dead_refs_in_file "$root/$rel" "$map" | wc -l | tr -d ' ')
            [ "$n" -gt 0 ] || continue
            reasons="${reasons:+$reasons
}$rel cites $n renamed or removed standards path(s)"
        done
    fi
    if [ -f "$root/.codexrc" ]; then
        reasons="${reasons:+$reasons
}.codexrc present (Codex reads AGENTS.md)"
    fi
    if [ -f "$root/.standards-config" ] && [ ! -f "$root/.standards.yml" ]; then
        reasons="${reasons:+$reasons
}legacy .standards-config present, no .standards.yml"
    fi
    [ -n "$reasons" ] || return 1
    printf '%s\n' "$reasons"
}

# ---------------------------------------------------------------------------
# _migrate_commit <file> <rel> <new_content_file> <dry_run> <what> [backup]
#
# Replaces <file> with <new_content_file> when they differ. With backup=true
# (the default) the original is kept as <file>.pre-standards-setup, which
# setup.sh already gitignores. In dry-run mode only reports. Removes the temp
# file either way. Returns 0 when the file changed (or would), 1 if identical.
# ---------------------------------------------------------------------------
_migrate_commit() {
    local file="$1" rel="$2" new="$3" dry_run="$4" what="$5" backup="${6:-true}"
    if cmp -s "$file" "$new" 2>/dev/null; then
        rm -f "$new"
        return 1
    fi
    local kept=""
    [ "$backup" = true ] && kept="; original kept as $rel.pre-standards-setup"
    if [ "$dry_run" = true ]; then
        echo "  [dry-run] Would rewrite $rel ($what$kept)"
        rm -f "$new"
        return 0
    fi
    [ "$backup" = true ] && cp "$file" "$file.pre-standards-setup"
    # cat > keeps the destination's inode and mode (a symlinked config is
    # written through, not replaced by a regular file).
    cat "$new" > "$file"
    rm -f "$new"
    echo "   ✅ $rel rewritten ($what$kept)"
    return 0
}

# ---------------------------------------------------------------------------
# rewrite_dead_refs <file> <map_file> <dry_run> [project_root] [backup]
#
# Rewrites every renamed standards file name in <file> to its current name.
# A line that only cites a removed standard (a list item or comment whose
# subject is that file, with no other .md reference) is dropped and recorded
# in MIGRATE_DROPPED; a removed standard cited in running text is left in
# place and recorded in MIGRATE_UNRESOLVED for the MERGE_PLAN.
# ---------------------------------------------------------------------------
rewrite_dead_refs() {
    local file="$1" map="$2" dry_run="${3:-false}" root="${4:-}" backup="${5:-true}"
    [ -f "$file" ] || return 0
    local rel="$file"
    [ -n "$root" ] && rel="${file#"$root"/}"

    local tmpmap tmpout report
    tmpmap=$(mktemp); tmpout=$(mktemp); report=$(mktemp)
    load_rename_basenames "$map" > "$tmpmap"
    if [ ! -s "$tmpmap" ]; then
        rm -f "$tmpmap" "$tmpout" "$report"
        return 0
    fi

    awk -v report="$report" '
        function esc_re(s) { gsub(/\./, "\\.", s); return s }
        # Replace whole-name occurrences of old with new; a match glued to a
        # longer name (lang-03_kotlin… for 03_kotlin…) is left alone.
        function replace_name(line, old, new,    out, rest, pos, pre) {
            out = ""; rest = line
            while ((pos = index(rest, old)) > 0) {
                pre = (pos > 1) ? substr(rest, pos - 1, 1) : ""
                if (pre == "" || pre !~ /[A-Za-z0-9_-]/) {
                    out = out substr(rest, 1, pos - 1) new
                    hits++
                } else {
                    out = out substr(rest, 1, pos - 1 + length(old))
                }
                rest = substr(rest, pos + length(old))
            }
            return out rest
        }
        FNR == NR { split($0, p, "\t"); n++; old[n] = p[1]; new[n] = p[2]; next }
        {
            line = $0
            for (i = 1; i <= n; i++) {
                if (index(line, old[i]) == 0) continue
                if (new[i] == "-") {
                    # Removed standard. Drop the line only when it is a list
                    # item or comment about that file and cites nothing else.
                    probe = line; mdrefs = gsub(/\.md/, "&", probe)
                    if (mdrefs == 1 && line ~ ("^[[:space:]]*([-*+]|#+)[[:space:]]*(`|\\*\\*)?[[:space:]]*([./A-Za-z0-9_-]*/)?" esc_re(old[i]) "`?")) {
                        printf "DROPPED\t%d\t%s\n", FNR, old[i] > report
                        next
                    }
                    printf "UNRESOLVED\t%d\t%s\n", FNR, old[i] > report
                    continue
                }
                hits = 0
                line = replace_name(line, old[i], new[i])
                count[i] += hits
            }
            print line
        }
        END {
            for (i = 1; i <= n; i++)
                if (count[i] > 0) printf "REPLACED\t%s\t%s\t%d\n", old[i], new[i], count[i] > report
        }
    ' "$tmpmap" "$file" > "$tmpout"
    rm -f "$tmpmap"

    local kind a b c changed=false
    while IFS="$(printf '\t')" read -r kind a b c; do
        case "$kind" in
            REPLACED)
                echo "   $rel: $a → $b ($c)"
                MIGRATE_REWRITES=$((MIGRATE_REWRITES + c))
                changed=true
                ;;
            DROPPED)
                echo "   $rel:$a dropped — the line only cited $b, which was removed"
                _migrate_append MIGRATE_DROPPED "$rel:$a: $b"
                changed=true
                ;;
            UNRESOLVED)
                echo "   $rel:$a cites $b, which was removed — left in place for review"
                _migrate_append MIGRATE_UNRESOLVED "$rel:$a: $b"
                ;;
        esac
    done < "$report"
    rm -f "$report"

    if [ "$changed" = true ]; then
        _migrate_commit "$file" "$rel" "$tmpout" "$dry_run" "dead references" "$backup" || true
    else
        rm -f "$tmpout"
    fi
    return 0
}

# ---------------------------------------------------------------------------
# fix_legacy_tiers <file> <dry_run> [project_root] [backup]
#
# The old .aiderrc and .codexrc templates carried 100/90/80 coverage tiers;
# core-standards.md has had a 95% floor (domain 100%) since 1.0. Raises the
# 90/80 tiers to 95 and drops a `model =` line that pins one of the models the
# templates shipped (MIGRATE_TEMPLATE_MODELS) together with its
# "# Model configuration" caption; a project-chosen model stays.
# ---------------------------------------------------------------------------
fix_legacy_tiers() {
    local file="$1" dry_run="${2:-false}" root="${3:-}" backup="${4:-true}"
    [ -f "$file" ] || return 0
    local rel="$file"
    [ -n "$root" ] && rel="${file#"$root"/}"
    local tmpout
    tmpout=$(mktemp)
    sed -E 's/(Application|Infrastructure)([A-Za-z /]*): (90|80)%\+/\1\2: 95%+/g' "$file" \
        | awk -v models="^model = ($MIGRATE_TEMPLATE_MODELS)[[:space:]]*\$" '
            { lines[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    if (lines[i] ~ models) continue
                    if (lines[i] ~ /^# Model configuration[[:space:]]*$/ && i < NR && lines[i + 1] ~ models) continue
                    print lines[i]
                }
            }
        ' > "$tmpout"
    if grep -qE "^model = ($MIGRATE_TEMPLATE_MODELS)[[:space:]]*$" "$file"; then
        echo "   $rel: dropped the template-pinned model line (Aider takes the model from its own config)"
    fi
    if grep -qE '(Application|Infrastructure)[A-Za-z /]*: (90|80)%\+' "$file"; then
        echo "   $rel: coverage tiers 90%/80% → 95% floor (core-standards.md; domain stays 100%)"
    fi
    _migrate_commit "$file" "$rel" "$tmpout" "$dry_run" "coverage tiers / model" "$backup" || true
    return 0
}

# ---------------------------------------------------------------------------
# convert_codexrc <project_root> <map_file> <dry_run> <pending_dir>
#
# OpenAI Codex reads AGENTS.md; the pre-#40 template was a comment-style
# .codexrc. Converts it to Markdown (comment markers stripped, `##` headings
# kept), rewrites dead references and legacy tiers in the result, and
#   - with no AGENTS.md: writes AGENTS.md and keeps the original as
#     .codexrc.pre-standards-setup (the regular setup then stages the
#     assembled AGENTS.md beside it for /merge-standards);
#   - with an AGENTS.md: stages the conversion as
#     <pending_dir>/AGENTS.md.from-codexrc and leaves .codexrc in place.
# Records what it did in MIGRATE_NOTES.
# ---------------------------------------------------------------------------
convert_codexrc() {
    local root="$1" map="${2:-}" dry_run="${3:-false}" pending_dir="$4"
    local src="$root/.codexrc"
    [ -f "$src" ] || return 0

    local tmp
    tmp=$(mktemp)
    {
        echo "# AGENTS.md"
        echo ""
        echo "<!-- Converted from .codexrc by setup.sh --migrate (#184). OpenAI Codex reads AGENTS.md; the original was kept as .codexrc.pre-standards-setup. The assembled 1.2+ AGENTS.md is staged in .standards-pending/ — run /merge-standards to adopt it and keep anything project-specific from this file. -->"
        echo ""
        awk '
            FNR == 1 && /^# /  { print "## " substr($0, 3); next }
            /^## /             { print; next }
            /^#[[:space:]]*$/  { print ""; next }
            /^# /              { print substr($0, 3); next }
            /^#/               { print substr($0, 2); next }
            { print }
        ' "$src"
    } > "$tmp"

    local target rel note
    if [ -f "$root/AGENTS.md" ]; then
        target="$pending_dir/AGENTS.md.from-codexrc"
        rel=".standards-pending/AGENTS.md.from-codexrc"
        note="- \`.standards-pending/AGENTS.md.from-codexrc\` is your \`.codexrc\` converted to Markdown. \`AGENTS.md\` already existed and was not touched: merge anything project-specific from the conversion into it, then delete \`.codexrc\` (Codex reads \`AGENTS.md\`)."
        if [ "$dry_run" = true ]; then
            echo "  [dry-run] Would convert .codexrc → $rel (AGENTS.md already exists; left as is)"
        else
            mkdir -p "$pending_dir"
            cp "$tmp" "$target"
            echo "   ✅ .codexrc converted → $rel (AGENTS.md already exists; left as is)"
        fi
    else
        target="$root/AGENTS.md"
        rel="AGENTS.md"
        note="- \`AGENTS.md\` was converted from \`.codexrc\` (kept as \`.codexrc.pre-standards-setup\`). Compare it with the assembled \`.standards-pending/AGENTS.md\`: adopt the assembled version and move anything project-specific below its PROJECT-SPECIFIC marker."
        if [ "$dry_run" = true ]; then
            echo "  [dry-run] Would convert .codexrc → AGENTS.md and keep the original as .codexrc.pre-standards-setup"
        else
            cp "$tmp" "$target"
            mv "$src" "$src.pre-standards-setup"
            echo "   ✅ .codexrc converted → AGENTS.md; original kept as .codexrc.pre-standards-setup"
        fi
    fi
    rm -f "$tmp"
    _migrate_append MIGRATE_NOTES "$note"

    # Dead references and legacy tiers in the converted text. The conversion
    # already kept the original, so the rewrite takes no second backup. In
    # dry-run the target was not written: report against the source instead.
    local probe="$target"
    [ "$dry_run" = true ] && probe="$src"
    if [ -n "$map" ]; then
        rewrite_dead_refs "$probe" "$map" "$dry_run" "$root" false
    fi
    fix_legacy_tiers "$probe" "$dry_run" "$root" false
    return 0
}
