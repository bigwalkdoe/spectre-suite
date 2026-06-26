#!/bin/bash
# System Maintenance Installation Script

echo "==================================="
echo "System Maintenance Installation"
echo "==================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "Please run with sudo privileges"
   exit 1
fi

# Create directories
echo "Creating directories..."
mkdir -p /backups/{databases,docker-volumes,configurations,projects}
mkdir -p /var/log
mkdir -p /home/deon/.local/share

# Set permissions
echo "Setting permissions..."
chown -R $SUDO_USER:$SUDO_USER /backups
chmod -R 755 /backups
chmod -R 755 /home/deon/.local/share

# Copy scripts to /usr/local/bin
echo "Installing scripts..."
cp scripts/backups/*.sh /usr/local/bin/
cp scripts/performance/*.sh /usr/local/bin/
cp scripts/maintenance/*.sh /usr/local/bin/
cp scripts/network/*.sh /usr/local/bin/
cp scripts/security/*.sh /usr/local/bin/

# Copy enhancement scripts from /home/deon/scripts/
echo "Installing enhancement scripts..."
if [ -d /home/deon/scripts ]; then
    find /home/deon/scripts -name "*.sh" -type f -exec cp {} /usr/local/bin/ \; 2>/dev/null || true
fi

# Make scripts executable
chmod +x /usr/local/bin/*.sh

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
User=$SUDO_USER
Group=$SUDO_USER
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
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
User=$SUDO_USER
Group=$SUDO_USER
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
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
User=$SUDO_USER
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
User=$SUDO_USER
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
User=$SUDO_USER
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
User=$SUDO_USER
Group=$SUDO_USER
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

# Apply system performance optimizations
echo "Applying system performance optimizations..."
/usr/local/bin/optimize-system-performance.sh

# Apply network security hardening
echo "Applying network security hardening..."
/usr/local/bin/network-security-hardening.sh

# Configure Docker security
echo "Configuring Docker security..."
if command -v docker >/dev/null 2>&1; then
    bash -c 'cat > /etc/docker/daemon.json << "EOF"
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
EOF'
    systemctl restart docker
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
