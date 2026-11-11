#!/bin/bash
# Run the Spectre security agent audit to refresh recorded scan state.
# Intended for scheduled/regular execution so dashboard/prometheus
# `security_last_scan_timestamp` (agent-recorded) stays current.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_BIN="${SPECTRE_BIN:-$(command -v spectre 2>/dev/null || echo spectre)}"

log() { echo "[agent-security-audit] $*"; }

rc=0
log "running: $SPECTRE_BIN security --audit"
if ! "$SPECTRE_BIN" security --audit; then
    rc=$?
    log "spectre security --audit exited with status $rc"
fi

# Refresh exporter so Prometheus/dashboard reflects the new scan promptly.
if "$SPECTRE_BIN" run prometheus/security-metrics-exporter >/dev/null 2>&1; then
    log "security metrics exporter refreshed"
else
    log "warning: failed to refresh prometheus/security-metrics-exporter"
    [ "$rc" -eq 0 ] && rc=1
fi

exit "$rc"
