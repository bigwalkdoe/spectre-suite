# Operations Runbooks

## Common Incidents and Resolution Steps

---

### Runbook 1: High CPU Usage

**Symptoms:**
- Alert: HighCPUUsage or CriticalCPUUsage
- Slow application response times

**Check:**
```bash
top -bn1 | head -20
ps aux --sort=-%cpu | head -10
docker stats --no-stream
```

**Resolution:**
```bash
# Identify culprit container
docker stats --no-stream | sort -k3 -r | head -5

# Restart if misbehaving
docker restart <container_name>

# Scale if legitimate load
docker-compose up -d --scale <service>=3

# Add resource limits
docker update --cpus=1 --memory=512m <container_name>
```

**Post-mortem:**
- Review CPU trends in Grafana (System Monitoring dashboard)
- Consider auto-scaling if repeated
- Document in incident log

---

### Runbook 2: Disk Space Critical

**Symptoms:**
- Alert: HighDiskUsage or CriticalDiskUsage
- Failed writes, database errors

**Check:**
```bash
df -h
du -sh /var/log/* | sort -rh | head -10
du -sh /backups/* | sort -rh | head -10
docker system df
```

**Resolution:**
```bash
# Immediate cleanup
sudo journalctl --vacuum-time=3d
docker system prune -af
find /var/log -name "*.gz" -mtime +7 -delete

# Check log rotation
sudo logrotate -f /etc/logrotate.d/spectre-system-maintenance
sudo logrotate -f /etc/logrotate.d/docker-containers

# Archive old backups
find /backups -mtime +30 -exec mv {} /backups/archive/ \;
```

**Prevention:**
- Verify logrotate configs
- Add disk monitoring alerts at 80%/90%
- Schedule monthly archive cleanup

---

### Runbook 3: Docker Container Crash Loop

**Symptoms:**
- Container restarting repeatedly
- Alert: ServiceDown

**Check:**
```bash
docker logs --tail 100 <container_name>
docker inspect <container_name> | jq '.[0].State'
docker events --since 5m | grep <container_name>
```

**Resolution:**
```bash
# Stop the container
docker stop <container_name>

# Check resource limits
docker inspect <container_name> | jq '.[0].HostConfig.Memory'

# Increase limits if OOM
docker update --memory=1g <container_name>

# Restart with clean state
docker rm -f <container_name>
docker-compose up -d <service_name>

# If config issue, check mounted volumes
docker exec -it <container_name> cat /app/config.yml
```

---

### Runbook 4: Backup Failure

**Symptoms:**
- Alert: BackupFailed (from business metrics)
- Missing backup files

**Check:**
```bash
tail -100 /var/log/backup.log
ls -la /backups/databases/
journalctl -u backup.service --since "1 hour ago"
```

**Resolution:**
```bash
# Run backup manually
scripts/backups/backup-databases.sh

# Check disk space
df -h /backups

# Verify Docker is running
docker ps

# Check database connectivity
docker exec guardrail-ai-postgres-1 pg_isready

# Fix and re-run
scripts/backups/backup-all.sh
```

---

### Runbook 5: SSL Certificate Expiry

**Symptoms:**
- Browser warnings
- HTTPS failures

**Check:**
```bash
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates
certbot certificates
```

**Resolution:**
```bash
# Auto-renew
sudo certbot renew

# If using ACME
docker exec nginx-proxy certbot renew

# Manual renewal
sudo certbot certonly --standalone -d example.com

# Update services
docker-compose restart nginx
```

---

### Runbook 6: Failed Security Scan

**Symptoms:**
- Alert: CriticalVulnerabilityFound
- CI/CD pipeline failure

**Check:**
```bash
# The CI Trivy job uploads SARIF to the Security tab; there is no committed
# JSON report and no local wrapper script. Produce one on demand:
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v /tmp:/out aquasec/trivy image --format json -o /out/trivy.json <image>
jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL")' /tmp/trivy.json
```

**Resolution:**
```bash
# Immediate mitigation (if applicable)
docker pull <image>:pinned-tag

# Rebuild with patches
docker compose build --no-cache <service>

# Re-run the scan
scripts/security/scan-docker-images.sh

# Record a false positive. Trivy reads .trivyignore from the working directory,
# so create it where you run the scan:
echo "<CVE-ID> false-positive" >> .trivyignore
```

