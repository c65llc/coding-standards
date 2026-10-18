#!/bin/bash
# Resolve {{PROJECT_NAME}}, {{PROJECT_OVERVIEW}}, {{KEY_COMMANDS}} and
# {{WORKTREE_DIR}} in assembled agent-config and skill output. Called by assemble-config.sh right before the
# output file is written.
#
# Philosophy: fill what we can from package metadata and from the persisted
# `project_overview:` / `key_commands:` in .standards.yml; replace what we
# can't with explicit TODO markers so the user (or their LLM via
# /merge-standards) can finish the job. Never leave literal {{...}} in shipped
# output.

# yaml_block_scalar lives in lib/checksums.sh (the .standards.yml reader).
_TV_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! declare -f yaml_block_scalar >/dev/null 2>&1; then
    if [ -f "$_TV_LIB_DIR/checksums.sh" ]; then
        # shellcheck disable=SC1091
        source "$_TV_LIB_DIR/checksums.sh"
    fi
fi
# worktree_root_dir lives in lib/worktrees.sh (`worktree_dir:` reader, #190).
if ! declare -f worktree_root_dir >/dev/null 2>&1; then
    if [ -f "$_TV_LIB_DIR/worktrees.sh" ]; then
        # shellcheck disable=SC1091
        source "$_TV_LIB_DIR/worktrees.sh"
    fi
fi

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

TODO_OVERVIEW_MARKER="<!-- TODO(standards): one-paragraph project overview goes here. Run /merge-standards to fill. -->"
TODO_COMMANDS_MARKER="<!-- TODO(standards): list key build/test/run commands. Run /merge-standards to fill. -->"

# Persisted project text (#183). `project_overview:` and `key_commands:` in
# .standards.yml are the source of truth for {{PROJECT_OVERVIEW}} and
# {{KEY_COMMANDS}}; with them declared, a re-assembly reproduces the filled-in
# config byte for byte, so its checksum stays stable and sync never stages it
# as customized. Without them the TODO markers are written, as before.
resolve_project_overview() {
    local root="${1:-$(pwd)}"
    if declare -f yaml_block_scalar >/dev/null 2>&1 && [ -f "$root/.standards.yml" ]; then
        yaml_block_scalar "project_overview" "$root/.standards.yml"
    fi
}

resolve_key_commands() {
    local root="${1:-$(pwd)}"
    if declare -f yaml_block_scalar >/dev/null 2>&1 && [ -f "$root/.standards.yml" ]; then
        yaml_block_scalar "key_commands" "$root/.standards.yml"
    fi
}

# The agent worktree root (#194): `worktree_dir:` in .standards.yml when
# declared and valid, else the proc-04 default. Every agent's assembled text
# names the same root, so Codex, Cursor and Claude Code no longer disagree
# about where worktrees go.
resolve_worktree_dir() {
    local root="${1:-$(pwd)}"
    if declare -f worktree_root_dir >/dev/null 2>&1; then
        worktree_root_dir "$root"
    else
        printf '%s\n' "${WORKTREE_DIR_DEFAULT:-.claude/worktrees}"
    fi
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
    local worktree_dir worktree_dir_escaped
    worktree_dir=$(resolve_worktree_dir "$root")
    worktree_dir_escaped=$(_escape_sed_replacement "$worktree_dir")

    local overview commands
    overview=$(resolve_project_overview "$root")
    commands=$(resolve_key_commands "$root")
    [ -n "$overview" ] || overview="$TODO_OVERVIEW_MARKER"
    [ -n "$commands" ] || commands="$TODO_COMMANDS_MARKER"

    # POSIX-safe in-place edit (macOS/BSD compatible). The two multi-line
    # values go through awk via the environment (not -v, which would
    # interpret backslash escapes); a placeholder line is replaced by the
    # whole block, which may span several lines.
    local tmp
    tmp=$(mktemp)
    sed -e "s|{{PROJECT_NAME}}|${project_name_escaped}|g" \
        -e "s|{{WORKTREE_DIR}}|${worktree_dir_escaped}|g" "$file" \
        | TV_OVERVIEW="$overview" TV_COMMANDS="$commands" awk '
            # Literal replace-all (index/substr): the placeholders contain
            # braces, which BSD awk rejects inside a regex.
            function replace_all(line, needle, repl,   out, pos) {
                out = ""
                while ((pos = index(line, needle)) > 0) {
                    out = out substr(line, 1, pos - 1) repl
                    line = substr(line, pos + length(needle))
                }
                return out line
            }
            BEGIN { ov = ENVIRON["TV_OVERVIEW"]; cm = ENVIRON["TV_COMMANDS"] }
            {
                line = replace_all($0, "{{PROJECT_OVERVIEW}}", ov)
                line = replace_all(line, "{{KEY_COMMANDS}}", cm)
                print line
            }
        ' > "$tmp" && mv "$tmp" "$file"
}
