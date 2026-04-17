#!/bin/bash
# Resolve {{PROJECT_NAME}}, {{PROJECT_OVERVIEW}}, {{KEY_COMMANDS}} in
# assembled agent-config output. Called by assemble-config.sh right before the
# output file is written.
#
# Philosophy: fill what we can from package metadata; replace what we can't
# with explicit TODO markers so the user (or their LLM via /merge-standards)
# can finish the job. Never leave literal {{...}} in shipped output.

resolve_project_name() {
    local root="${1:-$(pwd)}"
    local name=""

    if [ -f "$root/package.json" ]; then
        name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$root/package.json" \
               | head -1 \
               | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if [ -z "$name" ] && [ -f "$root/Cargo.toml" ]; then
        name=$(grep -E '^name[[:space:]]*=' "$root/Cargo.toml" | head -1 \
               | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if [ -z "$name" ] && [ -f "$root/pyproject.toml" ]; then
        name=$(grep -E '^name[[:space:]]*=' "$root/pyproject.toml" | head -1 \
               | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if [ -z "$name" ]; then
        name=$(basename "$root")
    fi
    printf '%s' "$name"
}

# Escape a string for safe use as a sed replacement value.
# Handles \, &, and the | delimiter used in resolve_template_vars.
_escape_sed_replacement() {
    printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# Usage: resolve_template_vars <file> <project_root>
# Rewrites the file in place.
resolve_template_vars() {
    local file="$1"
    local root="${2:-$(pwd)}"
    [ -f "$file" ] || return 0

    local project_name
    project_name=$(resolve_project_name "$root")
    local project_name_escaped
    project_name_escaped=$(_escape_sed_replacement "$project_name")

    # POSIX-safe in-place edit (macOS/BSD compatible)
    local tmp
    tmp=$(mktemp)
    sed \
        -e "s|{{PROJECT_NAME}}|${project_name_escaped}|g" \
        -e "s|{{PROJECT_OVERVIEW}}|<!-- TODO(standards): one-paragraph project overview goes here. Run /merge-standards to fill. -->|g" \
        -e "s|{{KEY_COMMANDS}}|<!-- TODO(standards): list key build/test/run commands. Run /merge-standards to fill. -->|g" \
        "$file" > "$tmp" && mv "$tmp" "$file"
}
