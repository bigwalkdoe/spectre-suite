#!/usr/bin/env bash
# Install per-user systemd path/service units that process dashboard action triggers.
# Dispatches via `spectre run dashboard-actions/process-triggers`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SPECTRE_REPO_ROOT:-"$(cd "$SCRIPT_DIR/../../.." && pwd)"}"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE_NAME="spectre-dashboard-actions.service"
PATH_NAME="spectre-dashboard-actions.path"
SPECTRE_BIN="${SPECTRE_BIN:-$(command -v spectre 2>/dev/null || echo /usr/local/bin/spectre)}"
SPECTRE_JOB="dashboard-actions/process-triggers"
TRIGGER_DIR="$PROJECT_ROOT/dashboard-actions/triggers"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--print|--uninstall]

Installs a user path unit that watches for dashboard action triggers and runs
\`$SPECTRE_JOB\` via spectre.

  --print      Print the generated units without installing them.
  --uninstall  Stop, disable, and remove only $PATH_NAME/$SERVICE_NAME.

Environment:
  SPECTRE_BIN        Path to the spectre CLI (default: spectre on PATH or /usr/local/bin/spectre)
  SPECTRE_REPO_ROOT  Repository root (default: detected from script location)
EOF
}

service_unit() {
  cat <<EOF
[Unit]
Description=Process Spectre dashboard action triggers

[Service]
Type=oneshot
ExecStart=$SPECTRE_BIN run $SPECTRE_JOB
WorkingDirectory=$PROJECT_ROOT
# Runs as the user; jobs may require sudo depending on what they do.
EOF
}

path_unit() {
  cat <<EOF
[Unit]
Description=Watch for Spectre dashboard action triggers

[Path]
PathChanged=$TRIGGER_DIR
Unit=$SERVICE_NAME

[Install]
WantedBy=default.target
EOF
}

case "${1:-}" in
  --print) echo "# $PATH_NAME"; path_unit; echo; echo "# $SERVICE_NAME"; service_unit; exit 0 ;;
  --uninstall)
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user stop "$PATH_NAME" 2>/dev/null || true
      systemctl --user disable "$PATH_NAME" 2>/dev/null || true
      systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
    fi
    rm -f "$USER_UNIT_DIR/$PATH_NAME" "$USER_UNIT_DIR/$SERVICE_NAME"
    command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload 2>/dev/null || true
    echo "Removed $PATH_NAME and $SERVICE_NAME from $USER_UNIT_DIR"; exit 0 ;;
  -h|--help) usage; exit 0 ;; "") ;; *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

command -v systemctl >/dev/null 2>&1 || { echo "systemctl unavailable" >&2; exit 1; }
systemctl --user show-environment >/dev/null 2>&1 || { echo "systemd user manager unavailable" >&2; exit 1; }
if ! command -v "${SPECTRE_BIN}" >/dev/null 2>&1 && [ ! -x "${SPECTRE_BIN}" ]; then
  echo "spectre CLI not found/executable: ${SPECTRE_BIN}" >&2
  exit 1
fi
if [ ! -d "$TRIGGER_DIR" ]; then
  echo "WARNING: trigger directory not found: $TRIGGER_DIR" >&2
fi

mkdir -p "$USER_UNIT_DIR"
path_unit > "$USER_UNIT_DIR/$PATH_NAME"
service_unit > "$USER_UNIT_DIR/$SERVICE_NAME"
systemctl --user daemon-reload
systemctl --user enable --now "$PATH_NAME"
echo "Installed $PATH_NAME ($TRIGGER_DIR)."
systemctl --user --no-pager status "$PATH_NAME" || true
