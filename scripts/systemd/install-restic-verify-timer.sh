#!/bin/bash
# Install per-user systemd timer for the adopted spectre-suite restic verify.
# Runs scripts/backups/restic/verify.sh weekly (default Sun 05:30). Never touches
# spectre-backup-catchup (suite artifact catch-up).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="spectre-restic-verify.service"
TIMER_NAME="spectre-restic-verify.timer"
VERIFY_SCRIPT="$PROJECT_ROOT/scripts/backups/restic/verify.sh"
RESTIC_CONFIG_DEFAULT="${RESTIC_CONFIG:-$HOME/.secrets/spectre-suite-backups.env}"
ON_CALENDAR="${RESTIC_VERIFY_ON_CALENDAR:-Sun *-*-* 05:30:00}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--print|--uninstall]
Installs a user timer that runs the adopted restic verify (default $ON_CALENDAR).
Set RESTIC_CONFIG (default $RESTIC_CONFIG_DEFAULT) to the env file with repo/password settings.
  --print      Print the generated units without installing them.
  --uninstall  Stop, disable, and remove only $TIMER_NAME/$SERVICE_NAME.
EOF
}

service_unit() {
  cat <<EOF
[Unit]
Description=Spectre Suite adopted restic verify
Documentation=file://$PROJECT_ROOT/docs/migration/2026-11-06-absorb-spectre-backup.md
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_ROOT
Environment=RESTIC_CONFIG=$RESTIC_CONFIG_DEFAULT
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$VERIFY_SCRIPT
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
}

timer_unit() {
  cat <<EOF
[Unit]
Description=Spectre Suite weekly adopted restic verify
Documentation=file://$PROJECT_ROOT/docs/migration/2026-11-06-absorb-spectre-backup.md

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
[ -x "$VERIFY_SCRIPT" ] || { echo "missing/not executable: $VERIFY_SCRIPT" >&2; exit 1; }
[ -f "$RESTIC_CONFIG_DEFAULT" ] || echo "WARNING: $RESTIC_CONFIG_DEFAULT not found; configure before enabling" >&2

mkdir -p "$USER_UNIT_DIR"
service_unit > "$USER_UNIT_DIR/$SERVICE_NAME"
timer_unit > "$USER_UNIT_DIR/$TIMER_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "$TIMER_NAME"
echo "Installed $TIMER_NAME ($ON_CALENDAR)."
