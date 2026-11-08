#!/usr/bin/env bash
# Consumes dashboard action trigger files (written by the dashboard-actions
# container) and dispatches the allowlisted spectre job for each. Install with
# the systemd path/service units in systemd/dashboard-actions/ (or via
# `spectre run dashboard-actions/process-triggers`).
#
# Security: only actions present in the allowlist are executed. Trigger files
# are moved to processed/ or failed/ after handling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SPECTRE_REPO_ROOT:-"${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"}"
TRIGGERS_DIR="${TRIGGERS_DIR:-$REPO_ROOT/dashboard-actions/triggers}"
PROCESSED_DIR="$TRIGGERS_DIR/processed"
FAILED_DIR="$TRIGGERS_DIR/failed"
LOG_TAG="spectre-dashboard-actions"

mkdir -p "$PROCESSED_DIR" "$FAILED_DIR"

# Allowlist: action -> spectre job (must match web-dashboard/actions-backend/server.py)
allowlisted_job() {
    case "$1" in
        backup) echo "backups/run-missed-backups" ;;
        maintenance) echo "maintenance/run-maintenance" ;;
        security-scan) echo "security/scan-docker-images" ;;
        *) return 1 ;;
    esac
}

spectre_cmd() {
    if command -v spectre >/dev/null 2>&1; then
        spectre "$@"
    else
        PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" python3 -m spectre.cli.main "$@"
    fi
}

log() { logger -t "$LOG_TAG" -- "$*" 2>/dev/null || echo "$LOG_TAG: $*" >&2; }

shopt -s nullglob
for trigger in "$TRIGGERS_DIR"/*.json; do
    [ -f "$trigger" ] || continue
    base="$(basename "$trigger")"

    action=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('action',''))" "$trigger" 2>/dev/null || true)
    if [ -z "$action" ]; then
        log "invalid trigger (no action): $base"
        mv "$trigger" "$FAILED_DIR/$base"
        continue
    fi

    job=$(allowlisted_job "$action" || true)
    if [ -z "$job" ]; then
        log "rejected non-allowlisted action '$action': $base"
        mv "$trigger" "$FAILED_DIR/$base"
        continue
    fi

    log "dispatching allowlisted action '$action' via spectre run $job ($base)"
    if (cd "$REPO_ROOT" && spectre_cmd run "$job"); then
        log "action '$action' completed: $base"
        mv "$trigger" "$PROCESSED_DIR/$base"
    else
        status=$?
        log "action '$action' failed (exit $status): $base"
        mv "$trigger" "$FAILED_DIR/$base"
    fi
done
