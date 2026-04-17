#!/bin/bash
# Emit .standards-pending/MERGE_PLAN.md — the briefing that tells the user's
# preferred LLM what to finish after setup.sh completes. Read by the
# merge-standards skill (Claude Code), .cursor/commands/merge-standards.md
# (Cursor), and surfaced via `make merge-standards`.

# Usage:
#   write_merge_plan <project_root> <pending_list> <detected_agents> <requested_agents>
#
# pending_list: space-separated basenames staged in .standards-pending/
# detected_agents: space-separated agent names (as emitted by detect_installed_agents)
# requested_agents: space- or comma-separated (ASSEMBLED_AGENTS_LIST uses commas)
write_merge_plan() {
    local root="$1"
    local pending_list="$2"
    local detected="$3"
    local requested="$4"
    local pending_dir="$root/.standards-pending"

    [ -n "$pending_list" ] || return 0
    mkdir -p "$pending_dir"

    local plan="$pending_dir/MERGE_PLAN.md"
    {
        echo "# Standards Setup — Merge Plan"
        echo ""
        echo "Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo ""
        echo "setup.sh detected existing agent configs that differ from the assembled"
        echo "versions. They have NOT been overwritten. Each pending file is staged here"
        echo "alongside this plan."
        echo ""
        echo "## How to finish"
        echo ""
        echo "- **Claude Code:** run \`/merge-standards\`"
        echo "- **Cursor:** run the \`merge-standards\` command"
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
        echo "## Open questions for your LLM"
        echo ""
        echo "1. Fill in any \`<!-- TODO(standards): -->\` markers in the pending files"
        echo "   (project overview, key commands)."
        echo "2. For each pending file, decide: accept the assembled version, keep the"
        echo "   existing, or merge section-by-section."
        echo "3. After merging, delete the pending file and update \`.standards-checksums\`."
        echo ""
    } > "$plan"
}
