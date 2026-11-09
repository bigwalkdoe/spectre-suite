#!/bin/bash
# Install per-user systemd timer for the security baseline metrics exporter.
# Dispatches via `spectre run prometheus/security-baseline-metrics-exporter`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SPECTRE_REPO_ROOT:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="spectre-baseline-metrics.service"
TIMER_NAME="spectre-baseline-metrics.timer"
SPECTRE_BIN="${SPECTRE_BIN:-$(command -v spectre 2>/dev/null || echo /usr/local/bin/spectre)}"
SPECTRE_JOB="prometheus/security-baseline-metrics-exporter"
ON_BOOT_SEC="${BASELINE_METRICS_ON_BOOT_SEC:-2min}"
ON_UNIT_ACTIVE_SEC="${BASELINE_METRICS_ON_UNIT_ACTIVE_SEC:-5min}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--print|--uninstall]

Installs a user timer that runs \`$SPECTRE_JOB\` (OnBootSec=$ON_BOOT_SEC, OnUnitActiveSec=$ON_UNIT_ACTIVE_SEC).

  --print      Print the generated units without installing them.
  --uninstall  Stop, disable, and remove only $TIMER_NAME/$SERVICE_NAME.

Environment:
  SPECTRE_BIN                        Path to the spectre CLI (default: spectre on PATH or /usr/local/bin/spectre)
  SPECTRE_REPO_ROOT                  Repository root used as WorkingDirectory (default: detected from script location)
  BASELINE_METRICS_ON_BOOT_SEC       Timer OnBootSec (default: 2min)
  BASELINE_METRICS_ON_UNIT_ACTIVE_SEC Timer OnUnitActiveSec (default: 5min)
EOF
}

service_unit() {
  cat <<EOF
[Unit]
Description=Spectre security baseline metrics exporter (textfile, suite)
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_ROOT
Environment=SPECTRE_REPO_ROOT=$PROJECT_ROOT
ExecStart=$SPECTRE_BIN run $SPECTRE_JOB

[Install]
WantedBy=default.target
EOF
}

timer_unit() {
  cat <<EOF
[Unit]
Description=Run Spectre security baseline metrics exporter every 5 minutes

[Timer]
OnBootSec=$ON_BOOT_SEC
OnUnitActiveSec=$ON_UNIT_ACTIVE_SEC
Unit=$SERVICE_NAME
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

case "${1:-}" in
  --print) echo "# $SERVICE_NAME"; service_unit; echo; echo "# $TIMER_NAME"; timer_unit; exit 0 ;;
  --uninstall)
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user stop "$TIMER_NAME" 2>/dev/null || true
      systemctl --user disable "$TIMER_NAME" 2>/dev/null || true
    fi
    rm -f "$USER_UNIT_DIR/$TIMER_NAME" "$USER_UNIT_DIR/$SERVICE_NAME"
    command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null || true
    echo "Removed $TIMER_NAME and $SERVICE_NAME from $USER_UNIT_DIR"; exit 0 ;;
  -h|--help) usage; exit 0 ;; "") ;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

command -v systemctl >/dev/null 2>&1 || { echo "systemctl unavailable" >&2; exit 1; }
systemctl --user show-environment >/dev/null 2>&1 || { echo "systemd user manager unavailable" >&2; exit 1; }
if ! command -v "${SPECTRE_BIN}" >/dev/null 2>&1 && [ ! -x "${SPECTRE_BIN}" ]; then
  echo "spectre CLI not found/executable: ${SPECTRE_BIN}" >&2
  exit 1
fi

mkdir -p "$USER_UNIT_DIR"
service_unit > "$USER_UNIT_DIR/$SERVICE_NAME"
timer_unit > "$USER_UNIT_DIR/$TIMER_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "$TIMER_NAME"
echo "Installed $TIMER_NAME (OnBootSec=$ON_BOOT_SEC, OnUnitActiveSec=$ON_UNIT_ACTIVE_SEC)."
