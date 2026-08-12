# Linux System Maintenance & Security Automation

A comprehensive system maintenance, security, monitoring, and disaster recovery automation suite for Linux workstations and servers. Features automated backups, centralized logging, enhanced monitoring with alertmanager integrations, secrets management, intrusion detection, automated security scanning, VPN, CI/CD, load testing, database optimization, audit logging, policy enforcement, and cost optimization.

## Features

| Category | Capabilities |
|----------|-------------|
| **Backups** | Automated database, Docker volume, config, project backups with cron scheduling, off-site replication (rsync/S3/B2), encryption |
| **Monitoring** | Prometheus + Grafana + Alertmanager, Blackbox exporter (HTTP/TCP/ICMP/DNS), business metrics, uptime monitoring, custom dashboards |
| **Logging** | Centralized Loki stack, container log rotation, retention policies, log shipping to remote destinations |
| **Security** | Fail2Ban brute force protection, AIDE file integrity, Wazuh HIDS, Trivy container scanning, SonarQube code analysis, OWASP ZAP web testing, OPA policy enforcement |
| **Secrets** | Environment-based secret injection, HashiCorp Vault support, .env template with secure permissions; **`.env`/secret files are excluded from all backup paths** |
| **Network** | WireGuard VPN, network segmentation (internal/DMZ), DDoS protection, firewall hardening |
| **CI/CD** | GitHub Actions workflows for syntax check, security scanning, DR test, load testing, multi-distro testing |
| **DR** | RTO/RPO definitions, 10 incident runbooks, backup verification, DR testing schedule |
| **Load Testing** | k6 and Locust scripts, performance regression testing, capacity planning |
| **Database** | Automated vacuum/analyze, PgBouncer connection pooling, read replica setup |
| **Audit** | auditd rules, centralized audit trail, compliance reports, sudo command logging, access reviews |
| **Policy** | OPA policies for Docker security, backups, network, compliance; automated evaluation |
| **Cost** | Cloud cost tracking, resource rightsizing, automated cleanup of unused resources |
| **ML** | Anomaly detection (Isolation Forest, One-Class SVM, ensemble) + free local-LLM auto-remediation (Ollama) with safety-validated fixes |

## Quick Start

```bash
git clone https://github.com/bigwalkdoe/spectre-system-maintenance-suite.git
cd spectre-system-maintenance

# Full automated setup (recommended)
sudo ./install.sh

# Or deploy all enhancements at once
bash scripts/setup-all-enhancements.sh
```

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                spectre-system-maintenance                    │
├────────────┬──────────┬──────────┬──────────┬───────────────┤
│ Monitoring │ Security │ Backups  │ Logging  │ Automation    │
├────────────┼──────────┼──────────┼──────────┼───────────────┤
│ Prometheus │ Fail2Ban │ Database │ Loki     │ Cron jobs     │
│ Grafana    │ AIDE     │ Volumes  │ Promtail │ systemd timer │
│ Alertmanag │ Wazuh    │ Configs  │ Logrotate│ CI/CD (GA)    │
│ Blackbox   │ Trivy    │ Projects│ Shipping │ Ansible       │
│ Node/PG/RE │ OPA      │ Off-site │          │ Terraform     │
└────────────┴──────────┴──────────┴──────────┴───────────────┘
```

## Automated Schedule

| Time | Task | Frequency |
|------|------|-----------|
| 01:00 | Database backup | Daily |
| 02:00 | Full backup (Sat) / Docker volume backup | Daily/Weekly |
| 02:30 | PostgreSQL vacuum & analyze | Daily |
| 04:30 | Off-site backup replication | Daily |
| 05:00 | AIDE file integrity check | Daily |
| 06:00 | Trivy container scan | Weekly (Sun) |
| 07:00 | OWASP ZAP scan | Weekly (Sun) |
| 08:00 | Compliance report | Weekly (Mon) |
| 09:00 | Access review | Weekly (Mon) |
| 10:00 | OPA policy evaluation | Weekly (Mon) |
| Every 4h | Resource rightsizing | Continuous |
| Every 6h | Audit trail generation | Continuous |

## Monitoring Stack

```bash
docker-compose -f docker-compose.monitoring.yml up -d

# Access points:
#   Grafana:      http://localhost:3002   (admin/changeme)
#   Prometheus:   http://localhost:9090
#   Alertmanager: http://localhost:9093
#   Blackbox:     http://localhost:9115
#   Dashboard:    http://localhost:8081
#   Loki:         http://localhost:3100   (logging stack)
```

### Alertmanager Integrations
- **Slack**: Channels for critical, warning, info, watchdog alerts
- **Email**: SMTP-based notifications with HTML templates
- **PagerDuty**: Critical alert routing with severity mapping
- **Webhook**: Custom endpoint integration

## Security Tools

```bash
# Intrusion Detection
sudo systemctl start fail2ban          # Brute force protection
scripts/security/check-file-integrity.sh  # AIDE check

