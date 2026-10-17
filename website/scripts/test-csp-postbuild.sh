#!/bin/bash
# Functional tests for scripts/csp-postbuild.mjs (the build step that turns the
# Cloudflare Pages _headers CSP template into a hash-based policy).
#
# Runs against a synthetic dist/ fixture so it needs only node + openssl, not a
# full Astro build. Usage: ./scripts/test-csp-postbuild.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POSTBUILD="$SCRIPT_DIR/csp-postbuild.mjs"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

assert_contains() {
    # $1 = description, $2 = file, $3 = needle (fixed string)
    if grep -qF -- "$3" "$2"; then pass "$1"; else fail "$1 (missing: $3)"; fi
}

assert_not_contains() {
    if grep -qF -- "$3" "$2"; then fail "$1 (unexpected: $3)"; else pass "$1"; fi
}

assert_count() {
    # $1 = description, $2 = file, $3 = needle (fixed string), $4 = expected count
    local n
    n="$(grep -oF -- "$3" "$2" | wc -l | tr -d ' ')"
    if [ "$n" -eq "$4" ]; then pass "$1"; else fail "$1 (expected $4, got $n)"; fi
}

sha256_b64() {
    # CSP hash of the exact bytes passed on stdin: 'sha256-<base64>'
    printf "'sha256-%s'" "$(openssl dgst -sha256 -binary | openssl base64 -A)"
}

if ! command -v node >/dev/null 2>&1; then
    echo "node is required to run these tests" >&2
    exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/csp-postbuild-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

TEMPLATE_CSP="default-src 'self'; script-src 'self' 'wasm-unsafe-eval' __CSP_SCRIPT_HASHES__; style-src 'self' __CSP_STYLE_HASHES__; style-src-attr 'unsafe-inline'; object-src 'none'"

write_headers_template() {
    # $1 = target dist dir
    {
        # The comment mentions a placeholder on purpose: only the header line
        # may be rewritten, never the documentation above it.
        echo "# comment line: __CSP_SCRIPT_HASHES__ is filled in at build time"
        echo "/*"
        echo "  X-Content-Type-Options: nosniff"
        echo "  Content-Security-Policy: $TEMPLATE_CSP"
    } > "$1/_headers"
}

# --- Fixture -----------------------------------------------------------------
DIST="$TMP/dist"
mkdir -p "$DIST/nested"
write_headers_template "$DIST"

SCRIPT_A='window.a = 1;'
SCRIPT_B='console.log("b")'
STYLE_A='.x{color:red}'
ATTR_A='--0:#D6DEEB;--1:#403F53'
ATTR_B='--depth: 1;'

# Page 1: a classic inline script, a module script, an ld+json data block
# (not executable, must not be hashed), an inline <style>, two style attrs.
{
    echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>t</title>'
    printf '<script>%s</script>\n' "$SCRIPT_A"
    printf '<script type="module">%s</script>\n' "$SCRIPT_B"
    echo '<script type="application/ld+json">{"@context":"https://schema.org"}</script>'
    printf '<style>%s</style>\n' "$STYLE_A"
    echo '<script type="module" src="/_astro/page.js"></script>'
    echo '</head><body>'
    printf '<span style="%s">x</span><li style="%s">y</li><span style="%s">z</span>\n' "$ATTR_A" "$ATTR_B" "$ATTR_A"
    echo '</body></html>'
} > "$DIST/index.html"

# Page 2: shares SCRIPT_A, has an HTML entity in a style attr, no inline style.
{
    printf '<!DOCTYPE html><html><head><title>n</title><script>%s</script></head>\n' "$SCRIPT_A"
    echo '<body><div style="content:&quot;a&quot;">q</div></body></html>'
} > "$DIST/nested/index.html"

# Non-HTML files must be left alone.
printf 'not html' > "$DIST/robots.txt"

echo "Running csp-postbuild.mjs against fixture..."
if node "$POSTBUILD" --dist "$DIST" > "$TMP/out.log" 2>&1; then
    pass "postbuild exits 0 on a well-formed dist"
else
    fail "postbuild exits 0 on a well-formed dist"
    cat "$TMP/out.log"
fi

HASH_SCRIPT_A="$(printf '%s' "$SCRIPT_A" | sha256_b64)"
HASH_SCRIPT_B="$(printf '%s' "$SCRIPT_B" | sha256_b64)"
HASH_LDJSON="$(printf '%s' '{"@context":"https://schema.org"}' | sha256_b64)"
HASH_STYLE_A="$(printf '%s' "$STYLE_A" | sha256_b64)"
HASH_ATTR_A="$(printf '%s' "$ATTR_A" | sha256_b64)"
HASH_ATTR_B="$(printf '%s' "$ATTR_B" | sha256_b64)"
HASH_ATTR_Q="$(printf '%s' 'content:"a"' | sha256_b64)"

