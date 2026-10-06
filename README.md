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

# Also apply the system performance tuning and network hardening, which
# mutate live system state (sysctl, firewall rules, docker daemon) and are
# therefore opt-in rather than an automatic side effect of installing:
sudo APPLY_HARDENING=1 ./install.sh
```

The installer backs up `/etc/docker/daemon.json` before rewriting it, creates
`/backups` with mode `700` (it holds database dumps), and installs only the
scripts from this repository into `/usr/local/bin`. It does **not** copy
arbitrary `.sh` files out of your home directory.

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
| 02:30 | PostgreSQL vacuum & analyze (`vacuum-databases.sh`) | Daily |
| 04:30 | Off-site backup replication | Daily |
| 04:40 | Off-site backup replication (`replicate-backups.sh`) | Daily |
| 04:50 | Backup health check (`check-backup-health.sh`) | Daily |
| 05:00 | AIDE file integrity check | Daily |
| 06:00 | Trivy container scan | Weekly (Sun) |
| 07:00 | OWASP ZAP scan | Weekly (Sun) |
| 08:00 | Compliance report | Weekly (Mon) |
| 09:00 | Access review | Weekly (Mon) |
| 10:00 | OPA policy evaluation | Weekly (Mon) |
| Every 4h | Resource rightsizing | Continuous |
| Every 6h | Audit trail generation | Continuous |
| Every 5m | Metrics exporter (`prometheus/business-metrics-exporter.sh`) | Continuous |

> **All of these point at this repository.** A stale copy of these scripts
> elsewhere on the host will keep running on schedule while the repository is
> fixed but unused. That is not hypothetical: a fork under `/home/deon/scripts`
> ran nightly for the life of the crontab, targeted containers from another
> project, and reported success over empty files.
>
> **Backup health is verified against the archives, not a log.**
> `scripts/backups/check-backup-health.sh` inspects each backup: a real
> PostgreSQL dump must carry the `PostgreSQL database dump` header (a failed dump
> gzips to ~50 bytes), an RDB must start with the `REDIS` magic, a volume tarball
> must list a member, and a success marker must exist and be recent. It exits
> non-zero listing what is wrong, and records its verdict where the exporter
> publishes it as `backup_health_check_ok`, so `BackupHealthCheckFailed` can
> alert. Run it directly at any time — it reads only.
>
> **The exporter must actually be scheduled.** It is not a container: it is a
> script that writes `.prom` files for the node-exporter textfile collector, and
> nothing runs it unless a cron entry exists. Without it, `backup_last_success_timestamp`
> and the system/docker gauges do not exist, and Prometheus does not fire a rule
> whose series is absent — so `BackupStale` would silently never alert.
> `MetricsExporterNotRunning` exists to make that condition visible.
>
> ```bash
> crontab -l | grep -q business-metrics-exporter || \
>   (crontab -l; echo "*/5 * * * * $PWD/prometheus/business-metrics-exporter.sh") | crontab -
> ```
>
> The backup jobs must point at this repository. A stale copy of these scripts
> elsewhere on the host will keep running on schedule while the repository is
> fixed but unused, which is how 81 empty archives accumulated here while every
> job reported success.

## Monitoring Stack

Credentials are **required**. `docker compose` refuses to start without them
rather than falling back to a default password, so populate them first:

```bash
cp .env.example .env
$EDITOR .env          # GRAFANA_ADMIN_PASSWORD, POSTGRES_PASSWORD,
                      # REDIS_PASSWORD, POSTGRES_EXPORTER_DSN

docker compose -f docker-compose.monitoring.yml up -d
```

```bash
# Access points (all bound to 127.0.0.1, so reach them from the host or over an
# SSH tunnel -- they are not exposed on any other interface):
#   Grafana:      http://localhost:3002   (user + GRAFANA_ADMIN_PASSWORD)
#   Prometheus:   http://localhost:9090
#   Alertmanager: http://localhost:9093
#   Blackbox:     http://localhost:9115
#   Dashboard:    http://localhost:8081
#   Loki:         http://localhost:3100   (logging stack)
```

Redis and PostgreSQL are **not** published to the host at all; they are reachable
only on the internal `monitoring` network by the exporters.

> **Upgrading an existing deployment:** `POSTGRES_PASSWORD` only takes effect when
> the `postgres-data` volume is first initialised. Changing it in `.env` will not
> change the password in an existing volume, and the postgres exporter will then
> fail to authenticate. Either run
> `docker compose exec postgres psql -U postgres -c "ALTER USER postgres PASSWORD '<new>'"`
> or destroy the volume (this discards the data).

### Alertmanager Integrations

**Slack is the only notification channel.** The webhook URL is **not** read from
`.env` — Alertmanager performs no `${VAR}` substitution in its config file.
Supply it via:

```bash
SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' \
  scripts/setup-notification-channels.sh --test
