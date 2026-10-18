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

artifact_bytes() {
    local file="$1"
    cat "$file"
    case "$file" in
        *.jar)
            if [ "$HAVE_UNZIP" -eq 1 ]; then
                unzip -p "$file" 2>/dev/null || true
            fi
            ;;
    esac
}

if [ -n "$ARTIFACTS" ]; then
    while IFS= read -r artifact; do
        [ -n "$artifact" ] || continue
        [ -f "$artifact" ] || continue
        scanned=$((scanned + 1))

        # First match only — one example path is enough to point at the producer.
        sample=$(artifact_bytes "$artifact" \
            | LC_ALL=C grep -aoE "${HOME_PATH_REGEX}[A-Za-z0-9._/-]*" 2>/dev/null \
            | head -1 | redact_user)
        [ -n "$sample" ] || continue

        tainted_count=$((tainted_count + 1))
        rel="${artifact#"$PROJECT_ROOT"/}"
        if [ "$tainted_count" -le 3 ]; then
            FINDINGS="${FINDINGS}${rel} (${sample}); "
        fi
    done <<EOF
$ARTIFACTS
EOF
fi

if [ "$tainted_count" -eq 0 ] && [ "$UNSCANNABLE_COUNT" -eq 0 ]; then
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
echo "WARN $CHECK_NAME $msg"
exit 2