# Vulnerability Scanning
scripts/security/run-trivy-scan.sh

# Code Analysis
docker-compose -f security/sonarqube/docker-compose.yml up -d
scripts/security/run-sonarqube-analysis.sh

# Web App Testing
docker-compose -f security/zap/docker-compose.yml up -d
scripts/security/run-zap-scan.sh http://localhost:3000

# Policy Enforcement
scripts/security/opa/evaluate-policies.sh
```

## Secrets Management

```bash
# Edit your secrets
vim /home/deon/.secrets/environment

# Source into environment
source /home/deon/.secrets/environment

# Inject into project files
scripts/security/inject-secrets.sh

# Or use Vault
scripts/security/vault-secrets.sh store database/postgres password mypass
scripts/security/vault-secrets.sh get database/postgres password
```

## Configuration & Portability

All scripts are portable and fail-loud: every script uses `set -euo pipefail`,
resolves its own location via `SCRIPT_DIR` (no hard-coded user paths), and honours
the following environment overrides:

| Variable | Default | Used by |
|----------|---------|---------|
| `PROJECTS_ROOT` | `$HOME/projects` | Project backups, health checks, dependency scanning |
| `PROJECTS_DIR` | `/home/deon/projects` | `backup-configurations.sh` (project config backup) |
| `BACKUP_DIR` | `/backups/<type>` | All backup/restore scripts |
| `LOG_FILE` | `/var/log/...` (falls back to `$TMPDIR`/`/tmp` if unwritable) | `restore-databases.sh` |
| `POSTGRES_CONTAINER` | `guardrail-ai-postgres-1` | `backup-databases.sh` |
| `REDIS_CONTAINER` | `guardrail-ai-redis-1` | `backup-databases.sh` |
| `NEO4J_CONTAINER` | `guardrail-ai-neo4j-1` | `backup-databases.sh` |
| `PROMETHEUS_CONTAINER` | `guardrail-ai-prometheus-1` | `setup-notification-channels.sh`, `setup-prometheus-alerts.sh` |
| `ALERTMANAGER_CONTAINER` | `guardrail-alertmanager` | `setup-notification-channels.sh` |

`REPO_ROOT` is derived automatically from the script location and should not
normally need overriding. Orchestrator scripts (`run-maintenance.sh`,
`run-security-hardening.sh`, `backup-all.sh`, `backup-all-projects.sh`) run every
step and report per-step status rather than aborting on the first failure.

**Secrets in backups:** `.env` files, `secrets/` directories, and other credential
material are deliberately excluded from `backup-configurations.sh`,
`backup-projects.sh`, and the project-specific backups (`backup-modelink.sh`,
). Store credentials via the Secrets Management flow above.

## VPN & Network

```bash
# Start WireGuard VPN
sudo systemctl start wg-quick@wg0

# Add a client
scripts/network/add-vpn-client.sh my-laptop 10.0.0.2

# Check DDoS status
scripts/network/ddos-mitigation.sh
```

## Database Optimization

```bash
# Run vacuum manually
scripts/performance/pg-vacuum.sh

# Start PgBouncer connection pool
docker-compose -f performance/pgbouncer/docker-compose.yml up -d
# Connect: psql -h localhost -p 6432 -U postgres -d guardrail

# Set up read replica
scripts/performance/setup-read-replica.sh
```

## Load Testing

```bash
# k6 test (10 VUs, 30s)
bash scripts/performance/load-testing/run-k6-test.sh http://localhost:3000 10 30s

# Locust test
bash scripts/performance/load-testing/run-locust-test.sh http://localhost:3000 10 1 60s

# Performance regression
bash scripts/performance/load-testing/run-performance-regression.sh

