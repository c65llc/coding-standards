#!/bin/bash
# Check: Rust toolchain pin consistency
# rust-toolchain.toml `channel`, Cargo.toml `rust-version`, and CI toolchain
# pins must agree (lang-08 §21.4).
# Receives: $1 = project root
# Outputs: PASS|WARN|FAIL <check-name> <message>
# Exit:    0=PASS, 1=FAIL, 2=WARN

PROJECT_ROOT="${1:-.}"

CHECK_NAME="rust/toolchain-pin"

# --- rust-toolchain.toml / rust-toolchain -------------------------------------

CHANNEL=""
PIN_SOURCE=""
if [ -f "$PROJECT_ROOT/rust-toolchain.toml" ]; then
    PIN_SOURCE="rust-toolchain.toml"
    CHANNEL=$(grep -E '^[[:space:]]*channel[[:space:]]*=' "$PROJECT_ROOT/rust-toolchain.toml" 2>/dev/null \
        | head -1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d ' ')
elif [ -f "$PROJECT_ROOT/rust-toolchain" ]; then
    PIN_SOURCE="rust-toolchain"
    CHANNEL=$(head -1 "$PROJECT_ROOT/rust-toolchain" 2>/dev/null | tr -d ' \r')
fi

if [ -z "$PIN_SOURCE" ]; then
    echo "WARN $CHECK_NAME No rust-toolchain.toml — pin the toolchain (channel = \"1.xx.y\") so local, CI and rust-version agree"
    exit 2
fi

if [ -z "$CHANNEL" ]; then
    echo "WARN $CHECK_NAME $PIN_SOURCE present but no channel found"
    exit 2
fi

# Only a concrete major.minor.patch pins anything; "stable"/"nightly" float,
# and "1.99" still follows the latest patch release (§21.4).
if ! printf '%s' "$CHANNEL" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    if printf '%s' "$CHANNEL" | grep -qE '^[0-9]+\.[0-9]+$'; then
        echo "WARN $CHECK_NAME $PIN_SOURCE channel is \"$CHANNEL\" — pin the exact major.minor.patch (e.g. \"$CHANNEL.0\") so local, CI and rust-version agree"
    else
        echo "WARN $CHECK_NAME $PIN_SOURCE channel is \"$CHANNEL\" (floating) — pin an exact version so rust-version and CI can be checked against it"
    fi
    exit 2
fi

channel_mm=$(printf '%s' "$CHANNEL" | cut -d. -f1,2)

# Compare two "major.minor" strings numerically: prints -1, 0, or 1.
cmp_mm() {
    local a_major a_minor b_major b_minor
    a_major=$(printf '%s' "$1" | cut -d. -f1); a_minor=$(printf '%s' "$1" | cut -d. -f2)
    b_major=$(printf '%s' "$2" | cut -d. -f1); b_minor=$(printf '%s' "$2" | cut -d. -f2)
    if [ "$a_major" -lt "$b_major" ]; then echo -1; return; fi
    if [ "$a_major" -gt "$b_major" ]; then echo 1; return; fi
    if [ "$a_minor" -lt "$b_minor" ]; then echo -1; return; fi
    if [ "$a_minor" -gt "$b_minor" ]; then echo 1; return; fi
    echo 0
}

PROBLEMS=""
NOTES=""

# --- Cargo.toml rust-version ---------------------------------------------------

RUST_VERSIONS=""
if [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
    # Root manifest plus workspace members one or two levels down.
    MANIFESTS=$(find "$PROJECT_ROOT" -maxdepth 3 -name Cargo.toml \
        -not -path "*/target/*" -not -path "*/.git/*" -not -path "*/.standards/*" 2>/dev/null)
    while IFS= read -r manifest; do
        [ -n "$manifest" ] || continue
        rv=$(grep -E '^[[:space:]]*rust-version[[:space:]]*=' "$manifest" 2>/dev/null \
            | head -1 | sed -E 's/^[^=]*=[[:space:]]*"?([^"#]*)"?.*/\1/' | tr -d ' ')
        # `rust-version.workspace = true` inherits; skip those.
        if [ -n "$rv" ] && printf '%s' "$rv" | grep -qE '^[0-9]+\.[0-9]+'; then
            RUST_VERSIONS="${RUST_VERSIONS}${rv} "
        fi
    done <<< "$MANIFESTS"
fi

if [ -z "$RUST_VERSIONS" ]; then
    NOTES="${NOTES}no rust-version in Cargo.toml; "
else
    for rv in $RUST_VERSIONS; do
        rv_mm=$(printf '%s' "$rv" | cut -d. -f1,2)
        case "$(cmp_mm "$rv_mm" "$channel_mm")" in
            1)  PROBLEMS="${PROBLEMS}rust-version $rv is newer than pinned toolchain $CHANNEL; " ;;
            -1) NOTES="${NOTES}rust-version $rv trails pinned toolchain $CHANNEL (intentional MSRV? test it in CI); " ;;
        esac
    done
