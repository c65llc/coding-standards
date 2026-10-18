#!/bin/bash
# scripts/lib/project-sections.sh — read the filled-in "Project Overview" and
# "Key Commands" sections out of an existing assembled agent config, and print
# the .standards.yml keys that would persist them (#183).
#
# Why: the assembler has no source for {{PROJECT_OVERVIEW}} / {{KEY_COMMANDS}}
# other than .standards.yml. A config whose sections were filled in by hand (or
# by the merge-standards skill) can never match its checksum again until the
# text is persisted, so setup and sync offer the YAML to add.
#
# Source this file; do not execute it directly.

# Marker text written by lib/template-vars.sh when nothing is declared.
_PS_TODO_PREFIX="<!-- TODO(standards):"

# config_section_body <file> <heading>
#
# Prints the body of the `## <heading>` section in <file>: the lines after the
# heading up to the next `## ` heading or the PROJECT-SPECIFIC sentinel, with
# leading/trailing blank lines dropped. A body that is only the TODO marker
# prints nothing (it is not user content).
config_section_body() {
    local file="$1"
    local heading="$2"
    [ -f "$file" ] || return 0
    awk -v h="## $heading" -v todo="$_PS_TODO_PREFIX" '
        !ins && $0 == h { ins = 1; next }
        ins && ($0 ~ /^## / || index($0, "<!-- BEGIN PROJECT-SPECIFIC") == 1) { exit }
        ins { n++; lines[n] = $0 }
        END {
            s = 1
            while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
            while (n >= s && lines[n] ~ /^[[:space:]]*$/) n--
            if (s > n) exit
            if (n == s && index(lines[s], todo) == 1) exit
            for (i = s; i <= n; i++) print lines[i]
        }
    ' "$file" 2>/dev/null
}

# config_key_commands <file>
#
# Like config_section_body for "Key Commands", but returns only the contents of
# the first fenced code block when the section has one (the base template wraps
# {{KEY_COMMANDS}} in ```bash fences), so the persisted value round-trips.
config_key_commands() {
    local file="$1"
    local body
    body=$(config_section_body "$file" "Key Commands")
    [ -n "$body" ] || return 0
    if printf '%s\n' "$body" | grep -q '^```'; then
        printf '%s\n' "$body" | awk '
            /^```/ { if (inf) exit; inf = 1; next }
            inf { print }
        ' | awk -v todo="$_PS_TODO_PREFIX" '
            { n++; lines[n] = $0 }
            END {
                s = 1
                while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
                while (n >= s && lines[n] ~ /^[[:space:]]*$/) n--
                if (s > n) exit
                if (n == s && index(lines[s], todo) == 1) exit
                for (i = s; i <= n; i++) print lines[i]
            }'
    else
        printf '%s\n' "$body"
    fi
}

# yaml_literal_block <key> <text>
#
# Prints `<key>: |` followed by <text> indented two spaces, ready to paste into
# .standards.yml. Interior blank lines are kept as empty lines.
yaml_literal_block() {
    local key="$1"
    local text="$2"
    printf '%s: |\n' "$key"
    printf '%s\n' "$text" | awk '{ if ($0 ~ /^[[:space:]]*$/) print ""; else print "  " $0 }'
}

# uncaptured_project_sections_yaml <project_root> <config-file>
#
# When <config-file> has a filled-in Project Overview and/or Key Commands
# section that .standards.yml does not yet persist, prints the YAML keys to
# add (one literal block per missing key). Prints nothing when there is
# nothing to capture, so callers can test the output for emptiness.
uncaptured_project_sections_yaml() {
    local root="$1"
    local file="$2"
    [ -f "$file" ] || return 0
    local yml="$root/.standards.yml"

    local have_overview="" have_commands=""
    if [ -f "$yml" ] && declare -f yaml_block_scalar >/dev/null 2>&1; then
        have_overview=$(yaml_block_scalar "project_overview" "$yml")
        have_commands=$(yaml_block_scalar "key_commands" "$yml")
    fi

    local out="" body
    if [ -z "$have_overview" ]; then
        body=$(config_section_body "$file" "Project Overview")
        if [ -n "$body" ]; then
            out=$(yaml_literal_block "project_overview" "$body")
        fi
    fi
    if [ -z "$have_commands" ]; then
        body=$(config_key_commands "$file")
        if [ -n "$body" ]; then
            out="${out:+$out
}$(yaml_literal_block "key_commands" "$body")"
        fi
    fi
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
}

# print_capture_hint <project_root> <config-file> <display-name>
#
# Prints the migration hint for setup.sh / sync-standards.sh: the YAML to add
# to .standards.yml so the filled-in sections survive re-assembly. Returns 0
# when a hint was printed, 1 when there was nothing to capture.
print_capture_hint() {
    local root="$1"
    local file="$2"
    local display="${3:-$(basename "$file")}"
    local yaml
    yaml=$(uncaptured_project_sections_yaml "$root" "$file")
    [ -n "$yaml" ] || return 1
    echo "💡 $display has a filled-in Project Overview / Key Commands that .standards.yml does not persist."
    echo "   Add this to .standards.yml so re-assembly reproduces it and the checksum stays stable"
    echo "   (Claude Code: /merge-standards writes it for you):"
    echo ""
    printf '%s\n' "$yaml" | sed 's/^/   /'
    echo ""
    return 0
}
