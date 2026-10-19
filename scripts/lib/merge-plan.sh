#!/bin/bash
# Emit .standards-pending/MERGE_PLAN.md — the briefing that tells the user's
# preferred LLM what to finish after setup.sh completes. Read by the
# merge-standards skill (standards/skills/merge-standards.md, emitted per agent
# by assemble-skills.sh) and surfaced via `make merge-standards`.

# Usage:
#   write_merge_plan <project_root> <pending_list> <detected_agents> <requested_agents> [migration_notes] [containerized_notes]
#
# pending_list: space-separated project-relative paths staged in .standards-pending/
#   (basenames for the root agent configs, nested paths such as
#   scripts/init-workspace.sh for files the containerized kit ships)
# detected_agents: space-separated agent names (as emitted by detect_installed_agents)
# requested_agents: space- or comma-separated (ASSEMBLED_AGENTS_LIST uses commas)
# migration_notes: newline-separated Markdown bullets from setup.sh --migrate
#   (#184): what was rewritten or converted, and the removed-standard
#   references left for a manual decision. Rendered as a Migration section.
# containerized_notes: newline-separated Markdown bullets from setup.sh
#   --containerized (#159): the kit files that already existed and differ, kept
#   in place with the kit's version staged. Rendered as its own section.
write_merge_plan() {
    local root="$1"
    local pending_list="$2"
    local detected="$3"
    local requested="$4"
    local migration_notes="${5:-}"
    local containerized_notes="${6:-}"
    local pending_dir="$root/.standards-pending"

    [ -n "$pending_list" ] || [ -n "$migration_notes" ] || [ -n "$containerized_notes" ] || return 0
    mkdir -p "$pending_dir"

    local plan="$pending_dir/MERGE_PLAN.md"
    {
        echo "# Standards Setup — Merge Plan"
        echo ""
        echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo ""
        echo "setup.sh found existing files (agent configs, or files the containerized"
        echo "agent-dev kit ships) that differ from the versions it would write. They have"
        echo "NOT been overwritten. Each pending file is staged here alongside this plan."
        echo ""
        echo "## How to finish"
        echo ""
        echo "- **Claude Code:** run \`/merge-standards\`"
        echo "- **Cursor:** run the \`merge-standards\` command"
        echo "- **Copilot:** run the \`merge-standards\` prompt (\`.github/prompts/merge-standards.prompt.md\`)"
        echo "- **Codex / Gemini / Aider:** follow the \`merge-standards\` runbook listed in your config's Skills section"
        echo "- **Any agent / manual:** \`make merge-standards\` or read the steps below"
        echo ""
        echo "## Pending files"
        echo ""
        for f in $pending_list; do
            echo "- \`.standards-pending/$f\` → merge into \`$f\`"
        done
        echo ""
        echo "## Detected agents"
        echo ""
        if [ -n "$detected" ]; then
            for a in $detected; do echo "- $a"; done
        else
            echo "_(none detected — setup ran with explicit \`--agents\`)_"
        fi
        echo ""
        echo "## Agents written this run"
        echo ""
        for a in $(echo "$requested" | tr ',' ' '); do echo "- $a"; done
        echo ""
        if [ -n "$migration_notes" ]; then
            echo "## Migration (pre-1.2 install, setup.sh --migrate)"
            echo ""
            printf '%s\n' "$migration_notes"
            echo ""
        fi
        if [ -n "$containerized_notes" ]; then
            echo "## Containerized agent-dev kit (setup.sh --containerized)"
            echo ""
            printf '%s\n' "$containerized_notes"
            echo ""
        fi
        echo "## Open questions for your LLM"
        echo ""
        echo "1. Fill in any \`<!-- TODO(standards): -->\` markers in the pending files"
        echo "   (project overview, key commands) — write the text to \`.standards.yml\` as"
        echo "   \`project_overview: |\` / \`key_commands: |\` so re-assembly reproduces it and"
        echo "   the checksum stays stable, then re-run the sync or replace the markers."
        echo "2. For each pending file, decide: accept the assembled version, keep the"
        echo "   existing, merge section-by-section, or declare it hand-curated with"
        echo "   \`managed: { <file>: false }\` in \`.standards.yml\` (sync then leaves it alone)."
        echo "3. After merging, delete the pending file and update \`.standards-checksums\`."
        echo ""
    } > "$plan"
}
