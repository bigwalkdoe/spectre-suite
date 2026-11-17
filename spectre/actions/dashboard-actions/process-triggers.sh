#!/usr/bin/env bash
# Consumes dashboard action trigger files (written by the dashboard-actions
# container) and dispatches the allowlisted spectre job for each. Install with
# the systemd path/service units in systemd/dashboard-actions/ (or via
# `spectre run dashboard-actions/process-triggers`).
#
# Security: only actions present in the allowlist are executed. Trigger files
# are moved to processed/ or failed/ after handling. Run status/result records
# are written as JSON under $TRIGGERS_DIR/runs/ for read-only UI/API consumption.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SPECTRE_REPO_ROOT:-"${REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"}"
TRIGGERS_DIR="${TRIGGERS_DIR:-$REPO_ROOT/dashboard-actions/triggers}"
PROCESSED_DIR="$TRIGGERS_DIR/processed"
FAILED_DIR="$TRIGGERS_DIR/failed"
RUNS_DIR="$TRIGGERS_DIR/runs"
LOG_TAG="spectre-dashboard-actions"

mkdir -p "$PROCESSED_DIR" "$FAILED_DIR" "$RUNS_DIR"

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

json_field() {
    python3 - "$1" "$2" <<'PY'
import json, sys
path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    v = data.get(key, '')
    if v is None:
        v = ''
    print(v)
except Exception:
    print('')
PY
}

write_run_status() {
    local trigger_file="$1" status="$2" exit_code="${3:-}" message="${4:-}"
    python3 - "$trigger_file" "$RUNS_DIR" "$status" "$exit_code" "$message" <<'PY'
import json, os, sys, tempfile
from datetime import datetime, timezone

trigger_file, runs_dir, status, exit_code, message = sys.argv[1:6]
try:
    with open(trigger_file, 'r', encoding='utf-8') as f:
        trig = json.load(f)
except Exception:
    trig = {}

run_id = str(trig.get('id') or os.path.splitext(os.path.basename(trigger_file))[0])
path = os.path.join(runs_dir, f"{run_id}.json")
prev = {}
if os.path.exists(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            prev = json.load(f)
    except Exception:
        prev = {}

now = datetime.now(timezone.utc).isoformat()
msg = (message or '')[:500]
record = {
    'id': run_id,
    'action': trig.get('action') or prev.get('action') or '',
    'script': trig.get('script') or prev.get('script') or '',
    'requestedAt': trig.get('requestedAt') or prev.get('requestedAt'),
    'startedAt': prev.get('startedAt'),
    'finishedAt': prev.get('finishedAt'),
    'status': status,
    'exitCode': prev.get('exitCode'),
    'message': msg or prev.get('message', ''),
    'reason': (trig.get('reason') or prev.get('reason') or '')[:200] or None,
    'actor': (trig.get('actor') or prev.get('actor') or '')[:120] or None,
    'triggerFile': os.path.basename(trigger_file),
}
if status == 'running':
    record['startedAt'] = now
    record['finishedAt'] = None
    record['exitCode'] = None
if status in ('succeeded', 'failed', 'rejected'):
    record['finishedAt'] = now
    if record['startedAt'] is None and status != 'rejected':
        record['startedAt'] = now
    if exit_code != '':
        try:
            record['exitCode'] = int(exit_code)
        except Exception:
            record['exitCode'] = exit_code
    else:
        record['exitCode'] = 0 if status == 'succeeded' else record.get('exitCode')
if status == 'queued':
    record['finishedAt'] = None

os.makedirs(runs_dir, exist_ok=True)
fd, tmp = tempfile.mkstemp(prefix=f"{run_id}.", suffix='.tmp', dir=runs_dir)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(record, f, indent=2, sort_keys=True)
        f.write('\n')
    os.replace(tmp, path)
finally:
    try:
        if os.path.exists(tmp):
            os.unlink(tmp)
    except Exception:
        pass
PY
}

shopt -s nullglob
for trigger in "$TRIGGERS_DIR"/*.json; do
    [ -f "$trigger" ] || continue
    base="$(basename "$trigger")"

    # Skip non-trigger JSONs defensively (runs dir is separate, but be safe)
    action=$(json_field "$trigger" "action")
    if [ -z "$action" ]; then
        log "invalid trigger (no action): $base"
        write_run_status "$trigger" "rejected" "" "Invalid trigger: missing action"
        mv "$trigger" "$FAILED_DIR/$base"
        continue
    fi

    job=$(allowlisted_job "$action" || true)
    if [ -z "$job" ]; then
        log "rejected non-allowlisted action '$action': $base"
        write_run_status "$trigger" "rejected" "" "Action not allowlisted"
        mv "$trigger" "$FAILED_DIR/$base"
        continue
    fi

    log "dispatching allowlisted action '$action' via spectre run $job ($base)"
    write_run_status "$trigger" "running" "" "Dispatching allowlisted action"
    if (cd "$REPO_ROOT" && spectre_cmd run "$job"); then
        log "action '$action' completed: $base"
        write_run_status "$trigger" "succeeded" "0" "Action completed successfully"
        mv "$trigger" "$PROCESSED_DIR/$base"
    else
        status=$?
        log "action '$action' failed (exit $status): $base"
        write_run_status "$trigger" "failed" "$status" "Action failed (see host logs)"
        mv "$trigger" "$FAILED_DIR/$base"
    fi
done
