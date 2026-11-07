#!/bin/bash
set -euo pipefail
# Spectre Suite installation (consolidation §8.2 aligned).
#
# Installs ONLY the `spectre` CLI into /usr/local/bin (as a wrapper to a managed
# venv) and generates systemd units/timers that dispatch via `spectre run <job>`.
# Does NOT copy action scripts to /usr/local/bin. Review before use on a host.

PRINT_UNITS=0
[ "${1:-}" = "--print-units" ] && PRINT_UNITS=1

echo "==================================="
echo "Spectre Suite Installation"
echo "==================================="

if [ "$EUID" -ne 0 ] && [ "$PRINT_UNITS" -ne 1 ]; then
  echo "Please run with sudo privileges" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SPECTRE_REPO_ROOT:-$SCRIPT_DIR}"

# Unprivileged account for scheduled jobs (when run via sudo).
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  USER_NAME="$SUDO_USER"
  USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  USER_NAME="${USER_NAME:-root}"
  USER_HOME="${HOME:-/root}"
fi
[ -n "${USER_HOME:-}" ] || USER_HOME="/root"

SPECTRE_VENV="${SPECTRE_VENV:-/usr/local/share/spectre-venv}"
SPECTRE_BIN="${SPECTRE_BIN:-/usr/local/bin/spectre}"

# Backup directories (private)
ensure_backup_dirs() {
  echo "Creating backup directories..."
  mkdir -p /backups/{databases,docker-volumes,configurations,projects}
  chown -R "$USER_NAME:$USER_NAME" /backups
  chmod -R 700 /backups
  chmod 700 /backups /backups/{databases,docker-volumes,configurations,projects}
}


unit_out() {
  local path="$1"
  if [ "$PRINT_UNITS" -eq 1 ]; then cat > "/dev/stdout"; else cat > "$path"; fi
}

write_job_unit() {
  local unit="$1" desc="$2" job="$3" after="${4:-network.target}"
  if [ "$PRINT_UNITS" -eq 1 ]; then echo "### ${unit}.service"; fi
  cat << EOF | unit_out "/etc/systemd/system/${unit}.service"
[Unit]
Description=$desc
After=$after

[Service]
Type=oneshot
ExecStart=$SPECTRE_BIN run $job
WorkingDirectory=$REPO_ROOT
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
User=$USER_NAME
Group=$USER_NAME
EOF
}

