#!/bin/bash
# Install per-user systemd timer for weekly restic forget/prune (opt-in).
# Uses RESTIC_CONFIG for secrets; RESTIC_FORGET_ARGS controls policy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="spectre-restic-maintenance.service"
TIMER_NAME="spectre-restic-maintenance.timer"
MAINT_SCRIPT="$PROJECT_ROOT/scripts/backups/restic-forget-prune.sh"
RESTIC_CONFIG_DEFAULT="${RESTIC_CONFIG:-/home/deon/.secrets/restic.env}"
ON_CALENDAR="${RESTIC_MAINT_ON_CALENDAR:-Sun *-*-* 04:45:00}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--print|--uninstall]
Installs a weekly timer (default $ON_CALENDAR) running restic-forget-prune.sh.
Set RESTIC_CONFIG and RESTIC_FORGET_ARGS in that config (see restic.env.example).
Destructive to old snapshots per policy - verify policy before enabling.
  --print | --uninstall
EOF
}

service_unit() {
  cat <<EOF
[Unit]
Description=Spectre Suite restic maintenance (forget/prune)
Documentation=file://$PROJECT_ROOT/README.md
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_ROOT
Environment=RESTIC_CONFIG=$RESTIC_CONFIG_DEFAULT
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$MAINT_SCRIPT
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
EOF
}

timer_unit() {
  cat <<EOF
[Unit]
Description=Spectre Suite weekly restic maintenance
Documentation=file://$PROJECT_ROOT/README.md

[Timer]
OnCalendar=$ON_CALENDAR
Persistent=true
RandomizedDelaySec=15m
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
    echo "Removed $TIMER_NAME and $SERVICE_NAME"; exit 0 ;;
  -h|--help) usage; exit 0 ;; "") ;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

command -v systemctl >/dev/null 2>&1 || { echo "systemctl unavailable" >&2; exit 1; }
systemctl --user show-environment >/dev/null 2>&1 || { echo "systemd user manager unavailable" >&2; exit 1; }
[ -x "$MAINT_SCRIPT" ] || { echo "missing/not executable: $MAINT_SCRIPT" >&2; exit 1; }
[ -f "$RESTIC_CONFIG_DEFAULT" ] || echo "WARNING: $RESTIC_CONFIG_DEFAULT not found; configure before enabling" >&2

mkdir -p "$USER_UNIT_DIR"
service_unit > "$USER_UNIT_DIR/$SERVICE_NAME"
timer_unit > "$USER_UNIT_DIR/$TIMER_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "$TIMER_NAME"
echo "Installed $TIMER_NAME ($ON_CALENDAR). Verify RESTIC_FORGET_ARGS and run a dry-run before relying on it."
