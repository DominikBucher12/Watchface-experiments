#!/usr/bin/env bash
set -euo pipefail

# Stable convenience entry point for the physical watchOS 27 experiment.
# This file is intentionally kept small; the guarded implementation lives in
# bootstrap-watchos27-device.sh and can evolve without changing user commands.
experiments_dir="$(cd "$(dirname "$0")" && pwd)"
command="${1:-preflight}"
if [[ $# -gt 0 ]]; then shift; fi

case "$command" in
    audit)
        exec bash "$experiments_dir/audit-watchos27-system-boundary.sh" "$@"
        ;;
    result)
        exec bash "$experiments_dir/bootstrap-watchos27-device.sh" \
            --result-only "$@"
        ;;
    preflight|install|select|rollback)
        exec bash "$experiments_dir/bootstrap-watchos27-device.sh" \
            --system-action "$command" "$@"
        ;;
    help|--help|-h)
        printf '%s\n' \
            "usage: $0 audit" \
            "       $0 [result|preflight|install|select|rollback] [--device ID]" \
            "" \
            "audit      inspect the static system trust boundary in DeviceSupport" \
            "result     fetch the last JSON without rebuilding or relaunching" \
            "preflight  read-only system collection probe (default)" \
            "install    add the candidate without selecting it" \
            "select     select only a persisted, resolvable candidate" \
            "rollback   remove the candidate and restore prior selection"
        ;;
    *)
        printf 'ERROR: unknown command: %s\n' "$command" >&2
        exit 2
        ;;
esac
