#!/bin/bash
# Detect which AI agents are already in use in a project by probing for their
# canonical config files. Called by setup.sh when --agents detect (default).
# Output: space-separated agent names (claude-code, cursor, copilot, gemini,
# codex, aider). Empty output = greenfield project.

detect_installed_agents() {
    local root="${1:-$(pwd)}"
    local agents=()

    [ -f "$root/CLAUDE.md" ]                         && agents+=("claude-code")
    [ -f "$root/.cursorrules" ]                      && agents+=("cursor")
    [ -d "$root/.cursor" ]                           && agents+=("cursor")
    [ -f "$root/.github/copilot-instructions.md" ]   && agents+=("copilot")
    [ -f "$root/.gemini/GEMINI.md" ]                 && agents+=("gemini")
    [ -d "$root/.gemini" ]                           && agents+=("gemini")
    [ -f "$root/AGENTS.md" ]                         && agents+=("codex")
    [ -f "$root/.aiderrc" ]                          && agents+=("aider")
    [ -f "$root/.aider-instructions.md" ]            && agents+=("aider")

    printf '%s\n' "${agents[@]}" | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}
