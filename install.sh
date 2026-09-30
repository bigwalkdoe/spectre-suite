#!/bin/bash
set -euo pipefail
# System Maintenance Installation Script

echo "==================================="
echo "Spectre System Maintenance Installation"
echo "==================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run with sudo privileges"
   exit 1
fi

# Determine user home directory and the unprivileged account services should run as.
# When run under `sudo`, SUDO_USER is the invoking account. Otherwise we fall back
# to root so this script also works when executed directly as root.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    USER_NAME="$SUDO_USER"
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -z "$USER_HOME" ]; then
        echo "Could not determine home directory for $SUDO_USER" >&2
        exit 1
    fi
else
    USER_NAME="root"
    USER_HOME="$HOME"
fi

# Create directories
echo "Creating directories..."
mkdir -p /backups/{databases,docker-volumes,configurations,projects}

# Set permissions
# Backups hold database dumps and volume archives, so they must not be
# world-readable. 700 keeps them private to the owning account.
echo "Setting permissions..."
chown -R "$USER_NAME:$USER_NAME" /backups
chmod -R 700 /backups
chmod 700 /backups /backups/{databases,docker-volumes,configurations,projects}

# Copy scripts to /usr/local/bin
echo "Installing scripts..."
install -m 0755 -o root -g root scripts/backups/*.sh /usr/local/bin/
install -m 0755 -o root -g root scripts/performance/*.sh /usr/local/bin/
install -m 0755 -o root -g root scripts/maintenance/*.sh /usr/local/bin/
install -m 0755 -o root -g root scripts/network/*.sh /usr/local/bin/
install -m 0755 -o root -g root scripts/security/*.sh /usr/local/bin/

# Note: an earlier version copied every *.sh under the invoking user's ~/scripts
# into /usr/local/bin and then executed some of them as root below. That let a
# user-writable file run with root privileges. User scripts are no longer
# installed automatically; drop them in place yourself if you need them.

# Create systemd directory
mkdir -p /etc/systemd/system

# Copy systemd services
echo "Installing systemd services..."

# Backup service
cat > /etc/systemd/system/backup.service << 'EOF'
[Unit]
Description=Comprehensive System Backup
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-all.sh
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
User=$USER_NAME
Group=$USER_NAME
EOF

# Backup timer (daily at 2 AM)
cat > /etc/systemd/system/backup.timer << 'EOF'
[Unit]
Description=Daily Backup Timer
Requires=backup.service

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Maintenance service
cat > /etc/systemd/system/maintenance.service << 'EOF'
[Unit]
Description=System Maintenance Service
After=network.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/run-maintenance.sh
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
User=$USER_NAME
Group=$USER_NAME
EOF

# Maintenance timer (weekly Sundays at 3 AM)
cat > /etc/systemd/system/maintenance.timer << 'EOF'
[Unit]
Description=Weekly System Maintenance
Requires=maintenance.service

[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Performance check service
cat > /etc/systemd/system/performance-check.service << 'EOF'
[Unit]
Description=Performance Monitoring Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-performance.sh
User=$USER_NAME
Group=$USER_NAME
EOF

# Performance check timer (hourly)
cat > /etc/systemd/system/performance-check.timer << 'EOF'
[Unit]
Description=Performance Monitoring Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Network monitor service
cat > /etc/systemd/system/network-monitor.service << 'EOF'
[Unit]
Description=Network Monitoring Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/network-monitor.sh
User=$USER_NAME
Group=$USER_NAME
EOF

# Network monitor timer (hourly)
cat > /etc/systemd/system/network-monitor.timer << 'EOF'
[Unit]
Description=Network Monitoring Timer

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Disk space check service
cat > /etc/systemd/system/disk-space-check.service << 'EOF'
[Unit]
Description=Disk Space Monitoring Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/check-disk-space.sh
User=$USER_NAME
Group=$USER_NAME
EOF

# Disk space check timer (daily at midnight)
cat > /etc/systemd/system/disk-space-check.timer << 'EOF'
[Unit]
Description=Disk Space Monitoring Timer

[Timer]
OnCalendar=*-*-* 00:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Security scan service
cat > /etc/systemd/system/security-scan.service << 'EOF'
[Unit]
Description=Security Vulnerability Scanner
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/run-security-hardening.sh
User=$USER_NAME
Group=$USER_NAME
EOF

# Security scan timer (weekly Saturdays at 4 AM)
cat > /etc/systemd/system/security-scan.timer << 'EOF'
[Unit]
Description=Weekly Security Scanner

[Timer]
OnCalendar=Sat *-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Reload systemd
echo "Reloading systemd daemon..."
systemctl daemon-reload

# Enable timers
echo "Enabling timers..."
systemctl enable backup.timer
systemctl enable maintenance.timer
systemctl enable performance-check.timer
systemctl enable network-monitor.timer
systemctl enable disk-space-check.timer
systemctl enable security-scan.timer

# Start timers
echo "Starting timers..."
systemctl start backup.timer
systemctl start maintenance.timer
systemctl start performance-check.timer
systemctl start network-monitor.timer
systemctl start disk-space-check.timer
systemctl start security-scan.timer

# Apply system performance optimizations and network hardening.
# These mutate live system state (sysctl, firewall rules, docker daemon), so
# they are opt-in rather than an automatic side effect of installing.
if [ "${APPLY_HARDENING:-0}" = "1" ]; then
    echo "Applying system performance optimizations..."
    /usr/local/bin/optimize-system-performance.sh
    echo "Applying network security hardening..."
    /usr/local/bin/network-security-hardening.sh
else
    echo "Skipping system hardening (set APPLY_HARDENING=1 to apply)."
    echo "  optimize-system-performance.sh    # tune sysctl/limits"
    echo "  network-security-hardening.sh     # apply firewall rules"
fi

# Configure Docker security. Backs up any existing daemon.json first: the
# previous version overwrote it unconditionally and restarted the daemon, so a
# customised config was lost on every install.
if command -v docker >/dev/null 2>&1; then
    DAEMON_JSON=/etc/docker/daemon.json
    if [ -f "$DAEMON_JSON" ]; then
        BACKUP="${DAEMON_JSON}.spectre-backup.$(date +%Y%m%d%H%M%S)"
        cp -a "$DAEMON_JSON" "$BACKUP"
        echo "Backed up existing $DAEMON_JSON to $BACKUP"
    fi

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

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        systemctl restart docker
    else
        echo "Docker daemon not running; skipped restart. Reload it yourself when ready."
    fi
fi

# Create verification script
cat > /usr/local/bin/verify-installation.sh << 'EOF'
#!/bin/bash
echo "=== Installation Verification ==="

echo "Checking timers..."
systemctl list-timers --all

echo "Checking script permissions..."
ls -la /usr/local/bin/*.sh

echo "Checking directories..."
ls -la /backups

echo "Checking logs..."
ls -la /var/log/

echo "Installation verification complete!"
EOF

chmod +x /usr/local/bin/verify-installation.sh

echo "==================================="
echo "Installation Complete!"
echo "==================================="
echo "Run verification: /usr/local/bin/verify-installation.sh"
