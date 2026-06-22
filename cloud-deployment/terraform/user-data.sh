#!/bin/bash
# User data script for cloud instance initialization
# This script sets up the system maintenance suite on cloud instances

set -e

# Variables from Terraform
ENVIRONMENT="${environment}"
PROJECT_NAME="${project_name}"

echo "Starting initialization for $PROJECT_NAME in $ENVIRONMENT environment..."

# Update system
echo "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y \
    curl \
    wget \
    git \
    docker.io \
    docker-compose \
    python3 \
    python3-pip \
    fail2ban \
    ufw \
    unzip \
    software-properties-common

# Enable and start Docker
echo "Setting up Docker..."
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# Install Ansible for configuration management
echo "Installing Ansible..."
pip3 install ansible

# Clone system maintenance repository
echo "Cloning system maintenance repository..."
cd /opt
git clone https://github.com/YOUR_USERNAME/system-maintenance.git
cd system-maintenance

# Run installation script
echo "Running system maintenance installation..."
chmod +x install.sh
./install.sh

# Deploy monitoring stack
echo "Deploying monitoring stack..."
chmod +x scripts/deploy-monitoring.sh
./scripts/deploy-monitoring.sh

# Configure firewall
echo "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw allow 3002/tcp  # Grafana
ufw allow 9090/tcp  # Prometheus
ufw allow 8081/tcp  # Web Dashboard
ufw --force enable

# Configure fail2ban
echo "Configuring Fail2Ban..."
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF

systemctl enable fail2ban
systemctl start fail2ban

# Set up monitoring and backup systemd timers
echo "Setting up systemd timers..."
cp systemd/*.service /etc/systemd/system/
cp systemd/*.timer /etc/systemd/system/
systemctl daemon-reload

# Enable timers
systemctl enable backup.timer
systemctl enable maintenance.timer
systemctl enable performance-check.timer
systemctl enable network-monitor.timer
systemctl enable disk-space-check.timer
systemctl enable security-scan.timer

# Start timers
systemctl start backup.timer
systemctl start maintenance.timer
systemctl start performance-check.timer
systemctl start network-monitor.timer
systemctl start disk-space-check.timer
systemctl start security-scan.timer

# Create cloud-specific configuration
echo "Creating cloud-specific configuration..."
cat > /etc/system-maintenance/cloud-config.yml << EOF
cloud_deployment: true
environment: $ENVIRONMENT
provider: aws
instance_type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
instance_id: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
region: $(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')
EOF

# Set up log rotation for cloud instances
echo "Configuring log rotation..."
cat > /etc/logrotate.d/system-maintenance << EOF
/var/log/system-maintenance/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 ubuntu ubuntu
}
EOF

# Configure backup destination (S3 for AWS)
echo "Configuring cloud backup..."
if command -v aws >/dev/null 2>&1; then
    # Install AWS CLI
    pip3 install awscli
    
    # Create backup script with S3 support
    cat > /usr/local/bin/backup-to-s3.sh << 'EOF'
#!/bin/bash
S3_BUCKET="s3://system-maintenance-backups-$(hostname)"
BACKUP_DIR="/backups"

# Sync backups to S3
aws s3 sync "$BACKUP_DIR" "$S3_BUCKET" --delete
EOF
    chmod +x /usr/local/bin/backup-to-s3.sh
fi

# Create health check endpoint
echo "Setting up health check..."
cat > /var/www/html/health.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>System Maintenance Health Check</title>
</head>
<body>
    <h1>System Maintenance Suite - Health Check</h1>
    <p>Status: <strong>OK</strong></p>
    <p>Environment: $ENVIRONMENT</p>
    <p>Instance: $(hostname)</p>
    <p>Timestamp: $(date)</p>
</body>
</html>
EOF

# Install nginx for health check endpoint
apt-get install -y nginx
systemctl enable nginx
systemctl start nginx

# Create cron jobs for cloud-specific tasks
echo "Setting up cloud cron jobs..."
cat > /etc/cron.d/cloud-maintenance << EOF
# Cloud maintenance tasks
0 2 * * * ubuntu /opt/system-maintenance/scripts/backups/backup-all.sh
0 3 * * 0 ubuntu /opt/system-maintenance/scripts/maintenance/run-maintenance.sh
0 4 * * 6 ubuntu /opt/system-maintenance/scripts/security/run-security-hardening.sh
0 5 * * * ubuntu /usr/local/bin/backup-to-s3.sh
EOF

# Create cloud monitoring script
echo "Setting up cloud monitoring..."
cat > /usr/local/bin/cloud-monitor.sh << 'EOF'
#!/bin/bash
# Cloud monitoring script
# Reports instance health to cloud provider metrics

# Collect metrics
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
MEMORY_USAGE=$(free | grep Mem | awk '{print ($3/$2) * 100.0}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

# Send to CloudWatch (AWS) if available
if command -v aws >/dev/null 2>&1; then
    INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
    
    aws cloudwatch put-metric-data \
        --namespace SystemMaintenance \
        --metric-name CPUUsage \
        --value $CPU_USAGE \
        --dimensions InstanceId=$INSTANCE_ID \
        --unit Percent 2>/dev/null || true
    
    aws cloudwatch put-metric-data \
        --namespace SystemMaintenance \
        --metric-name MemoryUsage \
        --value $MEMORY_USAGE \
        --dimensions InstanceId=$INSTANCE_ID \
        --unit Percent 2>/dev/null || true
    
    aws cloudwatch put-metric-data \
        --namespace SystemMaintenance \
        --metric-name DiskUsage \
        --value $DISK_USAGE \
        --dimensions InstanceId=$INSTANCE_ID \
        --unit Percent 2>/dev/null || true
fi

echo "Cloud monitoring: CPU=$CPU_USAGE%, MEM=$MEMORY_USAGE%, DISK=$DISK_USAGE%"
EOF

chmod +x /usr/local/bin/cloud-monitor.sh

# Add cloud monitoring to cron
echo "*/5 * * * * ubuntu /usr/local/bin/cloud-monitor.sh" >> /etc/cron.d/cloud-maintenance

# Finalize
echo "Initialization completed successfully!"
echo "System Maintenance Suite is ready for use in $ENVIRONMENT environment."
echo ""
echo "Access Points:"
echo "  - Web Dashboard: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081"
echo "  - Grafana: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):3002"
echo "  - Prometheus: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):9090"
echo ""
echo "Next steps:"
echo "  1. Change default Grafana password"
echo "  2. Configure backup destination"
echo "  3. Review cloud-specific configurations"
echo "  4. Set up monitoring and alerting"
