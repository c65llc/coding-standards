#!/bin/bash
# Check: committed binary artifacts must not embed absolute home-directory paths
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN
#
# Why: a committed build output (wasm bundle, static/shared library, jar) that
# contains "/Users/<name>/..." or "/home/<name>/..." was produced from a
# machine-specific path. The next developer's cold rebuild embeds *their* home
# directory instead, the bytes differ, and the cold-rebuild drift gate
# (arch-06 §6, arch-07 §3) goes red for a reason that has nothing to do with the
# source. Fix at the producer: --remap-path-prefix (Rust), -ffile-prefix-map
# (C/C++), strip the wasm `producers` section, and build from the pinned
# platform runner rather than a laptop.
#
# This check only WARNs: the artifact is not *wrong*, it is non-reproducible,
# and the correct remediation is a regeneration, not a blocked merge.
#
# File enumeration lives in scripts/lib/lint-files.sh and runs --strict: a
# committed artifact is scanned wherever it lives (dist/, build/, target/,
# vendor/ …) and `.standards.yml` lint.exclude does not apply, because the
# question is "is this committed artifact reproducible", not "is this tree
# ours". Outside a git repository the library falls back to a pruned find
# that only excludes directories *below* the project root. Filenames that
# contain a newline cannot be carried by the file list; they are reported as
# findings rather than skipped.
#
# Two cases are reported as an incomplete scan rather than a PASS: a Git LFS
# pointer (the working tree holds a 130-byte stub, not the artifact — the
# standards-review workflow checks out without `lfs: true`), and an ELF
# object whose DWARF sections are compressed (`objcopy
# --compress-debug-sections`) when no objcopy is available to inflate them.
# With objcopy present the debug sections are decompressed into a temporary
# copy and scanned, so a path hidden in compressed DWARF is still found.

PROJECT_ROOT="${1:-.}"

CHECK_NAME="artifact-hygiene"

LINT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" 2>/dev/null && pwd)/lint-files.sh"
if [ ! -f "$LINT_LIB" ]; then
    echo "WARN $CHECK_NAME lint-files library not found ($LINT_LIB)"
    exit 2
fi
# shellcheck source=../../lib/lint-files.sh
source "$LINT_LIB"

# Binary artifact extensions that are commonly committed as build outputs.
# Matched case-sensitively against the path; `.so.<ver>` is covered too.
ARTIFACT_REGEX='\.(wasm|a|so|dylib|jar)$|\.so\.[0-9]+(\.[0-9]+)*$'

# Absolute home-directory path pattern. Matched against raw bytes (grep -a) so
# binaries are treated as text; LC_ALL=C keeps multibyte sequences from
# tripping up the regex engine.
HOME_PATH_REGEX='/(Users|home)/[A-Za-z0-9._-]+/'

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "WARN $CHECK_NAME Project root '$PROJECT_ROOT' not found"
    exit 2
fi

# ---------------------------------------------------------------------------
# Collect candidate artifacts (absolute paths, one per line).
# ---------------------------------------------------------------------------
ARTIFACTS=$(lint_list_files --strict "$PROJECT_ROOT" | grep -E -- "$ARTIFACT_REGEX" || true)

# Artifact names the list cannot carry (they contain a newline). Reported,
# never skipped: a silent skip would be a false PASS.
UNSCANNABLE=$(lint_unscannable_files --strict "$PROJECT_ROOT" | grep -E -- "$ARTIFACT_REGEX" || true)
UNSCANNABLE_COUNT=0
if [ -n "$UNSCANNABLE" ]; then
    UNSCANNABLE_COUNT=$(printf '%s\n' "$UNSCANNABLE" | grep -c .)
fi

if [ -z "$ARTIFACTS" ] && [ "$UNSCANNABLE_COUNT" -eq 0 ]; then
    if lint_scope_is_changed; then
        echo "PASS $CHECK_NAME No binary artifacts (*.wasm, *.a, *.so, *.dylib, *.jar) in the changed-file scope"
        exit 0
    fi
    echo "PASS $CHECK_NAME No committed binary artifacts (*.wasm, *.a, *.so, *.dylib, *.jar) to scan"
    exit 0
