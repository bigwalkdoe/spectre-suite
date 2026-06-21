# Troubleshooting Guide

This guide covers common issues and their solutions for the System Maintenance system.

## 🔧 Installation Issues

### Permission Denied Errors

**Problem**: `Permission denied` when running installation script

**Solution**:
```bash
# Run installation with sudo
sudo ./install.sh
```

### Script Not Found Errors

**Problem**: Scripts not found after installation

**Solution**:
```bash
# Verify scripts are in PATH
echo $PATH
ls -la /usr/local/bin/*.sh

# Add scripts to PATH if needed
export PATH=/usr/local/bin:$PATH
```

## 🔒 Security Issues

### Fail2Ban Not Working

**Problem**: Fail2Ban not blocking IPs

**Solution**:
```bash
# Check Fail2Ban status
sudo systemctl status fail2ban

# Check Fail2Ban logs
sudo fail2ban-client status sshd

# Restart Fail2Ban
sudo systemctl restart fail2ban
```

### SSH Access Blocked by Fail2Ban

**Problem**: Locked out of your own system by Fail2Ban

**Solution**:
```bash
# Check your IP in banned list
sudo fail2ban-client status sshd

# Unban your IP (replace with your IP)
sudo fail2ban-client set sshd unbanip 192.168.1.100
```

## 💾 Backup Issues

### Backup Script Fails

**Problem**: Backup scripts not completing successfully

**Solution**:
```bash
# Check backup logs
sudo cat /var/log/backup.log

# Test backup manually
sudo /usr/local/bin/backup-databases.sh

# Check disk space in backup directory
df -h /backups

# Verify database credentials
# Check that POSTGRES_USER and POSTGRES_PASSWORD are correct
```

### Docker Volume Backup Fails

**Problem**: Docker volume backups fail with permission errors

**Solution**:
```bash
# Check Docker permissions
sudo docker ps -a

# Check volume permissions
sudo docker volume ls

# Run docker volume backup with proper permissions
sudo docker run --rm -v volume_name:/data -v /backups:/backup \
  alpine tar czf /backup/volume_name_backup.tar.gz -C /data .
```

### Disk Space Full

**Problem**: Backup disk full, backups failing

**Solution**:
```bash
# Check disk usage
df -h /backups

# Clean old backups (modify retention policy)
find /backups -type f -mtime +30 -delete

# Remove large files
du -sh /backups/* | sort -hr | head -10

# Extend disk space if needed
# This depends on your storage setup
```

## 🚀 Performance Issues

### High CPU Usage

**Problem**: System CPU usage consistently high

**Solution**:
```bash
# Check processes using CPU
top -bn1 | head -20

# Check performance logs
cat /var/log/performance.log

# Review Docker container resource usage
docker stats --no-stream

# Adjust Docker resource limits if needed
```

### High Memory Usage

**Problem**: System memory usage consistently high

**Solution**:
```bash
# Check memory usage
free -h

# Check for memory leaks
ps aux --sort=-%mem | head -10

# Check swap usage
swapon -s

# Adjust swappiness if needed
sudo sysctl vm.swappiness=10
```

### Docker Containers Using Too Much Memory

**Problem**: Docker containers consuming excessive memory

**Solution**:
```bash
# Check container memory usage
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}"

# Restart resource-heavy containers
docker restart container_name

# Apply resource limits
# See docs/CONFIGURATION_EXAMPLES.md
```

## 🌐 Network Issues

### DNS Resolution Failing

**Problem**: DNS resolution not working

**Solution**:
```bash
# Check DNS configuration
cat /etc/resolv.conf

# Test DNS resolution
nslookup google.com

# Check systemd-resolved status
sudo systemctl status systemd-resolved

# Restart NetworkManager
sudo systemctl restart NetworkManager
```

### Network Monitoring Errors

**Problem**: Network monitoring script failing

**Solution**:
```bash
# Check network monitor log
cat /home/deon/.local/share/network-monitor.log

# Test network connectivity
ping -c 3 8.8.8.8

# Check firewall status
sudo firewall-cmd --state

# Check if network-monitor timer is running
sudo systemctl status network-monitor.timer
```

## 🐳 Docker Issues

### Docker Daemon Won't Start

