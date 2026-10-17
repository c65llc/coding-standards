#!/bin/bash
# Guard against running consumer-facing scripts from inside the .standards/
# submodule (shared by setup.sh, sync-standards.sh and diff-standards.sh).
#
# When a script is invoked with its working directory inside .standards/ (the
# v1.0-era `make -C .standards sync-standards` wrapper did exactly this),
# `git rev-parse --show-toplevel` resolves to the submodule checkout itself.
# PROJECT_ROOT then points at .standards/ and every write — assembled agent
# configs, .standards.yml, checksums — lands in the standards checkout instead
# of the consumer project. Refuse loudly rather than silently doing the wrong
# thing.
#
# Usage:
#   source "$SCRIPT_DIR/lib/guard.sh"
#   refuse_if_inside_standards_dir "$PROJECT_ROOT" "sync-standards.sh" || exit 2

refuse_if_inside_standards_dir() {
    local project_root="$1"
    local script_name="${2:-$(basename "$0")}"

    if [ "$(basename "$project_root")" = ".standards" ]; then
        {
            echo "❌ Error: $script_name is running from inside the standards checkout."
            echo "   Project root resolved to: $project_root"
            echo "   Every write would land in the .standards/ submodule instead of your project."
            echo ""
            echo "   Run it from your project root instead:"
            echo "     ./.standards/scripts/$script_name"
        } >&2
        return 2
    fi
    return 0
}