echo "Checking generated _headers..."
assert_not_contains "script placeholder replaced on the header line" "$DIST/_headers" "'wasm-unsafe-eval' __CSP_SCRIPT_HASHES__"
assert_not_contains "style placeholder replaced on the header line" "$DIST/_headers" "style-src 'self' __CSP_STYLE_HASHES__"
assert_contains "comment mentioning a placeholder is kept verbatim" "$DIST/_headers" "# comment line: __CSP_SCRIPT_HASHES__ is filled in at build time"
assert_contains "classic inline script hashed into script-src" "$DIST/_headers" "$HASH_SCRIPT_A"
assert_contains "module inline script hashed into script-src" "$DIST/_headers" "$HASH_SCRIPT_B"
assert_not_contains "ld+json data block is not hashed" "$DIST/_headers" "$HASH_LDJSON"
assert_contains "inline <style> hashed into style-src" "$DIST/_headers" "$HASH_STYLE_A"
assert_not_contains "script-src carries no 'unsafe-inline'" "$DIST/_headers" "'wasm-unsafe-eval' 'unsafe-inline'"
assert_contains "wasm-unsafe-eval kept for Pagefind" "$DIST/_headers" "'wasm-unsafe-eval'"
assert_contains "unrelated header lines preserved" "$DIST/_headers" "X-Content-Type-Options: nosniff"
assert_count "shared script hash is emitted once (deduplicated)" "$DIST/_headers" "$HASH_SCRIPT_A" 1
if [ "$(wc -l < "$DIST/_headers" | tr -d ' ')" -eq 4 ]; then
    pass "_headers keeps its line count"
else
    fail "_headers keeps its line count"
fi

echo "Checking per-page style-src-attr meta tags..."
META_PREFIX='<meta http-equiv="Content-Security-Policy" content="style-src-attr '
assert_contains "page 1 gets a CSP meta tag" "$DIST/index.html" "$META_PREFIX"
assert_contains "page 1 meta uses 'unsafe-hashes'" "$DIST/index.html" "style-src-attr 'unsafe-hashes'"
assert_contains "page 1 meta hashes style attr A" "$DIST/index.html" "$HASH_ATTR_A"
assert_contains "page 1 meta hashes style attr B" "$DIST/index.html" "$HASH_ATTR_B"
assert_not_contains "page 1 meta does not carry page 2's attr hash" "$DIST/index.html" "$HASH_ATTR_Q"
assert_contains "page 2 meta decodes HTML entities before hashing" "$DIST/nested/index.html" "$HASH_ATTR_Q"
assert_not_contains "no 'unsafe-inline' in any meta" "$DIST/index.html" "'unsafe-inline'"
assert_count "duplicate style attrs hashed once per page" "$DIST/index.html" "$HASH_ATTR_A" 1
assert_count "exactly one CSP meta per page" "$DIST/index.html" 'http-equiv="Content-Security-Policy"' 1
if head -c 80 "$DIST/index.html" | grep -qF '<head><meta http-equiv="Content-Security-Policy"'; then
    pass "meta is injected at the start of <head>"
else
    fail "meta is injected at the start of <head>"
fi
if [ "$(cat "$DIST/robots.txt")" = "not html" ]; then
    pass "non-HTML files untouched"
else
    fail "non-HTML files untouched"
fi

# A page without style attributes gets an explicit 'none'.
NONE="$TMP/none"
mkdir -p "$NONE"
write_headers_template "$NONE"
echo '<html><head></head><body>plain</body></html>' > "$NONE/index.html"
node "$POSTBUILD" --dist "$NONE" > /dev/null 2>&1 || true
assert_contains "page without style attrs gets style-src-attr 'none'" "$NONE/index.html" "style-src-attr 'none'"

echo "Checking failure modes..."
# Re-running on an already-rendered dist: the meta tags are replaced in place
# (still exactly one per page) and the rendered _headers is rejected with a
# clear message rather than silently shipping without hashes.
if node "$POSTBUILD" --dist "$DIST" > "$TMP/rerun.log" 2>&1; then
    fail "re-running on a rendered _headers fails clearly"
elif grep -q "already rendered" "$TMP/rerun.log"; then
    pass "re-running on a rendered _headers fails clearly"
else
    fail "re-running on a rendered _headers fails clearly (unexpected message)"
fi
assert_count "re-running keeps exactly one CSP meta per page" "$DIST/index.html" 'http-equiv="Content-Security-Policy"' 1

# A page with an inline event handler cannot be allowed by hashes -> fail.
BAD="$TMP/bad"
mkdir -p "$BAD"
write_headers_template "$BAD"
echo '<html><head></head><body onload="x()">b</body></html>' > "$BAD/index.html"
if node "$POSTBUILD" --dist "$BAD" > /dev/null 2>&1; then
    fail "inline event handler attribute fails the build"
else
    pass "inline event handler attribute fails the build"
fi

# A template without the placeholders means hashes would silently never ship.
NOPH="$TMP/noph"
mkdir -p "$NOPH"
printf "/*\n  Content-Security-Policy: default-src 'self'\n" > "$NOPH/_headers"
cp "$DIST/index.html" "$NOPH/index.html"
if node "$POSTBUILD" --dist "$NOPH" > /dev/null 2>&1; then
    fail "missing placeholders fail the build"
else
    pass "missing placeholders fail the build"
fi

# Oversized header (Cloudflare caps a _headers line at 2,000 chars) -> fail.
BIG="$TMP/big"
mkdir -p "$BIG"
write_headers_template "$BIG"
{
    printf '<html><head></head><body>'
    i=0
    while [ "$i" -lt 40 ]; do
        printf '<script>var v%s=%s;</script>' "$i" "$i"
        i=$((i + 1))
    done
    printf '</body></html>'
} > "$BIG/index.html"
if node "$POSTBUILD" --dist "$BIG" > /dev/null 2>&1; then
    fail "header over the 2,000-char Cloudflare limit fails the build"
else
    pass "header over the 2,000-char Cloudflare limit fails the build"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