**Problem**: Docker service won't start

**Solution**:
```bash
# Check Docker status
sudo systemctl status docker

# Check Docker logs
sudo journalctl -u docker -n 50

# Check Docker configuration
sudo cat /etc/docker/daemon.json

# Fix configuration if needed and restart
sudo systemctl restart docker
```

### Containers Not Starting

**Problem**: Docker containers failing to start

**Solution**:
```bash
# Check container logs
docker logs container_name

# Check Docker events
docker events --filter 'event=die'

# Recreate containers
cd /path/to/project
docker-compose up -d

# Check disk space
df -h
```

### Health Checks Failing

**Problem**: Container health checks consistently failing

**Solution**:
```bash
# Check health check configuration
docker inspect container_name | grep -A 10 Health

# Test health check manually
docker exec container_name health_check_command

# Disable health check if not critical
# Edit docker-compose.yml and remove healthcheck section
```

## 🔔 Monitoring Issues

### Alerts Not Being Received

**Problem**: System alerts not being generated

**Solution**:
```bash
# Check if timers are running
sudo systemctl list-timers --all

# Check service logs
sudo journalctl -u backup.service -n 20

# Check desktop notifications
# Ensure notification daemon is running
```

### Grafana Dashboard Not Showing Data

**Problem**: Grafana dashboards showing no data

**Solution**:
```bash
# Check Prometheus status
docker ps | grep prometheus

# Check if Prometheus is scraping metrics
curl http://localhost:9091/api/v1/targets

# Verify Grafana data source configuration
# Access Grafana and check data source settings
```

## 🛠️ Maintenance Issues

### Maintenance Script Fails

**Problem**: Weekly maintenance script failing

**Solution**:
```bash
# Check maintenance logs
sudo cat /var/log/maintenance.log

# Test individual maintenance components
sudo /usr/local/bin/cleanup-system.sh
sudo /usr/local/bin/cleanup-logs.sh
sudo /usr/local/bin/system-health-check.sh

# Check available disk space
df -h
```

### Automatic Cleanup Not Working

**Problem**: Temporary files not being cleaned automatically

**Solution**:
```bash
# Check maintenance timer status
sudo systemctl status maintenance.timer

# Run cleanup manually
sudo /usr/local/bin/cleanup-system.sh

# Verify timer is actually scheduled
sudo systemctl list-timers maintenance.timer
```

## 🐛 General Issues

### Scripts Not Executing

**Problem**: Scripts not running when triggered by timers

**Solution**:
```bash
# Check script permissions
ls -la /usr/local/bin/*.sh

# Make scripts executable
sudo chmod +x /usr/local/bin/*.sh

# Check service logs
sudo journalctl -u service_name -n 20
```

### Logs Not Being Written

**Problem**: Log files not being created or updated

**Solution**:
```bash
# Check log directory permissions
ls -la /var/log/

# Check if user has write permissions
sudo touch /var/log/test.log

# Check disk space
df -h /var

# Verify log directory exists
ls -la /home/deon/.local/share/
```

### Timers Not Triggering

**Problem**: Systemd timers not firing at scheduled times

**Solution**:
```bash
# Check timer status
sudo systemctl status timer_name

# Check timer next trigger time
sudo systemctl show timer_name --property=NextElapseUSec

# Reload systemd
sudo systemctl daemon-reload

# Restart timer
sudo systemctl restart timer_name
```

## 📞 Getting Additional Help

If you continue to experience issues:

1. Check the logs in /var/log/ and /home/deon/.local/share/
2. Review the main README.md for configuration guidance
3. Open an issue on GitHub with:
   - System information (OS, distribution, version)
   - Exact error messages
   - Steps to reproduce
   - Relevant logs
4. Check CONFIGURATION_EXAMPLES.md for configuration alternatives

## 🔧 System Information Collection

When reporting issues, provide:

```bash
# System information
uname -a
cat /etc/os-release

# Service status
sudo systemctl list-timers --all
sudo systemctl list-units --state=running

# Script versions
ls -la /usr/local/bin/*.sh

# Recent logs
sudo journalctl -n 50
cat /var/log/backup.log | tail -20
cat /var/log/maintenance.log | tail -20
```
