#!/bin/bash
# scripts/lib/checksums.sh — Sourceable library of checksum functions.
#
# Used by setup.sh and sync-standards.sh to detect customized agent configs
# and avoid overwriting user edits during re-assembly.
#
# Source this file; do not execute it directly.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/checksums.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CHECKSUMS_FILE=".standards-checksums"
PENDING_DIR=".standards-pending"
SENTINEL="<!-- BEGIN PROJECT-SPECIFIC"
ASSEMBLY_HEADER="Assembled by coding-standards"

# ---------------------------------------------------------------------------
# compute_hash <file>
#
# Computes SHA256 of the assembler-controlled portion of a file (content above
# the sentinel marker), with trailing whitespace normalized to avoid false
# positives from editor auto-formatting.
#
# Outputs the hex digest to stdout.
# ---------------------------------------------------------------------------
compute_hash() {
    local file="$1"
    # strip_trailing_blanks: portable awk that removes trailing blank lines,
    # avoiding the BSD sed multi-line loop syntax which is not portable.
    local strip_trailing_blanks='{ lines[NR]=$0; if(NF) last=NR } END { for(i=1;i<=last;i++) print lines[i] }'
    local content
    if grep -qF "$SENTINEL" "$file" 2>/dev/null; then
        content=$(sed "/$SENTINEL/,\$d" "$file" | awk "$strip_trailing_blanks")
    else
        content=$(awk "$strip_trailing_blanks" "$file")
    fi
    printf '%s' "$content" | shasum -a 256 | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# read_stored_hash <key> [checksums_file]
#
# Reads the stored hash for <key> from the checksums file.
# Outputs the hash to stdout, or empty string if not found.
#
# File format (one entry per line):
#   <key> <hash>
# ---------------------------------------------------------------------------
read_stored_hash() {
    local key="$1"
    local file="${2:-$CHECKSUMS_FILE}"
    if [ ! -f "$file" ]; then
        echo ""
        return 0
    fi
    awk -v k="$key" '$1 == k { print $2; exit }' "$file"
}

# ---------------------------------------------------------------------------
# update_checksum_entry <key> <hash> <existing_content>
#
# Adds or updates the <key> <hash> entry in <existing_content> (an in-memory
# checksums string). Returns the updated string via stdout.
#
# This is intentionally in-memory so callers can accumulate multiple entries
# and write the file once at the end.
# ---------------------------------------------------------------------------
update_checksum_entry() {
    local key="$1"
    local hash="$2"
    local content="$3"
    # Remove any existing line for this key, then append the new entry.
    local updated
    updated=$(printf '%s\n' "$content" | grep -v "^${key} " || true)
    if [ -n "$updated" ]; then
        printf '%s\n%s %s\n' "$updated" "$key" "$hash"
    else
        printf '%s %s\n' "$key" "$hash"
    fi
}

# ---------------------------------------------------------------------------
# has_assembly_header <file>
#
# Returns 0 (true) if <file> contains the "Assembled by coding-standards"
# header, 1 (false) otherwise.
# ---------------------------------------------------------------------------
has_assembly_header() {
    local file="$1"
    grep -qF "$ASSEMBLY_HEADER" "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# write_pending <output_file> <agent> <blocks_dir> <base_template> [block ...]
#
# Writes a pending-update stub to .standards-pending/<basename-of-output_file>
# so the operator knows a new assembly is available but was skipped because the
# file was customized.
#
# Creates .standards-pending/ if it does not exist.
# ---------------------------------------------------------------------------
write_pending() {
    local output_file="$1"
    local agent="$2"
    shift 2
    local basename
    basename="$(basename "$output_file")"

    mkdir -p "$PENDING_DIR"

    local pending_path="$PENDING_DIR/$basename"
    {
        printf '# Pending update for: %s\n' "$output_file"
        printf '# Generated: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        printf '#\n'
        printf '# This file was NOT written because the destination has been customized.\n'
        printf '# To apply the update, review the diff and merge manually.\n'
        printf '#\n'
        printf '# For guided merge instructions, see:\n'
        printf '#   docs/superpowers/merge-pending-standards.md\n'
        printf '#\n'
        printf '# Agent: %s\n' "$agent"
        printf '# Remaining args: %s\n' "$*"
    } > "$pending_path"
}

# ---------------------------------------------------------------------------
# should_assemble <output_file> [checksums_file]
#
# Decision function: determines whether assembly should proceed for <output_file>.
#
# Exit codes:
#   0 — assemble normally
#         (file does not exist, or file matches stored hash, or file has the
#          assembly header but no stored hash exists yet)
#   1 — skip: file has been customized (hash differs from stored hash)
#   2 — skip: file was manually created without the assembly header
#             (a .bak copy is written to .standards-pending/ as a safety backup)
#
# Warnings are printed to stderr when skipping or backing up.
# ---------------------------------------------------------------------------
should_assemble() {
    local output_file="$1"
    local checksums_file="${2:-$CHECKSUMS_FILE}"

    # File does not exist yet — safe to assemble.
    if [ ! -f "$output_file" ]; then
        return 0
    fi

    local file_key
    file_key=$(basename "$output_file")
    local stored_hash
    stored_hash=$(read_stored_hash "$file_key" "$checksums_file")

    # File exists but was never recorded by us.
    if [ -z "$stored_hash" ]; then
        if has_assembly_header "$output_file"; then
            # Our header is present but we have no hash — first run after
            # this library was introduced, or hash file was wiped. Allow
            # assembly so we can record a baseline.
            return 0
        else
            # File was created by the user (no assembly header).  Back it up
            # and skip assembly to avoid destroying their work.
            echo "WARNING: $output_file has no assembly header and no stored hash — skipping assembly. Backing up to $PENDING_DIR/$(basename "$output_file").bak" >&2
            mkdir -p "$PENDING_DIR"
            cp "$output_file" "$PENDING_DIR/$(basename "$output_file").bak"
            return 2
        fi
    fi

    # We have a stored hash — compare it to the current file content.
    local current_hash
    current_hash=$(compute_hash "$output_file")

    if [ "$current_hash" = "$stored_hash" ]; then
        # File is unchanged since last assembly — safe to overwrite.
        return 0
    else
        # File has been edited since last assembly — do not overwrite.
        echo "WARNING: $output_file has been customized since last assembly — skipping. Run 'make sync-standards' after reviewing $PENDING_DIR/ to merge updates." >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# YAML Parsing Helpers (grep-based, no external deps)
# ---------------------------------------------------------------------------

# awk function shared by the scalar readers below: a quoted value keeps
# everything up to its closing quote (a "#" inside quotes is data, not a
# comment) and drops whatever follows; an unquoted value loses its trailing
# comment and whitespace. Prepend to an awk program: awk "$_YAML_SCALAR_AWK"'...'
# (a plain string, not a heredoc: bash 3.2 misparses a quote inside a heredoc
# that sits in a command substitution; \047 is the single quote, for awk)
_YAML_SCALAR_AWK='
function yaml_scalar(s) {
    sub(/^[[:space:]]+/, "", s)
    if (s ~ /^"/) {
        if (match(s, /^"([^"\\]|\\.)*"/)) return substr(s, 2, RLENGTH - 2)
    } else if (s ~ /^\047/) {
        if (match(s, /^\047[^\047]*\047/)) return substr(s, 2, RLENGTH - 2)
    }
    sub(/[[:space:]]+#.*$/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
'

# Read a simple scalar value from a YAML file
# Usage: yaml_get "key" "file" → outputs value
yaml_get() {
    local key="$1"
    local file="$2"
    grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

# Read a YAML list into a space-separated string
# Usage: yaml_list "key" "file" → outputs "val1 val2 val3"
yaml_list() {
    local key="$1"
    local file="$2"
    # Handle both inline [a, b, c] and block list formats
    local inline
    inline=$(grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*$//')
    if [[ "$inline" == \[* ]]; then
        # Inline format: [python, typescript]   # a trailing comment is dropped.
        # Commas split entries only outside quotes, so ["api,v2", web] keeps
        # "api,v2" whole (the caller unquotes), as yaml_nested_list does.
        awk -v line="$inline" 'BEGIN {
            sub(/^\[/, "", line)
            sub(/\].*$/, "", line)
            len = length(line); cur = ""; q = ""
            for (i = 1; i <= len; i++) {
                ch = substr(line, i, 1)
                if (q != "") {
                    cur = cur ch
                    if (ch == q) q = ""
                } else if (ch == "\"" || ch == "\047") {
                    q = ch; cur = cur ch
                } else if (ch == ",") {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
                    if (cur != "") print cur
                    cur = ""
                } else {
                    cur = cur ch
                }
            }
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
            if (cur != "") print cur
        }' | tr '\n' ' '
    else
        # Block format:
        #   - python
        #   - typescript   # a trailing comment is dropped; a quoted value keeps
        #   - "gen#tmp"    # its "#" and loses anything after the closing quote
        #                  # (the caller unquotes)
        awk "/^${key}:/{found=1;next}
             found && /^[[:space:]]*-/{
                 gsub(/^[[:space:]]*-[[:space:]]*/,\"\");
                 if (\$0 ~ /^\\\"/)      { if (match(\$0, /^\\\"[^\\\"]*\\\"/)) \$0 = substr(\$0, 1, RLENGTH) }
                 else if (\$0 ~ /^'/)   { if (match(\$0, /^'[^']*'/)) \$0 = substr(\$0, 1, RLENGTH) }
                 else                    { sub(/^#.*$/, \"\"); sub(/[[:space:]]+#.*$/, \"\") }
                 sub(/[[:space:]]+$/, \"\");
                 if (length(\$0) > 0) print;
                 next
             }
             found && /^[^[:space:]-]/{exit}" "$file" 2>/dev/null | tr '\n' ' '
    fi
}

# Read a nested scalar value from a YAML file
# Usage: yaml_nested_get "parent" "child" "file" → outputs value
yaml_nested_get() {
    local parent="$1"
    local child="$2"
    local file="$3"
    awk "/^${parent}:/{found=1;next} found && /^[[:space:]]+${child}:/{gsub(/^[[:space:]]*${child}:[[:space:]]*/,\"\"); print; exit} found && /^[^[:space:]]/{exit}" "$file" 2>/dev/null | sed 's/[[:space:]]*$//'
}

# Read a nested YAML list into newline-separated values
# Usage: yaml_nested_list "parent" "child" "file" → outputs one value per line
# Handles both block lists and inline [a, b] under the nested key:
#   lint:
#     exclude:
#       - docs/
#       - fixtures/**
yaml_nested_list() {
    local parent="$1"
    local child="$2"
    local file="$3"
    awk -v p="$parent" -v c="$child" '
        !inp && index($0, p ":") == 1 { inp = 1; next }
        inp && !inc && $0 ~ /^[^[:space:]]/ { exit }
        inp && !inc && $0 ~ ("^[[:space:]]+" c ":") {
            line = $0
            sub(/^[[:space:]]*[^:]+:[[:space:]]*/, "", line)
            if (line ~ /^\[/) {
                # Inline list: split on commas outside quotes only, so a
                # quoted value such as "generated,old/" stays one entry.
                sub(/^\[/, "", line)
                sub(/\][[:space:]]*$/, "", line)
                len = length(line); cur = ""; q = ""
                for (i = 1; i <= len; i++) {
                    ch = substr(line, i, 1)
                    if (q != "") {
                        cur = cur ch
                        if (ch == q) q = ""
                    } else if (ch == "\"" || ch == "\047") {
                        q = ch; cur = cur ch
                    } else if (ch == ",") {
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
                        if (cur != "") print cur
                        cur = ""
                    } else {
                        cur = cur ch
                    }
                }
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", cur)
                if (cur != "") print cur
                exit
            }
            inc = 1; next
        }
        inc && $0 ~ /^[[:space:]]*-/ {
            sub(/^[[:space:]]*-[[:space:]]*/, "")
            sub(/[[:space:]]+$/, "")
            if ($0 != "") print
            next
        }
        inc && $0 ~ /^[[:space:]]*(#|$)/ { next }
        inc { exit }
    ' "$file" 2>/dev/null
}

# Read a scalar that may be a YAML literal block (`key: |` or `key: |-`) or a
# plain one-line value. Block lines are de-indented by the indentation of the
# first non-blank line; interior blank lines are kept, trailing ones dropped.
# A folded block (`>`) is read like a literal one. Output ends with a newline
# when non-empty.
# Usage: yaml_block_scalar "key" "file"
yaml_block_scalar() {
    local key="$1"
    local file="$2"
    awk -v k="$key" "$_YAML_SCALAR_AWK"'
        function flush() {
            while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
            for (i = 1; i <= n; i++) print lines[i]
        }
        !inb && index($0, k ":") == 1 {
            rest = substr($0, length(k) + 2)
            sub(/^[[:space:]]+/, "", rest)
            if (rest ~ /^[|>][-+]?[[:space:]]*(#.*)?$/) { inb = 1; n = 0; indent = -1; next }
            # plain scalar on the key line: quotes stripped, trailing comment
            # dropped (a "#" inside the quotes is kept, see yaml_scalar)
            rest = yaml_scalar(rest)
            if (rest != "") print rest
            exit
        }
        inb {
            if ($0 ~ /^[[:space:]]*$/) { n++; lines[n] = ""; next }
            # next top-level key ends the block (exit still runs END, so clear inb)
            if ($0 ~ /^[^[:space:]]/) { flush(); inb = 0; exit }
            if (indent < 0) { match($0, /^[[:space:]]*/); indent = RLENGTH }
            n++; lines[n] = substr($0, indent + 1)
            next
        }
        END { if (inb) flush() }
    ' "$file" 2>/dev/null
}

# Print a top-level key and its whole block verbatim: the `key:` line plus every
# following indented or blank line, trailing blank lines dropped. Lets a script
# that regenerates .standards.yml carry a hand-written block across unchanged.
# Prints nothing when the key is absent.
# Usage: yaml_raw_block "key" "file"
yaml_raw_block() {
    local key="$1"
    local file="$2"
    awk -v k="$key" '
        !inb && index($0, k ":") == 1 { inb = 1; n = 1; lines[n] = $0; next }
        inb && $0 ~ /^[^[:space:]]/ { exit }
        inb { n++; lines[n] = $0 }
        END {
            if (!inb) exit
            while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
            for (i = 1; i <= n; i++) print lines[i]
        }
    ' "$file" 2>/dev/null
}

# Read one entry of a top-level YAML mapping whose keys are file paths:
#   managed:
#     CLAUDE.md: false
#     .github/copilot-instructions.md: false
# or inline: managed: { CLAUDE.md: false, AGENTS.md: true }
# Keys and values may be quoted; a trailing comment is dropped. Prints the
# value, or nothing when the entry is absent.
# Usage: yaml_map_value "parent" "entry-key" "file"
yaml_map_value() {
    local parent="$1"
    local entry="$2"
    local file="$3"
    awk -v p="$parent" -v want="$entry" "$_YAML_SCALAR_AWK"'
        function unq(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
            return s
        }
        function emit(pair,   k, v) {
            if (pair !~ /:/) return
            k = pair; sub(/:.*$/, "", k)
            v = pair; sub(/^[^:]*:/, "", v)
            if (unq(k) == want) { print yaml_scalar(v); exit }
        }
        !inp && index($0, p ":") == 1 {
            rest = substr($0, length(p) + 2)
            sub(/^[[:space:]]+/, "", rest)
            if (rest ~ /^\{/) {
                sub(/^\{/, "", rest); sub(/\}.*$/, "", rest)
                n = split(rest, parts, ",")
                for (i = 1; i <= n; i++) emit(parts[i])
                exit
            }
            inp = 1; next
        }
        inp && $0 ~ /^[^[:space:]]/ { exit }
        inp && $0 ~ /^[[:space:]]*(#|$)/ { next }
        inp { line = $0; sub(/^[[:space:]]+/, "", line); emit(line) }
    ' "$file" 2>/dev/null
}

# ---------------------------------------------------------------------------
# file_managed <project_root> <config-path>
#
# Returns 0 when the assembled agent config at <config-path> (absolute, relative
# to the project root, or a bare basename such as CLAUDE.md) is managed by the
# standards scripts — the default — and 1 when .standards.yml declares it
# hand-curated (#183):
#
#   managed:
#     CLAUDE.md: false
#
# The entry may name the relative path or the basename. Any value other than
# false/no/off (case-insensitive) means managed.
# ---------------------------------------------------------------------------
file_managed() {
    local root="$1"
    local path="$2"
    local yml="$root/.standards.yml"
    [ -f "$yml" ] || return 0
    local rel="${path#"$root"/}"
    local base
    base="$(basename "$path")"
    local value
    value=$(yaml_map_value "managed" "$rel" "$yml")
    if [ -z "$value" ] && [ "$rel" != "$base" ]; then
        value=$(yaml_map_value "managed" "$base" "$yml")
    fi
    if [ -z "$value" ]; then
        # Entry written with a directory the caller did not give (or vice
        # versa): every agent config has a unique basename, so match on it.
        local entry_key entry_value
        while IFS="$(printf '\t')" read -r entry_key entry_value; do
            [ -n "$entry_key" ] || continue
            if [ "$(basename "$entry_key")" = "$base" ]; then
                value="$entry_value"
                break
            fi
        done <<EOF
$(yaml_map_entries "managed" "$yml")
EOF
    fi
    case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
        false|no|off) return 1 ;;
        *)            return 0 ;;
    esac
}

# List every entry of a top-level YAML mapping (block or inline) as
# "<key><TAB><value>" lines, keys and values unquoted, comments dropped.
# Usage: yaml_map_entries "parent" "file"
yaml_map_entries() {
    local parent="$1"
    local file="$2"
    awk -v p="$parent" "$_YAML_SCALAR_AWK"'
        function unq(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) s = substr(s, 2, length(s) - 2)
            return s
        }
        function emit(pair,   k, v) {
            if (pair !~ /:/) return
            k = pair; sub(/:.*$/, "", k)
            v = pair; sub(/^[^:]*:/, "", v)
            k = unq(k)
            if (k != "") printf "%s\t%s\n", k, yaml_scalar(v)
        }
        !inp && index($0, p ":") == 1 {
            rest = substr($0, length(p) + 2)
            sub(/^[[:space:]]+/, "", rest)
            if (rest ~ /^\{/) {
                sub(/^\{/, "", rest); sub(/\}.*$/, "", rest)
                n = split(rest, parts, ",")
                for (i = 1; i <= n; i++) emit(parts[i])
                exit
            }
            inp = 1; next
        }
        inp && $0 ~ /^[^[:space:]]/ { exit }
        inp && $0 ~ /^[[:space:]]*(#|$)/ { next }
        inp { line = $0; sub(/^[[:space:]]+/, "", line); emit(line) }
    ' "$file" 2>/dev/null
}

# Read .standards.yml or fall back to .standards-config
# Sets global variables: STD_LANGUAGES, STD_AGENTS, STD_ROLE, STD_VERSION, STD_COVERAGE_MIN, STD_COVERAGE_DOMAIN, STD_ARCHITECTURE, STD_SECURITY, STD_LINT_EXCLUDE, STD_MEMBERS,
# STD_PROJECT_OVERVIEW and STD_KEY_COMMANDS (text assembled into {{PROJECT_OVERVIEW}} / {{KEY_COMMANDS}}),
# STD_HOOKS (declared git hook manager: standards | lefthook | husky | custom; empty when undeclared)
read_standards_config() {
    local project_root="$1"
    local yml="$project_root/.standards.yml"
    local legacy="$project_root/.standards-config"

    if [ -f "$yml" ]; then
        STD_VERSION=$(yaml_get "version" "$yml")
        STD_LANGUAGES=$(yaml_list "languages" "$yml")
        STD_AGENTS=$(yaml_list "agents" "$yml")
        # members: root-relative sub-roots with their own .standards.yml (#179).
        # Raw values; scripts/lib/members.sh normalizes and validates them.
        STD_MEMBERS=$(yaml_list "members" "$yml" | sed 's/[[:space:]]*$//')
        STD_ROLE=$(yaml_get "role" "$yml")
        STD_COVERAGE_MIN=$(yaml_nested_get "coverage" "minimum" "$yml")
        STD_COVERAGE_DOMAIN=$(yaml_nested_get "coverage" "domain" "$yml")
        STD_ARCHITECTURE=$(yaml_get "architecture" "$yml")
        STD_SECURITY=$(yaml_get "security" "$yml")
        # lint.exclude: space-separated list of project-relative path prefixes
        # or globs that lint-standards.sh check modules skip (see
        # scripts/lib/lint-files.sh for the matching rules).
        STD_LINT_EXCLUDE=$(yaml_nested_list "lint" "exclude" "$yml" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
        # project_overview / key_commands: persisted text the assembler writes
        # into {{PROJECT_OVERVIEW}} / {{KEY_COMMANDS}}, so a re-assembly
        # reproduces a filled-in config and its checksum stays stable (#183).
        STD_PROJECT_OVERVIEW=$(yaml_block_scalar "project_overview" "$yml")
        STD_KEY_COMMANDS=$(yaml_block_scalar "key_commands" "$yml")
        # hooks: the git hook manager that owns post-merge/commit-msg (#183).
        STD_HOOKS=$(yaml_block_scalar "hooks" "$yml")
        # Defaults
        STD_ROLE="${STD_ROLE:-service}"
        STD_COVERAGE_MIN="${STD_COVERAGE_MIN:-95}"
        STD_COVERAGE_DOMAIN="${STD_COVERAGE_DOMAIN:-100}"
        STD_ARCHITECTURE="${STD_ARCHITECTURE:-clean}"
        STD_SECURITY="${STD_SECURITY:-strict}"
        return 0
    elif [ -f "$legacy" ]; then
        # Backward compat: read .standards-config key=value format
        local cfg_role="" cfg_langs="" cfg_agents=""
        while IFS='=' read -r raw_key raw_value; do
            [[ -z "$raw_key" || "$raw_key" =~ ^[[:space:]]*# ]] && continue
            local key="${raw_key// /}"
            local value="${raw_value// /}"
            case "$key" in
                STANDARDS_ROLE)      cfg_role="$value" ;;
                STANDARDS_LANGUAGES) cfg_langs="$value" ;;
                STANDARDS_AGENTS)    cfg_agents="$value" ;;
            esac
        done < "$legacy"
        STD_ROLE="${cfg_role:-service}"
        STD_LANGUAGES=$(echo "${cfg_langs:-}" | tr ',' ' ')
        STD_AGENTS=$(echo "${cfg_agents:-}" | tr ',' ' ')
        STD_VERSION="1"
        STD_COVERAGE_MIN="95"
        STD_COVERAGE_DOMAIN="100"
        STD_ARCHITECTURE="clean"
        STD_SECURITY="strict"
        STD_LINT_EXCLUDE=""
        STD_MEMBERS=""
        STD_PROJECT_OVERVIEW=""
        STD_KEY_COMMANDS=""
        STD_HOOKS=""
        return 0
    else
        return 1
    fi
}
