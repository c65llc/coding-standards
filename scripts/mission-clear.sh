#!/bin/bash
# Clear the active Antigravity Mission for the current project.
#
# Truncates .gemini/active_mission.log to empty (preserves the file path
# so subsequent reads return cleanly) and signals to other agents that no
# Mission is in flight.
#
# Usage:
#   ./scripts/mission-clear.sh

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_FILE="$PROJECT_ROOT/.gemini/active_mission.log"

# Ensure the parent directory exists, then truncate (or create empty).
# Truncate rather than delete: keeps the path stable so readers
# (other agents checking for an active Mission) never error on missing
# file. An empty file unambiguously means "no active Mission".
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

echo "✅ Active Mission cleared: $LOG_FILE"