fi

# ---------------------------------------------------------------------------
# Scan each artifact for embedded home paths.
# ---------------------------------------------------------------------------
scanned=0
tainted_count=0
FINDINGS=""

# Redact the username so the lint output itself (which lands in PR comments)
# does not leak who built the artifact.
redact_user() {
    sed -E 's#/(Users|home)/[A-Za-z0-9._-]+/#/\1/<user>/#g'
}

# Emit the bytes worth scanning for one artifact: always the raw file (which
# covers the ZIP central directory, entry names, archive comments and stored
# entries), and for JARs additionally the inflated entry contents, because
# ZIP entries are normally deflated and a grep over the raw bytes cannot see
# a path inside a class file or resource. Without unzip only the raw bytes
# are inspected.
HAVE_UNZIP=0
command -v unzip >/dev/null 2>&1 && HAVE_UNZIP=1

# objcopy inflates compressed DWARF (`--compress-debug-sections`, zlib-gnu
# `.zdebug_*` or SHF_COMPRESSED `.debug_*`) so the source paths inside become
# greppable again. binutils objcopy, Homebrew's gobjcopy and llvm-objcopy all
# take --decompress-debug-sections and operate on `.a` archives as well as on
# single ELF objects. readelf, when present, is the authoritative way to tell
# whether a file carries compressed debug sections.
OBJCOPY=""
for tool in objcopy gobjcopy llvm-objcopy; do
    if command -v "$tool" >/dev/null 2>&1; then OBJCOPY="$tool"; break; fi
done
READELF=""
for tool in readelf greadelf llvm-readelf; do
    if command -v "$tool" >/dev/null 2>&1; then READELF="$tool"; break; fi
done

SCRATCH=$(mktemp -d 2>/dev/null || mktemp -d -t artifact-hygiene)
trap 'rm -rf "$SCRATCH"' EXIT

# Git LFS stores a small pointer stub in the working tree; the artifact itself
# is only present after `git lfs pull` (or `actions/checkout` with `lfs: true`).
is_lfs_pointer() {
    LC_ALL=C head -c 64 "$1" 2>/dev/null | LC_ALL=C grep -q '^version https://git-lfs\.github\.com/spec/v'
}

# ELF object or `ar` archive (`.a`) — the only formats where DWARF can be
# section-compressed. Mach-O (.dylib) keeps debug info in a dSYM, uncompressed.
is_native_object() {
    local magic
    magic=$(LC_ALL=C head -c 8 "$1" 2>/dev/null | LC_ALL=C tr -d '\0' | LC_ALL=C tr '\n' ' ')
    case "$magic" in
        $'\177ELF'*|'!<arch> '*) return 0 ;;
    esac
    return 1
}

# Does the object carry compressed debug sections? With readelf: a `.zdebug_*`
# section, or a `.debug_*` row whose Flg column carries `C` (SHF_COMPRESSED).
# Without readelf only the zlib-gnu naming is detectable from raw bytes.
has_compressed_debug() {
    if [ -n "$READELF" ]; then
        "$READELF" -S -W "$1" 2>/dev/null \
            | LC_ALL=C grep -qE '\.zdebug_|\.debug_[^[:space:]]+[[:space:]]+[A-Z_]+[[:space:]]+[0-9a-f]+[[:space:]]+[0-9a-f]+[[:space:]]+[0-9a-f]+[[:space:]]+[0-9a-f]+[[:space:]]+[A-Za-z]*C'
    else
        LC_ALL=C grep -aq '\.zdebug_' "$1"
    fi
}

# Write a copy of $1 with debug sections inflated to $2. Returns non-zero when
# no objcopy is available or it could not process the file.
decompress_debug() {
    [ -n "$OBJCOPY" ] || return 1
    "$OBJCOPY" --decompress-debug-sections "$1" "$2" >/dev/null 2>&1 && [ -s "$2" ]
}

