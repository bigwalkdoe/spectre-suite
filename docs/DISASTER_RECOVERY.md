# Disaster Recovery Documentation

## Recovery Time Objective (RTO) & Recovery Point Objective (RPO)

| Service | RTO | RPO | Priority |
|---------|-----|-----|----------|
| PostgreSQL Database | 1 hour | 15 minutes | Critical |
| Redis Cache | 30 minutes | 1 hour | High |
| Docker Volumes | 2 hours | 1 day | High |
| Application Configurations | 1 hour | 1 day | High |
| Web Dashboard | 30 minutes | N/A | Medium |
| Monitoring Stack | 2 hours | 7 days | Medium |

---

## Incident Response Runbooks

### 1. Database Failure

```bash
# 1. Check database status
docker ps | grep postgres
docker logs --tail 50 guardrail-ai-postgres-1

# 2. Verify backup exists
ls -la /backups/databases/
find /backups/databases -name "postgres_*" -mtime -1

# 3. Restore from latest backup
LATEST_BACKUP=$(ls -t /backups/databases/postgres_guardrail_*.gz | head -1)
gunzip -c "$LATEST_BACKUP" | docker exec -i guardrail-ai-postgres-1 psql -U postgres -d guardrail

# 4. Verify data integrity
docker exec guardrail-ai-postgres-1 psql -U postgres -d guardrail -c "SELECT count(*) FROM information_schema.tables;"

# 5. If backup restoration fails, promote replica (if configured):
# docker exec guardrail-ai-postgres-replica-1 psql -U postgres -c "SELECT pg_promote();"
```

### 2. Server/System Failure

```bash
# 1. Provision new instance via Terraform
cd /home/deon/dev/github/system-maintenance/cloud-deployment/terraform
terraform plan
terraform apply

# 2. Run Ansible to reconfigure
cd /home/deon/dev/github/system-maintenance/cloud-deployment/ansible
ansible-playbook -i inventory/production.yml playbook.yml

# 3. Restore data from off-site backup
/home/deon/scripts/backups/restore-from-remote.sh

# 4. Verify services
/home/deon/scripts/healthcheck.sh
```

### 3. Docker Daemon Failure

```bash
# 1. Restart Docker daemon
sudo systemctl restart docker

# 2. If daemon.json is corrupted, restore backup
cp /backups/configurations/docker_configs_*.tar.gz /tmp/
tar -xzf /tmp/docker_configs_*.tar.gz -C /tmp/
sudo cp /tmp/etc/docker/daemon.json /etc/docker/daemon.json

# 3. Restart all containers
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml up -d

# 4. Restore volumes from backup
/home/deon/scripts/backups/restore-docker-volumes.sh
```

### 4. Security Breach

```bash
# 1. Isolate affected system
sudo iptables -A INPUT -s <attacker_ip> -j DROP
sudo fail2ban-client set sshd banip <attacker_ip>

# 2. Run security scan
/home/deon/scripts/security/run-trivy-scan.sh
/home/deon/scripts/security/check-file-integrity.sh

# 3. Review logs
sudo journalctl -u docker --since "24 hours ago" | grep -i error
tail -100 /var/log/auth.log | grep -i "failed\|error\|unauthorized"

# 4. Rotate credentials
/home/deon/scripts/security/inject-secrets.sh
sudo systemctl restart all services

# 5. Generate incident report
/home/deon/scripts/security/generate-security-report.sh
```

### 5. Disk Space Exhaustion

```bash
# 1. Identify large files
du -sh /* 2>/dev/null | sort -rh | head -10
du -sh /var/log/* 2>/dev/null | sort -rh | head -10

# 2. Clean up immediately
/home/deon/scripts/maintenance/cleanup-system.sh
/home/deon/scripts/maintenance/cleanup-logs.sh

# 3. Remove old Docker data
docker system prune -af --volumes 2>/dev/null || true

# 4. Check if rotation is working
sudo logrotate -d /etc/logrotate.d/system-maintenance

# 5. Add alert if below threshold
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo "CRITICAL: Disk at ${DISK_USAGE}%"
    # Notify via alertmanager
fi
```

### 6. Monitoring Stack Failure

```bash
# 1. Check container status
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml ps

# 2. Restart individual services
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml restart prometheus
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml restart grafana
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml restart alertmanager

# 3. If config is corrupted, restore from git
cd /home/deon/dev/github/system-maintenance
git checkout -- prometheus/prometheus.yml
git checkout -- docker-compose.monitoring.yml

# 4. Full restart
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml down
docker-compose -f /home/deon/dev/github/system-maintenance/docker-compose.monitoring.yml up -d
```

---

## Recovery Procedures

### Full System Recovery

```bash
# Step 1: Provision infrastructure
cd /home/deon/dev/github/system-maintenance/cloud-deployment
./deploy.sh aws production 2

# Step 2: Restore configuration
scp -r user@backup-server:/backups/configurations/latest/ /tmp/config-restore/
sudo cp -r /tmp/config-restore/* /

# Step 3: Restore databases
/home/deon/scripts/backups/restore-databases.sh

# Step 4: Restore Docker volumes
/home/deon/scripts/backups/restore-docker-volumes.sh

# Step 5: Start services
docker-compose -f docker-compose.monitoring.yml up -d

# Step 6: Verify
/home/deon/scripts/healthcheck.sh
```

### Backup Verification Procedure

```bash
# Weekly: Verify backup integrity
for backup in /backups/databases/*.gz; do
    gzip -t "$backup" && echo "OK: $backup" || echo "CORRUPT: $backup"
done

# Monthly: Test restore to staging
# Run in isolated environment:
# docker run --rm -v /backups/databases:/backups postgres bash -c "
#     gunzip -c /backups/postgres_latest.sql.gz | psql -h test-host -U test-user test-db
# "
```

---

## Communication Plan

| Severity | Notification Method | Response Time | Escalation |
|----------|-------------------|---------------|------------|
| Critical | PagerDuty + Slack + Email | 15 minutes | Manager + On-call team |
| High | Slack + Email | 1 hour | On-call team |
| Medium | Email | 4 hours | Next business day |
| Low | Dashboard alert | 24 hours | Next sprint |

### Notification Contacts

- **PagerDuty**: Configured in alertmanager.yml (routing_key)
- **Slack**: #alerts-critical, #alerts-warning channels
- **Email**: Configured in alertmanager.yml (smtp)

---

## Disaster Recovery Testing Schedule

| Test Type | Frequency | Scope | Success Criteria |
|-----------|-----------|-------|------------------|
| Database restore | Monthly | Single DB | < 1 hour RTO |
| Volume restore | Quarterly | Docker volumes | All services running |
| Full DR drill | Bi-annual | Complete system | Meet all RTO/RPO |
| Failover test | Quarterly | Primary -> Standby | < 5 minute failover |
| Backup integrity | Weekly | All backups | No corrupt files |

---

## Key Contacts & Resources

- **System Administrator**: sysadmin@example.com
- **Security Team**: security@example.com
- **Cloud Provider Support**: AWS/Azure/GCP support portal
- **Backup Server**: backup.example.com (port 2222)
- **Off-site Storage**: S3 bucket /backups/
- **DR Coordinator**: dr-coordinator@example.com

---

*Last Updated: 2026-06-26*
*Review Cycle: Monthly*
