#!/bin/bash
# Configuration Backup Script
# Backs up system and application configurations

BACKUP_DIR="/backups/configurations"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30

mkdir -p "$BACKUP_DIR"

echo "Backing up system configurations..."

# System configurations
echo "Backing up systemd configurations..."
sudo cp -r /etc/systemd/system/* "$BACKUP_DIR/systemd_$DATE/" 2>/dev/null || true
sudo tar czf "$BACKUP_DIR/systemd_configs_$DATE.tar.gz" -C /etc systemd/system 2>/dev/null || true

# Docker configurations
echo "Backing up Docker configurations..."
sudo tar czf "$BACKUP_DIR/docker_configs_$DATE.tar.gz" -C /etc docker 2>/dev/null || true

# SSH configuration
echo "Backing up SSH configuration..."
sudo cp /etc/ssh/sshd_config "$BACKUP_DIR/sshd_config_$DATE" 2>/dev/null || true

# Firewall configuration
echo "Backing up firewall configuration..."
sudo firewall-cmd --list-all > "$BACKUP_DIR/firewall_config_$DATE.txt" 2>/dev/null || true

# Fail2Ban configuration
echo "Backing up Fail2Ban configuration..."
sudo cp /etc/fail2ban/jail.local "$BACKUP_DIR/fail2ban_jail_$DATE" 2>/dev/null || true

# DNF configuration
echo "Backing up DNF configuration..."
sudo cp /etc/dnf/dnf5-automatic.conf "$BACKUP_DIR/dnf-automatic_$DATE" 2>/dev/null || true

# Project configurations
echo "Backing up project configurations..."
tar czf "$BACKUP_DIR/projects_config_$DATE.tar.gz" -C /home/deon/projects Guardrail-AI/dk-compose.yml Guardrail-AI/.env 2>/dev/null || true

# Cleanup old backups
echo "Cleaning up old configuration backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -type d -mtime +$RETENTION_DAYS -exec rm -rf {} + 2>/dev/null || true

echo "Configuration backup completed: $DATE"
logger -p user.info "Configuration backup completed successfully"
