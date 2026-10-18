#!/bin/bash
# cmake-presets.sh — CMakePresets.json reader for the lint-check modules.
#
# Sourced by scripts/lint-checks/cpp/*.sh. The hosts the linter runs on have
# bash 3.2 and awk but no JSON parser, so this is a brace-and-string scanner
# tuned to the CMakePresets schema, not a general parser. It answers one
# question: which configure preset does a CI step's `--preset <name>` select,
# and what does that preset — with everything it inherits — configure? That
# is what separates "the preset CI runs sets -Werror" from "some preset
# somewhere sets -Werror".
#
#   cmake_presets_dump <file>...
#       One record per preset, tab-separated:
#           section  name  inherits  configure  body
#       section   configurePresets | buildPresets | testPresets | workflowPresets
#       inherits  space-separated names (string or array form)
#       configure the configurePreset a build/test preset names, or the
#                 configure step of a workflow preset
#       body      the preset's JSON text on one line, `//` comment lines removed
#
#   cmake_preset_body <section> <name> <file>...
#       Prints the body of that one preset. Returns 1 when it is not defined.
#
#   cmake_preset_resolve [--workflow] <name> <file>...
#       Prints the body of the configure preset <name> denotes — itself, or
#       the configure preset behind the build/test/workflow preset of that
#       name (--workflow prefers the workflow preset when both exist) —
#       followed by the bodies of every preset it inherits, transitively.
#       Returns 1, printing nothing, when nothing resolves. CMakeUserPresets.json
#       is gitignored, so an unknown name is expected; callers say so rather
#       than guess.

cmake_presets_dump() {
    local f
    for f in "$@"; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        grep -vE '^[[:space:]]*//' "$f" 2>/dev/null | awk '
        # value(v, d): a completed string that turned out to be a value (not a
        # key) at container depth d. Depth 1 is the root object, 2 the
        # *Presets array, 3 a preset object, 4 its arrays/objects (inherits,
        # cacheVariables, steps), 5 a workflow step object.
        function value(v, d) {
            if (d == 3) {
                if (key[3] == "name") name = v
                else if (key[3] == "inherits") inherits = v
                else if (key[3] == "configurePreset") configure = v
            } else if (d == 4 && key[3] == "inherits") {
                inherits = (inherits == "") ? v : inherits " " v
            } else if (d == 5 && section == "workflowPresets") {
                if (key[5] == "type") stype = v
                else if (key[5] == "name") sname = v
            }
        }
        BEGIN { depth = 0; instr = 0; esc = 0; haspending = 0; collecting = 0; section = "" }
        {
            line = $0
            n = length(line)
            for (i = 1; i <= n; i++) {
                c = substr(line, i, 1)
                if (collecting) body = body ((c == "\t") ? " " : c)
                if (instr) {
                    if (esc) { esc = 0; str = str c; continue }
                    if (c == "\\") { esc = 1; str = str c; continue }
                    if (c == "\"") { instr = 0; pending = str; haspending = 1; pdepth = depth; continue }
                    str = str c
                    continue
                }
                if (c == " " || c == "\t" || c == "\r") continue
                if (haspending) {
                    haspending = 0
                    if (c == ":") { key[pdepth] = pending; continue }
                    value(pending, pdepth)
                }
                if (c == "\"") { instr = 1; str = ""; continue }
                if (c == "{" || c == "[") {
                    depth++
                    if (depth == 2 && c == "[") section = key[1]
                    if (depth == 3 && c == "{" && section ~ /Presets$/) {
                        collecting = 1; body = "{"; name = ""; inherits = ""; configure = ""
                    }
                    if (depth == 5 && c == "{" && section == "workflowPresets") { stype = ""; sname = "" }
                    continue
                }
                if (c == "}" || c == "]") {
                    if (depth == 5 && c == "}" && section == "workflowPresets" && stype == "configure") configure = sname
                    if (depth == 3 && c == "}" && collecting) {
                        collecting = 0
                        printf "%s\t%s\t%s\t%s\t%s\n", section, name, inherits, configure, body
                        body = ""
                    }
                    depth--
                    continue
                }
            }
            if (collecting) body = body " "
        }'
    done
}

cmake_preset_body() {
    local section="$1" name="$2"
    shift 2
    cmake_presets_dump "$@" | awk -F'\t' -v s="$section" -v n="$name" '
        $1 == s && $2 == n { print $5; found = 1; exit }
        END { exit found ? 0 : 1 }'
}

cmake_preset_resolve() {
    local prefer_workflow=false
    if [ "$1" = "--workflow" ]; then
        prefer_workflow=true
        shift
    fi
    local name="$1"
    shift
    local dump configure
    dump=$(cmake_presets_dump "$@")
    [ -n "$dump" ] || return 1

    if [ "$prefer_workflow" = true ]; then
        configure=$(printf '%s\n' "$dump" | awk -F'\t' -v n="$name" '
            $1 == "workflowPresets" && $2 == n && $4 != "" { print $4; exit }')
    fi
    if [ -z "$configure" ]; then
        configure=$(printf '%s\n' "$dump" | awk -F'\t' -v n="$name" '
            $1 == "configurePresets" && $2 == n { print n; exit }
            $2 == n && $4 != "" { print $4; exit }')
    fi
    [ -n "$configure" ] || return 1

    local queue="$configure" seen="" cur rec inh printed=false
    while [ -n "$queue" ]; do
        cur="${queue%% *}"
        if [ "$cur" = "$queue" ]; then queue=""; else queue="${queue#* }"; fi
        case " $seen " in *" $cur "*) continue ;; esac
        seen="$seen $cur"
        rec=$(printf '%s\n' "$dump" | awk -F'\t' -v n="$cur" '$1 == "configurePresets" && $2 == n { print; exit }')
        [ -n "$rec" ] || continue   # inherits a name only CMakeUserPresets.json defines
        printf '%s\n' "$rec" | cut -f5
        printed=true
        inh=$(printf '%s\n' "$rec" | cut -f3)
        [ -n "$inh" ] && queue="$queue${queue:+ }$inh"
    done
    [ "$printed" = true ]
}