write_timer() {
  local unit="$1" desc="$2" calendar="$3"
  if [ "$PRINT_UNITS" -eq 1 ]; then echo "### ${unit}.timer"; fi
  cat << EOF | unit_out "/etc/systemd/system/${unit}.timer"
[Unit]
Description=$desc
Requires=${unit}.service

[Timer]
OnCalendar=$calendar
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

if [ "$PRINT_UNITS" -eq 1 ]; then
  write_job_unit backup "Comprehensive System Backup" backups/backup-all "network.target docker.service"
  write_job_unit maintenance "System Maintenance Service" maintenance/run-maintenance "network.target docker.service"
  write_job_unit performance-check "Performance Monitoring Service" performance/check-performance
  write_job_unit network-monitor "Network Monitoring Service" network/monitor-network
  write_job_unit disk-space-check "Disk Space Monitoring Service" maintenance/check-disk-space
  write_job_unit security-scan "Security Vulnerability Scanner" security/run-security-hardening "network.target"
  exit 0
fi

# Install spectre CLI into a managed venv and expose only /usr/local/bin/spectre
install_spectre_cli() {
  echo "Installing spectre CLI into $SPECTRE_VENV ..."
  if [ ! -f "$REPO_ROOT/pyproject.toml" ]; then
    echo "ERROR: $REPO_ROOT/pyproject.toml not found. Run from repo root or set SPECTRE_REPO_ROOT." >&2
    exit 1
  fi
  python3 -m venv "$SPECTRE_VENV"
  "$SPECTRE_VENV/bin/pip" install --upgrade pip >/dev/null
  "$SPECTRE_VENV/bin/pip" install "$REPO_ROOT"
  cat > "$SPECTRE_BIN" <<EOF
#!/bin/bash
exec "$SPECTRE_VENV/bin/spectre" "\$@"
EOF
  chmod 0755 "$SPECTRE_BIN"
  echo "Installed $SPECTRE_BIN"
}

if [ "${SKIP_PIP_INSTALL:-0}" = "1" ]; then
  echo "SKIP_PIP_INSTALL=1: writing $SPECTRE_BIN wrapper to $SPECTRE_VENV/bin/spectre (venv/package not created)."
  mkdir -p "$(dirname "$SPECTRE_BIN")"
  cat > "$SPECTRE_BIN" <<EOF
#!/bin/bash
exec "$SPECTRE_VENV/bin/spectre" "\$@"
EOF
  chmod 0755 "$SPECTRE_BIN"
else
  install_spectre_cli
fi

ensure_backup_dirs

echo "Installing systemd units/timers (dispatch via spectre run)..."
mkdir -p /etc/systemd/system
write_job_unit backup "Comprehensive System Backup" backups/backup-all "network.target docker.service"
write_timer backup "Daily Backup Timer" "*-*-* 02:00:00"
write_job_unit maintenance "System Maintenance Service" maintenance/run-maintenance "network.target docker.service"
write_timer maintenance "Weekly System Maintenance" "Sun *-*-* 03:00:00"
write_job_unit performance-check "Performance Monitoring Service" performance/check-performance
write_timer performance-check "Performance Monitoring Timer" "hourly"
write_job_unit network-monitor "Network Monitoring Service" network/monitor-network
write_timer network-monitor "Network Monitoring Timer" "hourly"
write_job_unit disk-space-check "Disk Space Monitoring Service" maintenance/check-disk-space
write_timer disk-space-check "Disk Space Monitoring Timer" "*-*-* 00:00:00"
write_job_unit security-scan "Security Vulnerability Scanner" security/run-security-hardening "network.target"
write_timer security-scan "Weekly Security Scanner" "Sat *-*-* 04:00:00"

echo "Reloading systemd..."
systemctl daemon-reload
echo "Enabling timers..."
systemctl enable backup.timer maintenance.timer performance-check.timer network-monitor.timer disk-space-check.timer security-scan.timer
echo "Starting timers..."
systemctl start backup.timer maintenance.timer performance-check.timer network-monitor.timer disk-space-check.timer security-scan.timer

# Optional hardening (mutates live system state). Uses spectre run, not /usr/local/bin scripts.
if [ "${APPLY_HARDENING:-0}" = "1" ]; then
  echo "Applying system performance optimizations via spectre..."
  "$SPECTRE_BIN" run performance/optimize-system-performance || true
  echo "Applying network security hardening via spectre..."
  "$SPECTRE_BIN" run maintenance/network-security-hardening || "$SPECTRE_BIN" run network/harden-network-security || true
else
  echo "Skipping system hardening (set APPLY_HARDENING=1 to apply)."
  echo "  spectre run performance/optimize-system-performance"
  echo "  spectre run maintenance/network-security-hardening"
fi

# Docker daemon.json handling (backs up existing config first).
if command -v docker >/dev/null 2>&1; then
  DAEMON_JSON=/etc/docker/daemon.json
  if [ -f "$DAEMON_JSON" ]; then
    BACKUP="${DAEMON_JSON}.spectre-backup.$(date +%Y%m%d%H%M%S)"
    cp -a "$DAEMON_JSON" "$BACKUP"
    echo "Backed up existing $DAEMON_JSON to $BACKUP"
  fi
  mkdir -p /etc/docker
  cat > "$DAEMON_JSON" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "icc": false
}
EOF
  chmod 0644 "$DAEMON_JSON"
  if docker info >/dev/null 2>&1; then
    systemctl restart docker
  else
    echo "Docker daemon not running; skipped restart. Reload it yourself when ready."
  fi
fi

echo "==================================="
echo "Installation complete (§8.2: only $SPECTRE_BIN installed to /usr/local/bin)."
echo "Verify: $SPECTRE_BIN actions verify"
echo "==================================="
