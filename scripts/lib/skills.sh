#!/bin/bash
# scripts/lib/skills.sh — agent-neutral skills (standards/skills/*.md) rendered
# per agent (proc-04, #194). Shared by assemble-skills.sh (file-based agents)
# and assemble-config.sh (agents that read one config file).
#
# Source this file; do not execute it directly. bash 3.2 compatible.
#
# A skill is a Markdown runbook with a YAML frontmatter carrying `name:` and
# `description:`. The same file is emitted in each agent's own shape:
#
#   claude-code  .claude/skills/<name>.md            frontmatter kept as is
#   cursor       .cursor/commands/<name>.md          `description:` frontmatter only
#   copilot      .github/prompts/<name>.prompt.md    `description:` frontmatter only
#   codex, gemini, aider                             a "## Skills" index in the
#                                                    assembled config (AGENTS.md,
#                                                    .gemini/GEMINI.md,
#                                                    .aider-instructions.md)
#
#   skills_list <skills_dir>                → skill names, one per line, sorted
#   skill_field <file> <key>                → a frontmatter scalar
#   skill_body <file>                       → everything after the frontmatter
#   skill_section <file> <heading>          → the body of one "## <heading>"
#   skills_agent_target <agent> <name>      → project-relative output path, or
#                                             nothing for index-only agents
#   render_skill_for_agent <agent> <file>   → the file as that agent reads it
#   render_skills_index <skills_dir> <ref>  → the "## Skills" section body;
#                                             <ref> is the path prefix the
#                                             runbooks are reachable at

# Agents whose skills are files the agent discovers on its own.
SKILLS_FILE_AGENTS="claude-code cursor copilot"
# Agents that read one config file: the skills are indexed inside it.
SKILLS_INDEX_AGENTS="codex gemini aider"

# skills_list <skills_dir> — skill names (basename without .md), sorted.
skills_list() {
    local dir="$1" f
    [ -d "$dir" ] || return 0
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
            README.md) continue ;;
        esac
        basename "$f" .md
    done | LC_ALL=C sort
}

# skill_field <file> <key> — the value of a top-level frontmatter key
# (`key: value`, quotes stripped). Prints nothing without frontmatter or key.
skill_field() {
    awk -v k="$2" '
        NR == 1 { if ($0 != "---") exit; next }
        /^---[[:space:]]*$/ { exit }
        index($0, k ":") == 1 {
            v = substr($0, length(k) + 2)
            sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/ || v ~ /^\x27.*\x27$/) v = substr(v, 2, length(v) - 2)
            print v; exit
        }
    ' "$1"
}

# skill_body <file> — the Markdown after the closing frontmatter fence, with
# leading blank lines dropped. A file without frontmatter is printed whole.
skill_body() {
    awk '
        NR == 1 && $0 == "---" { infm = 1; next }
        infm && /^---[[:space:]]*$/ { infm = 0; started = 0; next }
        infm { next }
        !started && /^[[:space:]]*$/ { next }
        { started = 1; print }
    ' "$1"
}

# skill_section <file> <heading> — the lines under "## <heading>" up to the
# next "## " heading, leading and trailing blank lines dropped.
skill_section() {
    skill_body "$1" | awk -v h="## $2" '
        inb && /^## / { exit }
        inb { n++; lines[n] = $0; next }
        $0 == h { inb = 1 }
        END {
            s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
            while (n >= s && lines[n] ~ /^[[:space:]]*$/) n--
            for (i = s; i <= n; i++) print lines[i]
        }
    '
}

# skills_agent_target <agent> <name> — the project-relative path a file-based
# agent reads skill <name> from; prints nothing for index-only agents.
skills_agent_target() {
    case "$1" in
        claude-code) printf '.claude/skills/%s.md\n' "$2" ;;
        cursor)      printf '.cursor/commands/%s.md\n' "$2" ;;
        copilot)     printf '.github/prompts/%s.prompt.md\n' "$2" ;;
        *)           return 0 ;;
    esac
}

# skills_agent_dir <agent> — the directory the agent's skill files live in.
skills_agent_dir() {
    case "$1" in
        claude-code) printf '.claude/skills\n' ;;
        cursor)      printf '.cursor/commands\n' ;;
        copilot)     printf '.github/prompts\n' ;;
        *)           return 0 ;;
    esac
}

# skills_agent_known <agent> — true for every agent the skills tooling knows.
skills_agent_known() {
    case " $SKILLS_FILE_AGENTS $SKILLS_INDEX_AGENTS " in
        *" $1 "*) return 0 ;;
        *)        return 1 ;;
    esac
}

# render_skill_for_agent <agent> <file> — the skill as <agent> reads it.
# Claude Code keeps the frontmatter verbatim (name + description). Cursor
# commands and Copilot prompt files take a `description:`-only frontmatter;
# their name is the file name.
render_skill_for_agent() {
    local agent="$1" file="$2" desc
    case "$agent" in
        claude-code)
            cat "$file"
            ;;
        cursor|copilot)
            desc=$(skill_field "$file" description)
            printf -- '---\n'
            printf 'description: %s\n' "$desc"
            printf -- '---\n\n'
            skill_body "$file"
            ;;
        *)
            return 1
            ;;
    esac
}

# render_skills_index <skills_dir> <runbook_ref> — the body of the "## Skills"
# section for agents that read one config file: each skill's name,
# description and triggers, and where its full runbook lives.
render_skills_index() {
    local dir="$1" ref="$2" name file desc when
    [ -d "$dir" ] || return 0
    printf 'Runbooks the standards ship for recurring tasks. Read the runbook before carrying one out and report as it says; each is also installed as a native skill, command or prompt for agents that support them.\n'
    for name in $(skills_list "$dir"); do
        file="$dir/$name.md"
        desc=$(skill_field "$file" description)
        printf '\n### %s\n\n' "$name"
        if [ -n "$desc" ]; then
            printf '%s\n' "$desc"
        fi
        when=$(skill_section "$file" "When to Use")
        if [ -n "$when" ]; then
            printf '\nUse when:\n\n'
            # Bullets stay bullets; a paragraph becomes one bullet per line.
            printf '%s\n' "$when" | awk '
                /^[[:space:]]*$/ { next }
                /^[-*] / { print; next }
                /^[[:space:]]+[-*] / { print; next }
                { print "- " $0 }
            '
        fi
        printf '\nRunbook: `%s/%s.md`\n' "$ref" "$name"
    done
}
