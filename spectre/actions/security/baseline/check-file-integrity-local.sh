#!/bin/bash
# Spectre Security Baseline — AIDE/File Integrity (additive)
# Uses suite state dirs by default; preserves evidence/log behavior.
set -euo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

LOG_DIR="${SECURITY_BASELINE_LOG_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre/security-baseline}"
AIDE_DIR="${SECURITY_AIDE_DIR:-$LOG_DIR/aide}"
AIDE_DB="$AIDE_DIR/aide.db.gz"
AIDE_LOG="$AIDE_DIR/aide.log"
AIDE_CONF="$AIDE_DIR/aide.conf"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$AIDE_DIR"

echo "=== AIDE File Integrity Check - $DATE ==="
command -v aide >/dev/null 2>&1 || { echo "AIDE not installed; skipping integrity check"; exit 0; }

if [ ! -f "$AIDE_CONF" ]; then
  cat > "$AIDE_CONF" << EOF
# AIDE Configuration for baseline integrity (suite-managed state)
database_in=file:$AIDE_DIR/aide.db.gz
database_out=file:$AIDE_DIR/aide.db.new.gz
gzip_dbout=yes
report_url=file:$AIDE_DIR/aide.log
report_url=stdout
EOF
fi

if [ ! -f "$AIDE_DB" ]; then
  echo "No AIDE database found. Initializing..."
  aide --init --config="$AIDE_CONF" 2>&1 | tail -20 || true
  [ -f "$AIDE_DIR/aide.db.new.gz" ] && cp "$AIDE_DIR/aide.db.new.gz" "$AIDE_DB"
fi

echo "Checking file integrity..."
set +e
aide --check --config="$AIDE_CONF" > "$AIDE_LOG" 2>&1
AIDE_EXIT=$?
set -e
if [ $AIDE_EXIT -eq 0 ]; then
  echo "File integrity check PASSED"
else
  echo "WARNING: File integrity changes detected (exit $AIDE_EXIT)"
  echo "Check $AIDE_LOG for details"
  tail -120 "$AIDE_LOG" || true
fi
[ -f "$AIDE_DIR/aide.db.new.gz" ] && cp "$AIDE_DIR/aide.db.new.gz" "$AIDE_DB"
echo "AIDE check completed (exit code: $AIDE_EXIT)"
exit $AIDE_EXIT
