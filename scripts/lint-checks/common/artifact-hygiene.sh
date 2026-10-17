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

PROJECT_ROOT="${1:-.}"

CHECK_NAME="artifact-hygiene"

# Binary artifact extensions that are commonly committed as build outputs.
# Matched case-sensitively against the basename; `.so.<ver>` is covered too.
ARTIFACT_REGEX='\.(wasm|a|so|dylib|jar)$|\.so\.[0-9]+(\.[0-9]+)*$'

# Directories never worth scanning when falling back to a filesystem walk
# (vendored/third-party trees and build caches are not "committed artifacts").
EXCLUDE_DIRS=(
    ".git"
    "node_modules"
    ".standards"
    ".standards_tmp"
    "vendor"
    "target"
    ".venv"
    "venv"
    "__pycache__"
)

# Absolute home-directory path pattern. Matched against raw bytes (grep -a) so
# binaries are treated as text; LC_ALL=C keeps multibyte sequences from
# tripping up the regex engine.
HOME_PATH_REGEX='/(Users|home)/[A-Za-z0-9._-]+/'

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "WARN $CHECK_NAME Project root '$PROJECT_ROOT' not found"
    exit 2
fi

# ---------------------------------------------------------------------------
# Collect candidate artifacts.
#
# Prefer the git index: the standard is about *committed* artifacts, and a
# tracked-file listing ignores untracked build output automatically. Outside a
# git repository fall back to a filesystem walk with the usual exclusions.
# ---------------------------------------------------------------------------
list_artifacts() {
    if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$PROJECT_ROOT" ls-files -z 2>/dev/null \
            | tr '\0' '\n' \
            | grep -E "$ARTIFACT_REGEX" \
            | sed "s|^|$PROJECT_ROOT/|"
    else
        local exclude_args=()
        local dir
        for dir in "${EXCLUDE_DIRS[@]}"; do
            exclude_args+=(-not -path "*/$dir/*")
        done
        find "$PROJECT_ROOT" -type f "${exclude_args[@]}" 2>/dev/null \
            | grep -E "$ARTIFACT_REGEX"
    fi
}

ARTIFACTS=$(list_artifacts || true)

if [ -z "$ARTIFACTS" ]; then
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

while IFS= read -r artifact; do
    [ -n "$artifact" ] || continue
    [ -f "$artifact" ] || continue
    scanned=$((scanned + 1))

    # First match only — one example path is enough to point at the producer.
    sample=$(LC_ALL=C grep -aoE "${HOME_PATH_REGEX}[A-Za-z0-9._/-]*" "$artifact" 2>/dev/null \
        | head -1 | redact_user)
    [ -n "$sample" ] || continue

    tainted_count=$((tainted_count + 1))
    rel="${artifact#"$PROJECT_ROOT"/}"
    if [ "$tainted_count" -le 3 ]; then
        FINDINGS="${FINDINGS}${rel} (${sample}); "
    fi
done <<< "$ARTIFACTS"

if [ "$tainted_count" -eq 0 ]; then
    echo "PASS $CHECK_NAME $scanned committed binary artifact(s) scanned, no embedded home paths"
    exit 0
fi

FINDINGS="${FINDINGS%; }"
more=""
if [ "$tainted_count" -gt 3 ]; then
    more=" (+$((tainted_count - 3)) more)"
fi
echo "WARN $CHECK_NAME $tainted_count of $scanned committed artifact(s) embed absolute home paths — non-reproducible build; regenerate from the pinned runner with --remap-path-prefix / -ffile-prefix-map and strip producers: ${FINDINGS}${more}"
exit 2
