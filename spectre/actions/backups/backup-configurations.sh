#!/bin/bash
set -euo pipefail

# Configuration Backup Script
# Backs up system and application configurations

BACKUP_DIR="${BACKUP_DIR:-/backups/configurations}"
# Directory containing project configs to back up. Override per environment.
PROJECTS_DIR="${PROJECTS_DIR:-$PROJECTS_ROOT}"
DATE="${DATE:-$(date +%Y%m%d_%H%M%S)}"
RETENTION_DAYS=30
# Test/backup seams: SUDO_CMD empty runs without sudo; source overrides for root-owned files.
SUDO_CMD=${SUDO_CMD-sudo}
SSHD_CONFIG_SRC="${SSHD_CONFIG_SRC:-/etc/ssh/sshd_config}"
FAIL2BAN_JAIL_SRC="${FAIL2BAN_JAIL_SRC:-/etc/fail2ban/jail.local}"
DNF_AUTOMATIC_SRC="${DNF_AUTOMATIC_SRC:-/etc/dnf/dnf5-automatic.conf}"

mkdir -p "$BACKUP_DIR"

echo "Backing up system configurations..."

# System configurations
echo "Backing up systemd configurations..."
$SUDO_CMD mkdir -p "$BACKUP_DIR/systemd_$DATE"
$SUDO_CMD cp -r /etc/systemd/system/. "$BACKUP_DIR/systemd_$DATE/" 2>/dev/null || true
$SUDO_CMD tar czf "$BACKUP_DIR/systemd_configs_$DATE.tar.gz" -C /etc systemd/system 2>/dev/null || true

# Docker configurations
echo "Backing up Docker configurations..."
$SUDO_CMD tar czf "$BACKUP_DIR/docker_configs_$DATE.tar.gz" -C /etc docker 2>/dev/null || true

# SSH configuration (install -m 0640 -o invoking user: readable by restic, not world-readable)
echo "Backing up SSH configuration..."
$SUDO_CMD install -m 0640 -o "$(id -u)" -g "$(id -g)" "$SSHD_CONFIG_SRC" "$BACKUP_DIR/sshd_config_$DATE" 2>/dev/null || true

# Firewall configuration
echo "Backing up firewall configuration..."
$SUDO_CMD firewall-cmd --list-all 2>/dev/null | $SUDO_CMD tee "$BACKUP_DIR/firewall_config_$DATE.txt" >/dev/null || true

# Fail2Ban configuration
echo "Backing up Fail2Ban configuration..."
$SUDO_CMD install -m 0640 -o "$(id -u)" -g "$(id -g)" "$FAIL2BAN_JAIL_SRC" "$BACKUP_DIR/fail2ban_jail_$DATE" 2>/dev/null || true

# DNF configuration
echo "Backing up DNF configuration..."
$SUDO_CMD install -m 0640 -o "$(id -u)" -g "$(id -g)" "$DNF_AUTOMATIC_SRC" "$BACKUP_DIR/dnf-automatic_$DATE" 2>/dev/null || true

# Project configurations
# NOTE: Only non-secret configs are included. .env files (which may contain
# credentials) are deliberately excluded to avoid leaking secrets into backups.
echo "Backing up project configurations..."
if [[ -d "$PROJECTS_DIR/Guardrail-AI" ]]; then
    tar czf "$BACKUP_DIR/projects_config_$DATE.tar.gz" \
        -C "$PROJECTS_DIR" Guardrail-AI/dk-compose.yml 2>/dev/null || true
fi

# Cleanup old backups
echo "Cleaning up old configuration backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -maxdepth 1 -type f -mtime +"$RETENTION_DAYS" -delete
# Only prune timestamped backup directories we created (systemd_*, *_$DATE style).
find "$BACKUP_DIR" -maxdepth 1 -type d -name '*_[0-9][0-9][0-9][0-9]*' -mtime +"$RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true

echo "Configuration backup completed: $DATE"
logger -p user.info "Configuration backup completed successfully" 2>/dev/null || true
