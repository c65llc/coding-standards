#!/bin/sh
# egress-entrypoint.sh — fail-closed start for the tinyproxy egress sidecar
# (arch-09 §4). Copied into the image by Dockerfile.egress.
#
# This is the enforcement point the dev container cannot reach: the workspace's
# proxy/ directory is mounted read-only into `dev`, but a stale, hand-edited or
# otherwise untrusted allow-list or config could still arrive here, so nothing is
# trusted on arrival. The sidecar refuses to start unless:
#   * the config is the baked-in deny-by-default one (required directives present
#     verbatim, nothing that re-points the filter or chains to another proxy);
#   * the mounted allow-list is a readable regular file with at least one entry;
#   * EVERY entry is a lowercase hostname of two or more labels, optionally
#     prefixed with "*." — the exact grammar setup-proxy.sh emits. That rules out
#     a bare "*", any other glob ("?*", "*.*"), a single-label wildcard ("*.com"),
#     URLs, paths and mixed case (tinyproxy's fnmatch filter is case-sensitive, so
#     entries are normalised to lowercase at generation time and checked here).
# Because the dev service depends on this container being healthy, a bad
# allow-list stops the whole environment instead of quietly opening it.
#
# Also serves as the container HEALTHCHECK (`egress-entrypoint.sh healthcheck`).
#
# POSIX sh on purpose: the image is Alpine (busybox), not bash.
set -eu

CONF="${TINYPROXY_CONF:-/etc/tinyproxy/tinyproxy.conf}"
# Where the compose file mounts the allow-list and where the baked-in config must
# point. TINYPROXY_FILTER lets the test-suite feed a different file to the
# validation below; the config's Filter directive is always checked against the
# canonical path, since that is what tinyproxy will actually read.
CANONICAL_FILTER="/etc/tinyproxy/filter"
FILTER="${TINYPROXY_FILTER:-$CANONICAL_FILTER}"
PORT="${EGRESS_PORT:-3128}"

# One whole-host glob per line: lowercase labels, at least two of them, optional
# leading "*." for all subdomains. Keep in sync with setup-proxy.sh.
ENTRY_RE='^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$'

die() {
    printf 'egress: %s\n' "$*" >&2
    exit 1
}

# --- Health check -------------------------------------------------------------
# Liveness = tinyproxy accepts TCP connections on its port. A plain connect
# (busybox `nc -z`) is used on purpose: any HTTP probe would be filtered like
# every other unlisted host and leave a synthetic "Proxying refused" line in the
# log every few seconds, burying the real allow/deny verdicts.
if [ "${1:-}" = "healthcheck" ]; then
    exec nc -z -w 2 127.0.0.1 "$PORT"
fi

# --- Preflight: config ----------------------------------------------------------
# The config is baked into the image, but the image is built from the workspace,
# so assert the enforcement directives rather than trusting the file. A config
# that is not deny-by-default, filters URLs instead of hosts, reads a different
# filter file, or chains to an upstream proxy must never start.
[ -f "$CONF" ] || die "config not found at $CONF (Dockerfile.egress copies proxy/tinyproxy.conf there)."
[ -r "$CONF" ] || die "config at $CONF is not readable by uid $(id -u)."

conf_directives="$(sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$CONF" | grep . || true)"
require_directive() {
    printf '%s\n' "$conf_directives" | grep -qxF "$1" \
        || die "config at $CONF is missing the required directive '$1'. Refusing to start a proxy that is not deny-by-default."
}
require_directive 'FilterDefaultDeny Yes'
require_directive 'FilterType fnmatch'
require_directive 'FilterURLs Off'
require_directive "Filter \"$CANONICAL_FILTER\""
if [ "$(printf '%s\n' "$conf_directives" | grep -c '^Filter ')" -ne 1 ]; then
    die "config at $CONF must contain exactly one Filter directive. Refusing to start."
fi
forbidden="$(printf '%s\n' "$conf_directives" | grep -E -i '^(Upstream|ReversePath|ReverseOnly|ReverseMagic|ReverseBaseURL)([[:space:]]|$)' || true)"
[ -z "$forbidden" ] || die "config at $CONF contains a directive that would route around the allow-list: $forbidden. Refusing to start."

# --- Preflight: allow-list ------------------------------------------------------
# The compose file mounts the allow-list with create_host_path: false, so a
# missing source fails `compose up` before this runs; the explicit regular-file
# test still guards other mount set-ups where Docker would create a directory.
[ -f "$FILTER" ] || die "allow-list not found at $FILTER. Run ./scripts/setup-proxy.sh to generate proxy/allowlist.generated.txt, then restart this service."
[ -r "$FILTER" ] || die "allow-list at $FILTER is not readable by uid $(id -u) (setup-proxy.sh writes it mode 0644; check the mount)."

# Same normalisation setup-proxy.sh applies: drop comments, whitespace, blanks.
entry_list="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$FILTER" | grep . || true)"
entries="$(printf '%s' "$entry_list" | grep -c . || true)"
[ "$entries" -gt 0 ] || die "allow-list at $FILTER has no entries; refusing to start a proxy that could allow nothing (regenerate with ./scripts/setup-proxy.sh)."

# Every entry must match the generated grammar. Report all offenders, not the
# first, so a stale or hand-edited file is fixed in one pass.
invalid="$(printf '%s\n' "$entry_list" | grep -v -E "$ENTRY_RE" || true)"
if [ -n "$invalid" ]; then
    printf 'egress: allow-list at %s contains entries that are not lowercase whole-host globs:\n' "$FILTER" >&2
    printf '%s\n' "$invalid" | sed 's/^/egress:   /' >&2
    die "a bare '*', other globs, single-label wildcards such as '*.com', URLs, paths and upper-case entries are refused. Regenerate the file with ./scripts/setup-proxy.sh; never hand-edit it."
fi

if [ "$entries" -eq 1 ]; then noun="entry"; else noun="entries"; fi
printf 'egress: %s allow-list %s loaded from %s; every other destination is denied.\n' \
    "$entries" "$noun" "$FILTER"

# -d: stay in the foreground so Docker owns the process and collects the logs.
exec tinyproxy -d -c "$CONF"
