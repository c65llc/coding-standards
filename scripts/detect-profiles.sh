#!/bin/bash
# Suggest standards profiles (#227) a project looks eligible for, from cheap
# heuristics. Prints one `<profile><TAB><reason>` line per profile, each at
# most once, and nothing for a project that matches none. Suggestions only:
# a profile is enabled solely by `profiles:` in the committed .standards.yml.
#
# Usage: ./detect-profiles.sh [/path/to/project]
#   or:  PROJECT_ROOT=/path/to/project ./detect-profiles.sh
#
# shared-core  a Cargo.toml (root, core/, crates/*) depends on uniffi or
#              wasm-bindgen; or crates/ or core/ coexists with more than one
#              of shells/, apps/, ios/, android/, windows/, macos/.
# ui-surface   a web app manifest (manifest.json / manifest.webmanifest at
#              the root, public/, apps/*, apps/*/public); `role: app` in
#              .standards.yml; or a SwiftUI, Compose, Flutter or WinUI import
#              in the sources.

set -e

PROJECT_ROOT="${1:-${PROJECT_ROOT:-.}}"
if [ ! -d "$PROJECT_ROOT" ]; then
    echo "detect-profiles: no such directory: $PROJECT_ROOT" >&2
    exit 2
fi
cd "$PROJECT_ROOT"

suggest() {
    printf '%s\t%s\n' "$1" "$2"
}

# --- shared-core -----------------------------------------------------------

shared_core_reason() {
    local f dep
    for f in Cargo.toml core/Cargo.toml crates/*/Cargo.toml; do
        [ -f "$f" ] || continue
        for dep in uniffi wasm-bindgen; do
            if grep -qE "^[[:space:]]*${dep}[[:space:]]*=" "$f" 2>/dev/null; then
                printf '%s in %s\n' "$dep" "$f"
                return 0
            fi
        done
    done
    if [ -d crates ] || [ -d core ]; then
        local shells=0 d
        for d in shells apps ios android windows macos; do
            [ -d "$d" ] && shells=$((shells + 1))
        done
        if [ "$shells" -gt 1 ]; then
            printf 'crates/ or core/ beside platform shells\n'
            return 0
        fi
    fi
    return 1
}

# --- ui-surface ------------------------------------------------------------

ui_surface_reason() {
    local f
    for f in manifest.json manifest.webmanifest public/manifest.json public/manifest.webmanifest \
             apps/*/manifest.json apps/*/manifest.webmanifest apps/*/public/manifest.json apps/*/public/manifest.webmanifest; do
        if [ -f "$f" ]; then
            printf 'web app manifest\n'
            return 0
        fi
    done
    if [ -f .standards.yml ] && grep -qE '^role:[[:space:]]*app[[:space:]]*$' .standards.yml 2>/dev/null; then
        printf 'role: app\n'
        return 0
    fi
    if grep -rIlE --include='*.swift' --include='*.kt' --include='*.dart' --include='*.cs' \
            --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=target --exclude-dir=build \
            --exclude-dir=dist --exclude-dir=vendor --exclude-dir=.worktrees --exclude-dir=.claude \
            'import SwiftUI|androidx\.compose|package:flutter|Microsoft\.UI\.Xaml' . 2>/dev/null | head -1 | grep -q .; then
        printf 'UI framework import (SwiftUI|Compose|Flutter|WinUI)\n'
        return 0
    fi
    return 1
}

if reason=$(shared_core_reason); then suggest shared-core "$reason"; fi
if reason=$(ui_surface_reason); then suggest ui-surface "$reason"; fi
exit 0
