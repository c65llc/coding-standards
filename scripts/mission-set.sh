#!/bin/bash
# Set the active Antigravity Mission for the current project.
#
# Writes the Mission URL to .gemini/active_mission.log so other agents
# (Claude Code, Cursor, Aider, Codex) can read it and stay aligned with
# the in-flight Mission's scope.
#
# Usage:
#   ./scripts/mission-set.sh <mission-url>
#
# Example:
#   ./scripts/mission-set.sh https://antigravity.google.com/missions/abc123

set -euo pipefail

MISSION_URL="${1:-}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_FILE="$PROJECT_ROOT/.gemini/active_mission.log"

if [ -z "$MISSION_URL" ]; then
    echo "Usage: $(basename "$0") <mission-url>" >&2
    echo "Example: $(basename "$0") https://antigravity.google.com/missions/abc123" >&2
    exit 1
fi

# URL validation: must be HTTPS. We deliberately do NOT pin to a specific
# host pattern — Antigravity's URL scheme may evolve, and consumers may use
# self-hosted variants. HTTPS-only is the security-relevant invariant.
if [[ ! "$MISSION_URL" =~ ^https:// ]]; then
    echo "ERROR: Mission URL must use HTTPS (got: $MISSION_URL)" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

# Atomic write: stage in temp file, then move. Avoids partial reads from
# concurrent agents.
TMPFILE="$(mktemp "${LOG_FILE}.XXXXXX")"
trap 'rm -f "$TMPFILE"' EXIT
{
    echo "$MISSION_URL"
    echo "# Set: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$TMPFILE"
mv "$TMPFILE" "$LOG_FILE"
trap - EXIT

echo "✅ Active Mission set: $MISSION_URL"
echo "   Logged to: $LOG_FILE"
echo ""
echo "Other agents (Claude Code, Cursor, Aider, Codex) will read this file"
echo "to stay aligned with the in-flight Mission. Run mission-clear.sh when done."
