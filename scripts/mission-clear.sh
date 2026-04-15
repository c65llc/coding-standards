#!/bin/bash
# Clear the active Antigravity Mission for the current project.
#
# Truncates .gemini/active_mission.log to empty (preserves the file path
# so subsequent reads return cleanly) and signals to other agents that no
# Mission is in flight.
#
# Usage:
#   ./scripts/mission-clear.sh

set -e

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_FILE="$PROJECT_ROOT/.gemini/active_mission.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "No active Mission to clear (log file missing): $LOG_FILE"
    exit 0
fi

# Truncate rather than delete: keeps the path stable for readers, and the
# file is gitignored anyway. An empty file = no active Mission.
: > "$LOG_FILE"

echo "✅ Active Mission cleared: $LOG_FILE"
