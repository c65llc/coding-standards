#!/bin/sh
# egress-entrypoint.sh — fail-closed start for the tinyproxy egress sidecar
# (arch-09 §4). Copied into the image by Dockerfile.egress.
#
# Refuses to start unless the mounted allow-list is a readable regular file with
# at least one real entry and no catch-all glob, so a missing, empty or
# over-broad allow-list can never become an open proxy or a silently broken one.
# Because the dev service depends on this container being healthy, a bad
# allow-list stops the whole environment instead of quietly opening it.
#
# Also serves as the container HEALTHCHECK (`egress-entrypoint.sh healthcheck`).
#
# POSIX sh on purpose: the image is Alpine (busybox), not bash.
set -eu

CONF="${TINYPROXY_CONF:-/etc/tinyproxy/tinyproxy.conf}"
FILTER="${TINYPROXY_FILTER:-/etc/tinyproxy/filter}"
PORT="${EGRESS_PORT:-3128}"

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
[ -f "$CONF" ] || die "config not found at $CONF (mount proxy/tinyproxy.conf there)."
[ -r "$CONF" ] || die "config at $CONF is not readable by uid $(id -u)."

# --- Preflight: allow-list ------------------------------------------------------
# A missing bind-mount source makes Docker create a DIRECTORY at the target, so
# test for a regular file explicitly.
[ -f "$FILTER" ] || die "allow-list not found at $FILTER. Run ./scripts/setup-proxy.sh to generate proxy/allowlist.generated.txt, then restart this service."
[ -r "$FILTER" ] || die "allow-list at $FILTER is not readable by uid $(id -u)."

# Same normalisation setup-proxy.sh applies: drop comments, whitespace, blanks.
entries="$(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$FILTER" | grep -c . || true)"
[ "$entries" -gt 0 ] || die "allow-list at $FILTER has no entries; refusing to start a proxy that could allow nothing (regenerate with ./scripts/setup-proxy.sh)."

if sed -e 's/#.*//' -e 's/[[:space:]]//g' "$FILTER" | grep -qx '\*'; then
    die "allow-list contains a bare '*', which would allow every destination. Refusing to start."
fi

if [ "$entries" -eq 1 ]; then noun="entry"; else noun="entries"; fi
printf 'egress: %s allow-list %s loaded from %s; every other destination is denied.\n' \
    "$entries" "$noun" "$FILTER"

# -d: stay in the foreground so Docker owns the process and collects the logs.
exec tinyproxy -d -c "$CONF"