Note that every image in `docker-compose.monitoring.yml` is pinned to an
explicit version, so there is no `:latest` to pull for the monitoring stack.

---

### Runbook 7: Network Connectivity Issues

**Symptoms:**
- Alert: UptimeCheckFailed
- Services unreachable

**Check:**
```bash
scripts/network/network-monitor.sh
ping -c 3 8.8.8.8
curl -sf http://localhost:9090/-/healthy
docker network ls
```

**Resolution:**
```bash
# Restart network
sudo systemctl restart networking

# Restart Docker (last resort)
sudo systemctl restart docker

# Check firewall
sudo iptables -L -n | head -20
sudo firewall-cmd --list-all

# Verify DNS
nslookup google.com
cat /etc/resolv.conf

# Restart affected containers
docker-compose -f docker-compose.monitoring.yml restart
```

---

### Runbook 8: Failed Authentication Rate Limiting

**Symptoms:**
- Legitimate users blocked
- Fail2Ban bans increasing

**Check:**
```bash
sudo fail2ban-client status sshd
sudo fail2ban-client status nginx-limit-req
sudo tail -100 /var/log/fail2ban.log
```

**Resolution:**
```bash
# Unban legitimate IP
sudo fail2ban-client set sshd unbanip <ip_address>

# Adjust limits
sudo sed -i 's/maxretry = 3/maxretry = 5/' /etc/fail2ban/jail.local
sudo systemctl restart fail2ban

# Whitelist trusted IPs
sudo sed -i '/ignoreip/s/$/ <trusted_ip>/' /etc/fail2ban/jail.local
```

---

### Runbook 9: Prometheus/Grafana Data Loss

**Symptoms:**
- Missing metrics in dashboards
- Grafana "No data" errors

**Check:**
```bash
docker logs prometheus | tail -50
docker exec prometheus tsdb list
curl -s http://localhost:9090/api/v1/label/__name__/values | head
```

**Resolution:**
```bash
# Check disk space on prometheus volume
docker exec prometheus df -h /prometheus

# Compact TSDB
docker exec prometheus tsdb compact /prometheus

# If corrupted, restore from backup
docker run --rm -v prometheus-data:/prometheus -v /backups/docker-volumes:/backups alpine \
    tar xzf /backups/prometheus_data_latest.tar.gz

# Replace
docker-compose -f docker-compose.monitoring.yml up -d prometheus
```

---

### Runbook 10: Configuration Drift

**Symptoms:**
- Manual changes not reflected
- Unexpected service behavior

**Check:**
```bash
# Config references must resolve to services that exist. The integrity-check
# script this runbook used to call is not in this repository, so the primary
# diagnostic for this runbook failed on invocation.
scripts/check-config-consistency.sh

# Confirm nothing drifted from version control.
git status --short
git diff -- prometheus/prometheus.yml docker-compose.monitoring.yml

# Compare the live Docker daemon config against the intended one.
diff <(cat /etc/docker/daemon.json) <(echo '{"live-restore":true}')
```

The same consistency check runs in CI as the `Configuration Consistency` job, so
a typo that breaks a scrape target or the dashboard proxy fails the build.

**Resolution:**
```bash
# Restore from version control
cd spectre-system-maintenance
git status
git diff prometheus/prometheus.yml
git checkout -- prometheus/prometheus.yml

# Re-apply via Ansible
cd spectre-system-maintenance/cloud-deployment/ansible
ansible-playbook -i inventory/production.yml playbook.yml --tags config

# Re-run installation script
sudo spectre-system-maintenance/install.sh
```

---

## Incident Log Template

```
INCIDENT REPORT
===============
Date: YYYY-MM-DD HH:MM
Severity: Critical/High/Medium/Low
Service Affected: 
Detected By: Alert/Runbook/Manual
Duration: X hours X minutes

SYMPTOMS:
- 

ROOT CAUSE:
- 

RESOLUTION:
- 

PREVENTION:
- 

LESSONS LEARNED:
- 

Reviewed By:
Date Closed:
```

---

## Runbook Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-06-26 | System Admin | Initial runbooks |