# Capacity planning
bash scripts/performance/load-testing/capacity-planning.sh
```

## Disaster Recovery

- **RTO/RPO**: Database (1h/15min), Redis (30min/1h), Full system (4h/1d)
- **Runbooks**: 10 incident-specific runbooks in `docs/RUNBOOKS.md`
- **DR Plan**: Full recovery procedures in `docs/DISASTER_RECOVERY.md`
- **Testing**: Weekly backup verification, monthly DB restore drill, bi-annual full DR

## CI/CD Pipeline

Three GitHub Actions workflows:
- **ci-cd.yml**: Syntax check, tests, Trivy scan, Docker build, multi-distro test, deployment
- **security-scanning.yml**: Weekly Trivy scan, OPA policy check, k6 load test
- **disaster-recovery-test.yml**: Weekly backup verification, DR documentation check

## Project Structure

```
spectre-system-maintenance/
├── .github/workflows/       # CI/CD pipelines
├── cloud-deployment/        # Terraform + Ansible
│   ├── terraform/           #    Infrastructure as code
│   └── ansible/             #    Configuration management
├── docs/                    # Documentation
│   ├── DISASTER_RECOVERY.md #    RTO/RPO + runbooks
│   └── RUNBOOKS.md          #    10 incident runbooks
├── prometheus/              # Monitoring configs
│   ├── alertmanager.yml     #    Slack/Email/PagerDuty
│   ├── blackbox-exporter.yml#    External monitoring
│   └── business-metrics*    #    Custom metrics
├── grafana-*/               # Grafana dashboards
├── scripts/                 # Enhancement scripts
├── docker-compose.monitoring.yml
└── install.sh
```

scripts/
├── backups/                 # Backup + off-site replication + restore
│   ├── backup-*.sh          #   Database, volume, config, project backups
│   ├── restore-*.sh         #   Database, volume, remote restore scripts
│   ├── backup-encryption.sh #   AES-256-CBC backup encryption
│   └── backup-verification.sh # Backup integrity verification
├── logging/                 # Loki stack + logrotate
├── maintenance/             # Audit, cleanup, optimization
│   ├── audit-trail.sh       #   Centralized audit logging
│   ├── compliance-report.sh #   Compliance reporting
│   ├── check-performance.sh #   Performance monitoring
│   ├── network-monitor.sh   #   Network connectivity monitoring
│   ├── check-disk-space.sh  #   Disk usage monitoring
│   ├── network-security-hardening.sh # Network security hardening
│   └── cleanup-*.sh         #   System + log cleanup
├── network/                 # WireGuard, DDoS, segmentation
├── performance/             # Load testing, vacuum, rightsizing
│   └── load-testing/        # k6, Locust, regression
└── security/                # IDS, scanning, OPA, secrets
    ├── opa/policies/        #   Rego policy files (firewall, audit, docker,
    │                        #   network, backups, intrusion_detection,
    │                        #   compliance, encryption)
    ├── run-trivy-scan.sh    #   Trivy container scanning
    └── check-file-integrity.sh # AIDE file integrity check
    ├── sonarqube/           # Code analysis
    └── zap/                 # Web app testing

## Requirements

- **OS**: Fedora, Ubuntu, Debian, RHEL, Arch (auto-detected)
- **Docker** + Docker Compose
- **Systemd** (for timers)
- **Bash** 4+
- Root/sudo access for system-level configs

## Quick Commands Reference

```bash
# Backup
scripts/backups/backup-all.sh                    # Full backup
scripts/backups/replicate-to-remote.sh           # Off-site sync

# Security
scripts/security/run-trivy-scan.sh               # Container scan
scripts/security/check-file-integrity.sh          # AIDE check
scripts/security/opa/evaluate-policies.sh         # Policy audit

# Monitoring
docker-compose -f docker-compose.monitoring.yml up -d        # Start stack
spectre-system-maintenance/prometheus/business-metrics-exporter.sh   # Export metrics

# Maintenance
scripts/maintenance/audit-trail.sh                # Generate audit
scripts/maintenance/compliance-report.sh          # Compliance check
scripts/maintenance/cleanup-unused-resources.sh   # Cleanup

# Database
scripts/performance/pg-vacuum.sh                 # Vacuum DB
scripts/performance/resource-rightsizing.sh      # Analyze usage

# Load test
bash scripts/performance/load-testing/run-k6-test.sh
```

## Documentation

| Document | Description |
|----------|-------------|
| `docs/ADVANCED_SECURITY_FEATURES.md` | IDS/IPS, advanced threat detection |
| `docs/ML_ANOMALY_DETECTION.md` | ML-based anomaly detection |
| `docs/MULTI_DISTRIBUTION_SUPPORT.md` | Multi-distro support details |
| `docs/TESTING_AND_CICD.md` | Test suite and CI/CD pipeline |
| `docs/DISASTER_RECOVERY.md` | RTO/RPO, incident runbooks |
| `docs/RUNBOOKS.md` | 10 common incident resolution guides |
| `docs/CONFIGURATION_EXAMPLES.md` | Configuration examples |
| `docs/TROUBLESHOOTING.md` | Troubleshooting guide |
| `cloud-deployment/docs/CLOUD_DEPLOYMENT_GUIDE.md` | Cloud deployment |

## License

MIT