```

That writes the URL to `prometheus/alertmanager-secrets/slack_webhook_url` at mode
`0600` (the directory is bind-mounted read-only and gitignored), restarts
Alertmanager, waits for readiness, and confirms Prometheus still points at it.

`--test` posts a self-resolving critical alert and reads the dispatcher log to
confirm it was actually **delivered**, not merely accepted. This matters because
`amtool check-config` is not a delivery test: `*_file` options are not
existence-checked, so it reports success with the webhook missing. The script also
reads the secret back from inside the container, since a permissions mismatch
there fails only at notification time while `/-/ready` still returns 200. It exits
non-zero while no webhook is configured.

Severity is expressed by the message's attachment colour and title prefix
(`danger` / `warning` / `good`) rather than by separate channels: Slack routes an
incoming webhook to the channel it was created for and commonly ignores the
`channel`, `username` and `icon_emoji` fields, so per-severity channel names in
`alertmanager.yml` would be decorative. Pick the channel when you create the
webhook.

`Watchdog` is a continuous informational alert routed to its own receiver. It is
the dead-man's switch: its **absence** means alerting itself is broken, which is
the one condition no other alert in this stack can report.

See `prometheus/alertmanager-secrets/README.md` for details.

## Security Tools

Everything below is present in this repository. Vulnerability scanning runs in
CI via the Trivy and OPA jobs; the local scripts complement that.

```bash
# Intrusion Detection
sudo scripts/security/install-ids-ips.sh      # Suricata + fail2ban
sudo scripts/security/run-security-hardening.sh

# Vulnerability Scanning
scripts/security/scan-docker-images.sh
scripts/security/scan-dependencies.sh

# Docker daemon and API hardening
sudo scripts/security/docker-security-hardening.sh
scripts/security/api-security-hardening.sh

# Audit policy against Docker and the host (same checks CI runs)
opa check scripts/security/opa/policies/
opa eval --format raw --data scripts/security/opa/policies \
  --input <(echo '{}') 'count([m | data.security[k].deny[m]])'
```

> **Not implemented here.** This repository does not contain AIDE/file-integrity
> checking, a standalone Trivy wrapper, SonarQube or OWASP ZAP orchestration, or
> a compliance report generator. The Trivy scan is the CI job in
> `.github/workflows/security-scanning.yml`; run it locally with
> `docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
> aquasec/trivy image --severity HIGH,CRITICAL <image>`.

## Security Metrics from the Spectre Agent

`prometheus/security-metrics-exporter.sh` publishes security findings from the
Spectre agent into Prometheus. It is a cron-driven script writing `.prom` files
for the node-exporter textfile collector, so **nothing publishes these metrics
unless the cron entry exists**:

```bash
crontab -l | grep -q security-metrics-exporter || \
  (crontab -l; echo "*/5 * * * * $PWD/prometheus/security-metrics-exporter.sh") | crontab -
```

### Configuration

| Variable | Default | Meaning |
|----------|---------|---------|
| `SPECTRE_AGENT_URL` | `http://127.0.0.1:8106` | Base URL of the agent's API. |
| `SPECTRE_API_KEY_FILE` | `<repo>/.spectre-api-key` | Agent API key, mode `0600`. |
| `SPECTRE_TIMEOUT` | `10` | Per-request timeout, seconds. |

The API key is mandatory because the agent's API is fail-closed: without a valid
`X-API-Key` every endpoint returns `401`, and with `SPECTRE_API_KEY` unset in the
agent it returns `503`. Create it with `install -m 600 /dev/null
.spectre-api-key`. It is gitignored (`.gitignore`) and must never be committed.

> **Why the port is 8106 and not the agent's shipped 8000.** 8000 is held by
> `arcaden-labs-api-edge-1` on this host, and that stack occupies 8001–8110 as
> well. Pointing the exporter at 8000 produced a `404` from that unrelated
> service on every scrape, which read as "the agent has no
> `/api/security/summary`" — so the suite reported the agent down while the
> exporter was the broken half. The agent is bound to 8106 on loopback via
> `spectre-api.service` (unit and `SPECTRE_API_HOST`/`SPECTRE_API_PORT` handling
> live in the agent repository). **If you move the agent's port, change
> `SPECTRE_AGENT_URL` to match, or this file publishes nothing.**

### Distinguishing a collision from an outage

The exporter verifies the identity of whatever is on the port before trusting
it, because "the agent is down" and "something else has the port" need opposite
remedies. It reads `/openapi.json` — which FastAPI serves ahead of the API-key
guard — and refuses to publish unless the service names itself `Spectre API`.

`404` on `/openapi.json` proves nothing: a proxy, a stripped path, or an older
agent all legitimately lack it. That case falls through to the summary request,
whose own response shape is the fallback test, so a missing `openapi.json` never
fails a healthy agent. A `3xx` or a `200` naming a *different* application is
conclusive and is refused.

Published state:

| Condition | `spectre_agent_up` | `spectre_agent_up_reason` | `spectre_agent_identifies_as` |
|-----------|--------------------|---------------------------|-------------------------------|
| Agent answered | `1` | — | — |
| Nothing listening | `0` | `connection_refused` | *(absent)* |
| Timed out | `0` | `timed_out` | *(absent)* |
| Wrong/revoked key | `0` | `api_key_rejected` | *(absent)* |
| `SPECTRE_API_KEY` unset in agent | `0` | `agent_serving_unauthenticated` | *(absent)* |
| Different app on the port | `0` | `wrong_service_on_port` | set to what it actually is |
| Agent predates the expected route | `0` | `endpoint_not_found` | *(absent)* |

