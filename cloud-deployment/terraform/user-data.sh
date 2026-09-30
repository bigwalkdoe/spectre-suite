#!/bin/bash
# User data script for cloud instance initialization
# This script sets up the system maintenance suite on cloud instances

set -euo pipefail

# Variables from Terraform. These are substituted by templatefile() (see
# user_data in main.tf), so they arrive already expanded and must keep the bare
# variable-reference form -- Terraform's template language has no default-value
# operator, so shell-style fallbacks here would be a template parse error.
# shellcheck disable=SC2154
ENVIRONMENT="${environment}"
# shellcheck disable=SC2154
PROJECT_NAME="${project_name}"
# shellcheck disable=SC2154
REPO_URL="${repo_url}"

if [ -z "$ENVIRONMENT" ] || [ -z "$PROJECT_NAME" ] || [ -z "$REPO_URL" ]; then
    echo "Error: environment/project_name/repo_url were not substituted by Terraform." >&2
    exit 1
fi

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
# Substituted by templatefile(). This was previously the literal placeholder
# YOUR_USERNAME/spectre-system-maintenance, so provisioning failed at the `cd`
# immediately below.
echo "Cloning $REPO_URL..."
cd /opt
git clone "$REPO_URL"
cd "$(basename "$REPO_URL" .git)"

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
cat > /etc/spectre-system-maintenance/cloud-config.yml << EOF
cloud_deployment: true
environment: $ENVIRONMENT
provider: aws
instance_type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)
instance_id: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)
region: $(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')
EOF

# Set up log rotation for cloud instances
echo "Configuring log rotation..."
cat > /etc/logrotate.d/spectre-system-maintenance << EOF
/var/log/spectre-system-maintenance/*.log {
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
S3_BUCKET="s3://spectre-system-maintenance-backups-$(hostname)"
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
    <h1>Spectre System Maintenance Suite - Health Check</h1>
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
0 2 * * * ubuntu /opt/spectre-system-maintenance/scripts/backups/backup-all.sh
0 3 * * 0 ubuntu /opt/spectre-system-maintenance/scripts/maintenance/run-maintenance.sh
0 4 * * 6 ubuntu /opt/spectre-system-maintenance/scripts/security/run-security-hardening.sh
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
        --namespace SpectreSystemMaintenance \
        --metric-name CPUUsage \
        --value "$${CPU_USAGE}" \
        --dimensions InstanceId=$INSTANCE_ID \
        --unit Percent 2>/dev/null || true
    
    aws cloudwatch put-metric-data \
        --namespace SpectreSystemMaintenance \
        --metric-name MemoryUsage \
        --value "$${MEMORY_USAGE}" \
        --dimensions InstanceId=$INSTANCE_ID \
        --unit Percent 2>/dev/null || true
    
    aws cloudwatch put-metric-data \
        --namespace SpectreSystemMaintenance \
        --metric-name DiskUsage \
        --value "$${DISK_USAGE}" \
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
echo "Spectre System Maintenance Suite is ready for use in $ENVIRONMENT environment."
echo ""
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 || echo "<instance-ip>")
echo "Access Points:"
echo "  Grafana, Prometheus and the dashboard bind to loopback only. Reach them via SSH tunnel:"
printf '    ssh -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 8081:127.0.0.1:8081 ubuntu@%s\n' "$PUBLIC_IP"
echo "  then open http://127.0.0.1:3002, :9090 and :8081 locally"
echo ""
echo "Next steps:"
echo "  1. Change default Grafana password"
echo "  2. Configure backup destination"
echo "  3. Review cloud-specific configurations"
echo "  4. Set up monitoring and alerting"
