#!/bin/bash
# Lightweight security posture maintenance (15-minute cadence)
#
# Runs a quick posture refresh/check cycle, writes status summary/markers, and
# applies only safe, idempotent self-remediations by default (bounded to its
# managed state dirs and idempotent exporter refresh). No service/container
# restarts, no firewall/SELinux/AppArmor/network changes, no package changes,
# no broad config rewrites, and no risky/destructive actions.
set -uo pipefail

DRY_RUN=0
STATE_DIR="${SECURITY_POSTURE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre-suite/security-posture}"
TMP_STALE_HOURS="${SECURITY_POSTURE_TMP_STALE_HOURS:-24}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run|--check-only]

Options:
  --dry-run, --check-only  Report posture state/remediations without applying
                           filesystem cleanup/remediation side effects
  -h, --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run|--check-only) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$TMP_STALE_HOURS" in
    ''|*[!0-9]*) echo "ERROR: SECURITY_POSTURE_TMP_STALE_HOURS must be a non-negative integer" >&2; exit 2 ;;
esac

overall_ok=1
checks_run=()
checks_skipped=()
checks_failed=()
remediations_applied=()
remediations_skipped=()
remediations_would=()

log() { echo "$*"; }
warn() { echo "WARN: $*" >&2; }
record_failure() { overall_ok=0; }

now_ts() { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%s"; }
now_epoch() { date +%s; }

MANAGED_TMP="$STATE_DIR/tmp"
STATUS_FILE="$STATE_DIR/status.txt"
SUMMARY_FILE="$STATE_DIR/summary.txt"

ensure_dirs() {
    if [ "$DRY_RUN" -eq 1 ]; then
        remediations_would+=("ensure_dirs:$STATE_DIR")
        remediations_would+=("ensure_dirs:$MANAGED_TMP")
        log "DRY RUN: would ensure managed state dirs: $STATE_DIR $MANAGED_TMP"
        return 0
    fi
    if mkdir -p "$STATE_DIR" "$MANAGED_TMP"; then
        remediations_applied+=("ensure_dirs")
        return 0
    else
        warn "failed to create managed state dirs"
        record_failure
        return 1
    fi
}

cleanup_stale_tmp() {
    # Only remove stale temp files in managed posture temp area (not arbitrary files)
    if [ ! -d "$MANAGED_TMP" ]; then
        remediations_skipped+=("cleanup_stale_tmp:no_managed_tmp")
        return 0
    fi
    local stale_minutes count
    stale_minutes=$((TMP_STALE_HOURS * 60))
    count=0

    if [ "$DRY_RUN" -eq 1 ]; then
        # report only, no side effects
        while IFS= read -r -d '' f; do
            [ -f "$f" ] || continue
            count=$((count + 1))
            log "DRY RUN: would remove stale managed temp file (> ${TMP_STALE_HOURS}h): $f"
        done < <(find "$MANAGED_TMP" -mindepth 1 -maxdepth 1 -type f -mmin "+${stale_minutes}" -print0 2>/dev/null)
        if [ "$count" -gt 0 ]; then
            remediations_would+=("cleanup_stale_tmp:${count}")
        else
            remediations_skipped+=("cleanup_stale_tmp:none")
        fi
        return 0
    fi

    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        if rm -f -- "$f"; then
            count=$((count + 1))
            log "removed stale managed temp file: $f"
        else
            warn "failed to remove stale managed temp file: $f"
            record_failure
        fi
    done < <(find "$MANAGED_TMP" -mindepth 1 -maxdepth 1 -type f -mmin "+${stale_minutes}" -print0 2>/dev/null)

    if [ "$count" -gt 0 ]; then
        remediations_applied+=("cleanup_stale_tmp:${count}")
    else
        remediations_skipped+=("cleanup_stale_tmp:none")
    fi
    return 0
}

run_refresh() {
    local cmd="$1" label="$2"
    checks_run+=("$label")
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY RUN: would refresh posture signal via: $cmd"
        remediations_would+=("refresh:$label")
        return 0
    fi
    if ! command -v spectre >/dev/null 2>&1; then
        log "posture refresh skipped (spectre unavailable): $label"
        checks_skipped+=("$label:spectre_unavailable")
        return 0
    fi
    # shellcheck disable=SC2086
    if spectre $cmd >/dev/null 2>&1; then
        log "posture refresh ok: $label"
        remediations_applied+=("refresh:$label")
        return 0
    else
        warn "posture refresh failed: $label"
        checks_failed+=("$label")
        record_failure
        return 1
    fi
}

write_status() {
    local ts result
    ts="$(now_ts)"
    result="ok"
    [ "$overall_ok" -eq 1 ] || result="failed"

    if [ "$DRY_RUN" -eq 1 ]; then
        log ""
        log "DRY RUN summary (no files written):"
        log "  timestamp: $ts"
        log "  checks_run: ${checks_run[*]:-none}"
        log "  checks_skipped: ${checks_skipped[*]:-none}"
        log "  checks_failed: ${checks_failed[*]:-none}"
        log "  remediations_would: ${remediations_would[*]:-none}"
        log "  overall_result: $result"
        return 0
    fi

    {
        echo "timestamp=$ts"
        echo "timestamp_epoch=$(now_epoch)"
        echo "checks_run=${checks_run[*]:-none}"
        echo "checks_skipped=${checks_skipped[*]:-none}"
        echo "checks_failed=${checks_failed[*]:-none}"
        echo "remediations_applied=${remediations_applied[*]:-none}"
        echo "remediations_skipped=${remediations_skipped[*]:-none}"
        echo "overall_result=$result"
        echo "dry_run=0"
    } > "$STATUS_FILE.tmp" && mv "$STATUS_FILE.tmp" "$STATUS_FILE"

    {
        echo "Security posture maintenance summary"
        echo "timestamp: $ts"
        echo "checks run: ${checks_run[*]:-none}"
        echo "checks skipped: ${checks_skipped[*]:-none}"
        echo "checks failed: ${checks_failed[*]:-none}"
        echo "remediations applied: ${remediations_applied[*]:-none}"
        echo "remediations skipped: ${remediations_skipped[*]:-none}"
        echo "overall result: $result"
    } > "$SUMMARY_FILE.tmp" && mv "$SUMMARY_FILE.tmp" "$SUMMARY_FILE"

    log "wrote status: $STATUS_FILE"
    log "wrote summary: $SUMMARY_FILE"
}

log "Security posture maintenance"
log "  mode      : $([ "$DRY_RUN" -eq 1 ] && echo check-only/dry-run || echo remediate)"
log "  state dir : $STATE_DIR"
log "  tmp stale : ${TMP_STALE_HOURS}h"
log ""

# Lightweight posture refresh/check steps (graceful when optional components unavailable)
run_refresh "run prometheus/security-baseline-metrics-exporter" "prometheus/security-baseline-metrics-exporter"
run_refresh "run prometheus/security-metrics-exporter" "prometheus/security-metrics-exporter"

# Safe, idempotent remediations bounded to managed dirs/state
ensure_dirs
cleanup_stale_tmp

write_status

if [ "$overall_ok" -eq 1 ]; then
    log "overall result: ok"
    exit 0
else
    log "overall result: failed"
    exit 1
fi
