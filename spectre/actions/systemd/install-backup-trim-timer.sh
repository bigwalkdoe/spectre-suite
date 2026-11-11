#!/bin/bash
# Install per-user systemd timer for conservative local backup artifact trimming.
# Dispatches via `spectre run backups/trim-backup-artifacts`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SPECTRE_REPO_ROOT:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="backup-trim.service"
TIMER_NAME="backup-trim.timer"
SPECTRE_BIN="${SPECTRE_BIN:-$(command -v spectre 2>/dev/null || echo /usr/local/bin/spectre)}"
SPECTRE_JOB="backups/trim-backup-artifacts"
ON_CALENDAR="${BACKUP_TRIM_ON_CALENDAR:-*-*-* 05:45:00}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--print|--uninstall]
Installs a user timer that runs \`$SPECTRE_JOB\` (default $ON_CALENDAR).
  --print      Print the generated units without installing them.
  --uninstall  Stop, disable, and remove only $TIMER_NAME/$SERVICE_NAME.
EOF
}

service_unit() {
  cat <<EOF
[Unit]
Description=Spectre Suite local backup artifact trimming
Documentation=file://$PROJECT_ROOT/docs/superpowers/specs/2026-11-11-automation-hardening-self-maintenance-design.md
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_ROOT
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$SPECTRE_BIN run $SPECTRE_JOB
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
}

timer_unit() {
  cat <<EOF
[Unit]
Description=Spectre Suite local backup artifact trimming timer
Documentation=file://$PROJECT_ROOT/docs/superpowers/specs/2026-11-11-automation-hardening-self-maintenance-design.md

[Timer]
OnCalendar=$ON_CALENDAR
Persistent=true
RandomizedDelaySec=10m
Unit=$SERVICE_NAME

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
echo "Installed $TIMER_NAME ($ON_CALENDAR)."