# $1 = artifact, $2 = decompressed copy or "" when none was produced.
artifact_bytes() {
    local file="$1" inflated="$2"
    cat "$file"
    [ -n "$inflated" ] && cat "$inflated"
    case "$file" in
        *.jar)
            if [ "$HAVE_UNZIP" -eq 1 ]; then
                unzip -p "$file" 2>/dev/null || true
            fi
            ;;
    esac
}

lfs_count=0
LFS_POINTERS=""
compressed_count=0
COMPRESSED=""

if [ -n "$ARTIFACTS" ]; then
    while IFS= read -r artifact; do
        [ -n "$artifact" ] || continue
        [ -f "$artifact" ] || continue
        rel="${artifact#"$PROJECT_ROOT"/}"

        # An LFS pointer is not the artifact: report, do not count as scanned.
        if is_lfs_pointer "$artifact"; then
            lfs_count=$((lfs_count + 1))
            [ "$lfs_count" -le 3 ] && LFS_POINTERS="${LFS_POINTERS}${rel} "
            continue
        fi
        scanned=$((scanned + 1))

        # Inflate compressed DWARF when we can; remember when we cannot.
        inflated=""
        if is_native_object "$artifact" && has_compressed_debug "$artifact"; then
            if decompress_debug "$artifact" "$SCRATCH/inflated"; then
                inflated="$SCRATCH/inflated"
            else
                compressed_count=$((compressed_count + 1))
                [ "$compressed_count" -le 3 ] && COMPRESSED="${COMPRESSED}${rel} "
            fi
        fi

        # First match only — one example path is enough to point at the producer.
        sample=$(artifact_bytes "$artifact" "$inflated" \
            | LC_ALL=C grep -aoE "${HOME_PATH_REGEX}[A-Za-z0-9._/-]*" 2>/dev/null \
            | head -1 | redact_user)
        rm -f "$SCRATCH/inflated"
        [ -n "$sample" ] || continue

        tainted_count=$((tainted_count + 1))
        if [ "$tainted_count" -le 3 ]; then
            FINDINGS="${FINDINGS}${rel} (${sample}); "
        fi
    done <<EOF
$ARTIFACTS
EOF
fi

if [ "$tainted_count" -eq 0 ] && [ "$UNSCANNABLE_COUNT" -eq 0 ] \
   && [ "$lfs_count" -eq 0 ] && [ "$compressed_count" -eq 0 ]; then
    echo "PASS $CHECK_NAME $scanned committed binary artifact(s) scanned, no embedded home paths"
    exit 0
fi

FINDINGS="${FINDINGS%; }"
more=""
if [ "$tainted_count" -gt 3 ]; then
    more=" (+$((tainted_count - 3)) more)"
fi

msg=""
if [ "$tainted_count" -gt 0 ]; then
    msg="$tainted_count of $scanned committed artifact(s) embed absolute home paths — non-reproducible build; regenerate from the pinned runner with --remap-path-prefix / -ffile-prefix-map and strip producers: ${FINDINGS}${more}"
fi
if [ "$UNSCANNABLE_COUNT" -gt 0 ]; then
    [ -n "$msg" ] && msg="$msg; "
    msg="${msg}${UNSCANNABLE_COUNT} artifact name(s) contain a newline and cannot be scanned (rename them): $(printf '%s\n' "$UNSCANNABLE" | head -3 | redact_user | tr '\n' ' ' | sed 's/ $//')"
fi
if [ "$lfs_count" -gt 0 ]; then
    [ -n "$msg" ] && msg="$msg; "
    msg="${msg}${lfs_count} artifact(s) are Git LFS pointers and were not scanned — fetch the objects first (actions/checkout with \`lfs: true\`, or \`git lfs pull\`): ${LFS_POINTERS% }"
fi
if [ "$compressed_count" -gt 0 ]; then
    [ -n "$msg" ] && msg="$msg; "
    msg="${msg}${compressed_count} artifact(s) carry compressed DWARF that could not be inflated — install binutils (objcopy) so the debug sections are scanned: ${COMPRESSED% }"
fi
echo "WARN $CHECK_NAME $msg"
exit 2
