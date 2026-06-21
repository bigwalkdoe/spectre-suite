# System Configuration Examples

This directory contains example configurations for different aspects of the system maintenance system.

## Docker Configuration Examples

### Docker Daemon Security Configuration
```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "icc": false,
  "default-runtime": "runc"
}
```

## Docker Compose Override for Resource Limits
```yaml
version: '3.8'

services:
  postgres:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

  neo4j:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G
```

## Systemd Timer Examples

### Custom Backup Schedule (twice daily)
```ini
[Unit]
Description=Custom Backup Timer

[Timer]
OnCalendar=06:00,18:00
Persistent=true

[Install]
WantedBy=timers.target
```

### Custom Maintenance Schedule (daily at 4 AM)
```ini
[Unit]
Description=Daily Maintenance Timer

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

## Network Configuration Examples

### Custom DNS Servers
```bash
# In /etc/systemd/resolved.conf.d/dns.conf
[Resolve]
DNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1
FallbackDNS=9.9.9.9 149.112.112.112
Cache=yes
DNSStubListener=yes
```

### Network Security Parameters
```bash
# In /etc/sysctl.conf
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.accept_source_route=0
```

## Monitoring Configuration Examples

### Custom Performance Thresholds
```bash
# In check-performance.sh
THRESHOLD_CPU=90
THRESHOLD_MEM=75
THRESHOLD_DISK=85
```

### Custom Alert Recipients
```bash
# In backup-all.sh
EMAIL_TO=admin@example.com
SLACK_WEBHOOK=https://hooks.slack.com/services/...
```

## Backup Configuration Examples

### Custom Retention Policies
```bash
# In backup-databases.sh
RETENTION_DAYS=14  # Keep 14 days of database backups
```

### Custom Backup Destinations
```bash
# In backup-all.sh
BACKUP_DIR="/mnt/nas/backups"  # Network storage
REMOTE_BACKUP="user@remote-server:/backups"  # Remote server
```

## Security Configuration Examples

### Fail2Ban Custom Configuration
```bash
# In /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
maxretry = 3
bantime = 2h
findtime = 1h
```

### API Rate Limiting Configuration
```nginx
# HTTP server status
server_status on
```

## Environment Variable Examples

### Backup Script Environment Variables
```bash
# Create .env file for backup scripts
POSTGRES_USER=backup_user
POSTGRES_PASSWORD=secure_password
POSTGRES_DB=database_name
NEO4J_USERNAME=neo4j
NEO4J_PASSWORD=secure_password
BACKUP_DIR=/custom/backup/location
```

### Performance Monitoring Environment Variables
```bash
# Performance thresholds
CPU_THRESHOLD=85
MEMORY_THRESHOLD=80
DISK_THRESHOLD=90
```

## Integration Examples

### Prometheus Configuration for System Monitoring
```yaml
# prometheus.yml example
scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['localhost:9100']
  
  - job_name: 'system_maintenance'
    static_configs:
      - targets: ['localhost:9101']
```

### Grafana Dashboard Import
1. Access Grafana at http://localhost:3002
2. Go to Dashboards -> Import
3. Upload the dashboard JSON from docs/grafana/
4. Configure Prometheus data source
