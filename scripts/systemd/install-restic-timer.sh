#!/bin/bash
# Install per-user systemd timers for optional restic backups (default: local-only).
#
# Secrets stay outside the repo: set RESTIC_CONFIG to an env file containing
# RESTIC_REPOSITORY and RESTIC_PASSWORD/RESTIC_PASSWORD_FILE (see
# scripts/backups/restic.env.example). The service fails clearly if unconfigured.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="spectre-restic-backup.service"
TIMER_NAME="spectre-restic-backup.timer"
BACKUP_SCRIPT="$PROJECT_ROOT/scripts/backups/restic-backup.sh"
RESTIC_CONFIG_DEFAULT="${RESTIC_CONFIG:-/home/deon/.secrets/restic.env}"
ON_CALENDAR="${RESTIC_ON_CALENDAR:-*-*-* 04:15:00}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--print|--uninstall]

Installs a user timer that runs restic-backup.sh daily (default $ON_CALENDAR).
Set RESTIC_CONFIG (default $RESTIC_CONFIG_DEFAULT) and RESTIC_ON_CALENDAR to override.

  --print      Print the generated units without installing them.
  --uninstall  Stop, disable, and remove the timer and service.
EOF
}

service_unit() {
    cat <<EOF
[Unit]
Description=Spectre Suite restic backup (optional)
Documentation=file://$PROJECT_ROOT/README.md
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_ROOT
Environment=RESTIC_CONFIG=$RESTIC_CONFIG_DEFAULT
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$BACKUP_SCRIPT
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
}

timer_unit() {
    cat <<EOF
[Unit]
Description=Spectre Suite daily restic backup
Documentation=file://$PROJECT_ROOT/README.md

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
    --print)
        echo "# $SERVICE_NAME"; service_unit; echo; echo "# $TIMER_NAME"; timer_unit; exit 0 ;;
    --uninstall)
        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user stop "$TIMER_NAME" 2>/dev/null || true
            systemctl --user disable "$TIMER_NAME" 2>/dev/null || true
        fi
        rm -f "$USER_UNIT_DIR/$TIMER_NAME" "$USER_UNIT_DIR/$SERVICE_NAME"
        if command -v systemctl >/dev/null 2>&1; then systemctl --user daemon-reload 2>/dev/null || true; fi
        echo "Removed $TIMER_NAME and $SERVICE_NAME from $USER_UNIT_DIR"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

if ! command -v systemctl >/dev/null 2>&1; then echo "systemctl is not available" >&2; exit 1; fi
if ! systemctl --user show-environment >/dev/null 2>&1; then echo "systemd user manager is not available" >&2; exit 1; fi
if [ ! -x "$BACKUP_SCRIPT" ]; then echo "missing or not executable: $BACKUP_SCRIPT" >&2; exit 1; fi
if [ ! -f "$RESTIC_CONFIG_DEFAULT" ]; then
    echo "WARNING: RESTIC_CONFIG not found at $RESTIC_CONFIG_DEFAULT (service will fail until configured)" >&2
fi

mkdir -p "$USER_UNIT_DIR"
service_unit > "$USER_UNIT_DIR/$SERVICE_NAME"
timer_unit > "$USER_UNIT_DIR/$TIMER_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "$TIMER_NAME"

if command -v loginctl >/dev/null 2>&1; then
    linger=$(loginctl show-user "$USER" -p Linger --value 2>/dev/null || true)
    if [ "$linger" != "yes" ]; then
        echo "WARNING: enable lingering if needed: sudo loginctl enable-linger $USER" >&2
    fi
fi
echo "Installed $TIMER_NAME ($ON_CALENDAR). Configure RESTIC_CONFIG and restic credentials before it runs."