fi

# --- CI toolchain pins ----------------------------------------------------------

CI_PINS=""
CI_DEFS=""
if [ -d "$PROJECT_ROOT/.github/workflows" ]; then
    CI_DEFS=$(find "$PROJECT_ROOT/.github/workflows" -maxdepth 1 \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null)
fi
for extra in .gitlab-ci.yml .circleci/config.yml .buildkite/pipeline.yml; do
    if [ -f "$PROJECT_ROOT/$extra" ]; then
        CI_DEFS="${CI_DEFS}
$PROJECT_ROOT/$extra"
    fi
done
if [ -n "$(printf '%s' "$CI_DEFS" | tr -d '[:space:]')" ]; then
    while IFS= read -r wf; do
        [ -n "$wf" ] && [ -f "$wf" ] || continue
        rel="${wf#"$PROJECT_ROOT"/}"
        # dtolnay/rust-toolchain@1.99.0 style refs
        for v in $(grep -oE 'rust-toolchain@[0-9]+\.[0-9]+(\.[0-9]+)?' "$wf" 2>/dev/null | sed 's/.*@//'); do
            CI_PINS="${CI_PINS}${rel}=${v} "
        done
        # `toolchain: 1.99.0` inputs (dtolnay, actions-rs, actions-rust-lang)
        for v in $(grep -oE '^[[:space:]]*toolchain:[[:space:]]*["'"'"']?[0-9]+\.[0-9]+(\.[0-9]+)?' "$wf" 2>/dev/null | sed -E 's/.*toolchain:[[:space:]]*["'"'"']?//'); do
            CI_PINS="${CI_PINS}${rel}=${v} "
        done
        # `rustup toolchain install 1.99.0` / `rustup default 1.99.0`
        for v in $(grep -oE 'rustup[[:space:]]+(toolchain[[:space:]]+install|default|override[[:space:]]+set)[[:space:]]+[0-9]+\.[0-9]+(\.[0-9]+)?' "$wf" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?$'); do
            CI_PINS="${CI_PINS}${rel}=${v} "
        done
        # Floating CI toolchains drift from the pinned file silently.
        if grep -qE 'rust-toolchain@(stable|beta|nightly)|^[[:space:]]*toolchain:[[:space:]]*["'"'"']?(stable|beta|nightly)' "$wf" 2>/dev/null; then
            NOTES="${NOTES}${rel} uses a floating toolchain (stable/nightly) instead of ${CHANNEL}; "
        fi
    done <<< "$CI_DEFS"
fi

for pin in $CI_PINS; do
    wf="${pin%%=*}"
    v="${pin#*=}"
    v_mm=$(printf '%s' "$v" | cut -d. -f1,2)
    if [ "$(cmp_mm "$v_mm" "$channel_mm")" -ne 0 ]; then
        PROBLEMS="${PROBLEMS}${wf} pins toolchain $v but $PIN_SOURCE pins $CHANNEL; "
    elif printf '%s' "$v" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
        && printf '%s' "$CHANNEL" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
        && [ "$v" != "$CHANNEL" ]; then
        PROBLEMS="${PROBLEMS}${wf} pins toolchain $v but $PIN_SOURCE pins $CHANNEL; "
    fi
done

if [ -n "$PROBLEMS" ]; then
    PROBLEMS="${PROBLEMS%; }"
    echo "FAIL $CHECK_NAME Toolchain pins disagree — $PROBLEMS"
    exit 1
fi

if [ -n "$NOTES" ]; then
    NOTES="${NOTES%; }"
    echo "WARN $CHECK_NAME $PIN_SOURCE pins $CHANNEL — $NOTES"
    exit 2
fi

ci_note="no explicit CI pin found (CI reads $PIN_SOURCE)"
if [ -n "$CI_PINS" ]; then
    ci_note="CI pins agree"
fi
echo "PASS $CHECK_NAME $PIN_SOURCE pins $CHANNEL; rust-version agrees; $ci_note"
exit 0