Finding counts are **omitted entirely** in every `0` state rather than published
as zero, because a zero is indistinguishable from "the agent scanned and found
nothing". `SecurityAgentDown` is a separate alert for that reason. A collision
additionally fires `SecurityAgentWrongServiceOnPort`, which is a configuration
error rather than an outage.

`security_last_scan_timestamp` is always the agent's recorded scan time, never
the moment the exporter polled. A stale database therefore reports a stale scan
instead of asserting that one just completed — an earlier version of this
exporter hardcoded the current time and reported scans that never happened.

## Secrets Management

Notification credentials are the secrets this stack consumes, and they are
written to files rather than interpolated into the Alertmanager config (which
performs no `${VAR}` substitution):

```bash
SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' \
  scripts/setup-notification-channels.sh
```

Database credentials come from `.env`, which the Compose stack requires and will
refuse to start without. See `.env.example`.

> **Not implemented here.** There is no Vault integration and no script that
> injects secrets into project files. Only the `.env` file and the Alertmanager
> secret files described above are supported.

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
| `POSTGRES_CONTAINER` | `postgres` | `backup-databases.sh`, `restore-databases.sh` (only honoured when set explicitly) |
| `REDIS_CONTAINER` | `redis` | `backup-databases.sh` |
| `NEO4J_CONTAINER` | `neo4j` | `backup-databases.sh` (skipped when absent) |
| `BACKUP_DIR` | `/backups/databases` | all backup/restore scripts |
| `BACKUP_STATE_DIR` | `/backups/backup-state` | `backup-databases.sh`, exporter (must match: a mismatch reads 0 forever) |
| `PROMETHEUS_CONTAINER` | `prometheus` | `setup-notification-channels.sh`, `setup-prometheus-alerts.sh` |
| `ALERTMANAGER_CONTAINER` | `alertmanager` | `setup-notification-channels.sh` |
| `SECRETS_DIR` | `prometheus/alertmanager-secrets` | `setup-notification-channels.sh` |
| `READY_TIMEOUT` | `60` (seconds to wait for `/-/ready`) | `setup-notification-channels.sh` |
| `TEST_TIMEOUT` | `90` (seconds to wait for the `--test` delivery attempt) | `setup-notification-channels.sh` |

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
# WireGuard VPN
sudo scripts/network/setup-vpn.sh

# Hardening and inspection
sudo scripts/network/harden-network-security.sh
scripts/network/optimize-network-config.sh
scripts/network/monitor-network.sh
```

> **Not implemented here.** There is no client-management helper
> (`add-vpn-client`) and no DDoS mitigation script. Configure clients in
> `/etc/wireguard/wg0.conf` directly.

## Database Optimization

```bash
# Host and container performance
sudo scripts/performance/optimize-system-performance.sh
sudo scripts/performance/optimize-docker-resources.sh
scripts/performance/check-performance.sh

# Reclaim space and inspect the host
sudo scripts/maintenance/cleanup-system.sh
scripts/maintenance/check-disk-space.sh
```

> **Not implemented here.** There is no `pg_vacuum` helper, no PgBouncer Compose
> file under `performance/`, and no read-replica setup. Manage vacuum and
> replication with the PostgreSQL tooling appropriate to your deployment.

## Load Testing

> **Not implemented here.** This repository ships no k6, Locust, or
> performance-regression harness, and no capacity-planning tooling. Use the load
> tooling of your choice against your own environment.

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
│   ├── alertmanager.yml     #    Slack
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

Every path below exists in this repository.

```bash
# Backup and restore
scripts/backups/backup-all.sh                    # Full backup
scripts/backups/backup-verification.sh           # Verify existing backups
scripts/backups/restore-databases.sh             # Restore databases
scripts/backups/restore-from-remote.sh           # Restore from off-site copy
sudo scripts/backups/setup-offsite-backup.sh     # Configure off-site + cron

# Security
scripts/security/scan-docker-images.sh            # Container scan
scripts/security/scan-dependencies.sh            # Dependency scan
sudo scripts/security/docker-security-hardening.sh
opa check scripts/security/opa/policies/         # Policy audit

# Monitoring
docker compose -f docker-compose.monitoring.yml up -d   # Start stack
prometheus/business-metrics-exporter.sh           # Export host metrics
scripts/check-config-consistency.sh               # Config references resolve

# Maintenance
scripts/maintenance/audit-trail.sh                # Generate audit
scripts/maintenance/compliance-report.sh          # Compliance check
sudo scripts/maintenance/cleanup-system.sh        # Cleanup
scripts/maintenance/system-health-check.sh        # Host health
```

Container vulnerability scanning is the Trivy job in
`.github/workflows/security-scanning.yml`; it is not wrapped in a local script.

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
