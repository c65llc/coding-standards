#!/usr/bin/env bash
# Guard the kit's inverted mount boundary (#221). Host consumers may read any
# checkout path: all must stay read-only, even files that do not exist yet.
# Deliberately accept only the template's small, auditable mount syntax. A new
# writable source overlay needs an explicit host-consumer audit and guard update.
set -euo pipefail

COMPOSE="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/templates/containerized-dev/docker-compose.dev.yml.example}"
awk '
    # A named volume with driver_opts/external could be a host bind in disguise.
    /^volumes:$/ {named=1; next}
    named && /^[^[:space:]#]/ {named=0}
    named && !/^[[:space:]]*(#|$)/ {
        if ($0 != "  dev-cache:") {
            print "Unreviewed named-volume backing: " $0 > "/dev/stderr"
            bad=1
        }
    }
    /^  dev:$/ {dev=1; next}
    dev && /^  [a-zA-Z_-]+:$/ {dev=0}
    dev && /^    (privileged|cap_add|volumes_from|devices|pid):/ {
        print "Unreviewed host-boundary override: " $0 > "/dev/stderr"
        bad=1
    }
    dev && /^    volumes:$/ {volumes=1; next}
    dev && volumes && /^    [a-zA-Z_-]+:/ {volumes=0}
    !dev || !volumes || /^[[:space:]]*(#|$)/ {next}
    {
        line=$0
        sub(/^[[:space:]]*/, "", line)
        if (line == "- { type: bind, source: ., target: /workspace, read_only: true, bind: { create_host_path: false } }") {
            root++; next
        }
        # These are Docker-owned volumes, never shared host-checkout paths.
        if (line == "- dev-cache:/home/developer/.cache") {next}
        # Identity and socket forwarding are read-only, outside /workspace.
        if (line == "- ${HOME}/.gitconfig:/home/developer/.gitconfig:ro" ||
            line == "- ${SSH_AGENT_SOURCE:-/dev/null}:/ssh-agent:ro") {next}
        print "Unsafe or unreviewed dev mount: " line > "/dev/stderr"
        bad=1
    }
    END {
        if (root != 1) {
            print "Expected exactly one read-only host-checkout mount at /workspace" > "/dev/stderr"
            bad=1
        }
        exit bad
    }
' "$COMPOSE"
