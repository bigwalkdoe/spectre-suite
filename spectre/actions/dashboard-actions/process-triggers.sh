#!/usr/bin/env bash
# Consumes dashboard action trigger files (written by the dashboard-actions
# container) and runs the allowlisted script for each. Install with the systemd
# path/service units in systemd/dashboard-actions/.
#
# Security: only actions present in the allowlist are executed. Trigger files
# are moved to processed/ or failed/ after handling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SPECTRE_REPO_ROOT:-"${REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"}"
TRIGGERS_DIR="${TRIGGERS_DIR:-$REPO_ROOT/dashboard-actions/triggers}"
PROCESSED_DIR="$TRIGGERS_DIR/processed"
FAILED_DIR="$TRIGGERS_DIR/failed"
LOG_TAG="spectre-dashboard-actions"

mkdir -p "$PROCESSED_DIR" "$FAILED_DIR"

# Allowlist: action -> repo-relative script (must match web-dashboard/actions-backend/server.py)
allowlisted_script() {
    case "$1" in
        backup) echo "scripts/backups/run-missed-backups.sh" ;;
        maintenance) echo "scripts/maintenance/run-maintenance.sh" ;;
        security-scan) echo "scripts/security/scan-docker-images.sh" ;;
        *) return 1 ;;
    esac
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

    script_rel=$(allowlisted_script "$action" || true)
    if [ -z "$script_rel" ]; then
        log "rejected non-allowlisted action '$action': $base"
        mv "$trigger" "$FAILED_DIR/$base"
        continue
    fi

    script="$REPO_ROOT/$script_rel"
    if [ ! -x "$script" ]; then
        log "allowlisted script not executable/missing: $script_rel ($base)"
        mv "$trigger" "$FAILED_DIR/$base"
        continue
    fi

    log "executing allowlisted action '$action' via $script_rel ($base)"
    if (cd "$REPO_ROOT" && "$script"); then
        log "action '$action' completed: $base"
        mv "$trigger" "$PROCESSED_DIR/$base"
    else
        status=$?
        log "action '$action' failed (exit $status): $base"
        mv "$trigger" "$FAILED_DIR/$base"
    fi
done
