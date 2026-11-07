# Spectre Suite — Linux System Maintenance, Backup & Monitoring Automation

Spectre Suite is a consolidated Linux operations suite for automated backups, restic snapshot workflows, monitoring/alerting (Prometheus + Grafana + Alertmanager), security hardening/scanning helpers, maintenance jobs, and operational reporting. It provides a unified `spectre` CLI/dispatch layer so scheduled and manual jobs run through one command surface with provenance.

> **Project status (current tree):** The `spectre` CLI/dispatch layer is in place (reference-host schedulers repointed to `spectre run <job>`; dispatcher/registry verification reports 0 findings on the current inventory). Consolidation/migration (C1) is **in progress**: canonical implementations live under `spectre/actions/*` and `spectre/monitoring/exporters/*` (C1 **Tier A** complete: top-level `prometheus/*-exporter.sh` forwarders removed; registry/jobs resolve to canonical actions/exporters). Repo-root `scripts/*.sh` compatibility forwarders still exist as transitional paths. Canonical policy/config paths also live under `spectre/policies/*` and `spectre/actions/ml-anomaly/*`. Use `spectre run <job>` as the operator interface; verify actual state with `spectre actions list` / `spectre actions verify`. See `docs/migration/` and `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md`.

## Features

| Category | Capabilities |
|----------|-------------|
| **Dispatch** | `spectre run <job>`, `spectre actions list/show/verify`; registry-driven jobs with metadata (`sudo`, `mutates`, `timeout`, `schedule_hint`, `concurrency`) and recorded run provenance |
| **Backups** | Database, Docker volume, config, project backups; off-site replication; encryption/verification helpers; missed-backup catch-up; **adopted restic engine** (`backups/restic/*`) with tag-scoped retention and degraded-offsite behavior |
| **Monitoring** | Prometheus + Grafana + Alertmanager, Blackbox exporter, business/security metrics exporters (textfile collector), restic marker metrics, custom dashboards/provisioning |
| **Logging** | Log rotation/retention and shipping helpers (as implemented in repo actions) |
| **Security** | Fail2Ban/IDS-IPS helpers, Docker/API/network hardening actions, dependency/image scanning scripts, OPA policies, Spectre agent security summary exporter (with port/identity collision detection) |
| **Maintenance** | Cache/temp/download/unused-resource cleanup, disk/performance checks, DB vacuum, system health, compliance/audit helpers |
| **Network/Performance** | VPN/network hardening/monitoring actions; system/Docker optimization and resource-rightsizing actions (some require `sudo`/explicit opt-in) |
| **ML** | ML anomaly detection pipeline/actions (`ml-anomaly/*`) where dependencies/config are present |

**Not implemented in this repository:** Loki, Promtail, Wazuh, OWASP ZAP orchestration, SonarQube orchestration, Trivy wrapper script (Trivy runs in CI; run locally via container), PgBouncer/read-replica/Vault deployment, k6/Locust harnesses, or standalone AIDE scheduler/script beyond host-tool reporting. Do not treat README claims as a substitute for `spectre actions list` / `spectre actions verify`.

## Quick Start

```bash
git clone https://github.com/bigwalkdoe/spectre-suite.git
cd spectre-suite

# Inspect available jobs and registry/host consistency
python3 -m spectre.cli.main actions list   # or: spectre actions list (if installed)
python3 -m spectre.cli.main actions verify

# Run a job through the dispatcher
spectre run maintenance/system-health-check
spectre run backups/backup-all -- --help  # pass args to the action after --
```

### Installation / migration note
The consolidation design moves dispatch to the `spectre` CLI and stops installing arbitrary scripts to `/usr/local/bin` (only `spectre` should live there). `install.sh` is now **§8.2-aligned** (installs only `/usr/local/bin/spectre` and generates units that dispatch via `spectre run <job>`), but it is a **root/host-mutating** script — review before use. Prefer the installed `spectre` CLI + `spectre run`/systemd timers that invoke `spectre run`.

On a workstation that sleeps, use the persistent catch-up timer (checks health first; runs only when stale):

```bash
# canonical installer (generates a user timer that runs `spectre run backups/run-missed-backups`)
./spectre/actions/systemd/install-backup-catchup-timer.sh
```

## Unified Dispatch Model

- **Canonical action implementations:** `spectre/actions/<group>/<job>.sh` (and related ML/restic actions)
- **Legacy compatibility paths (C1, in progress):** repo-root `scripts/*.sh` currently remains as Phase 1 compatibility forwarders that delegate to canonical implementations (C1 Tier A removed top-level `prometheus/*-exporter.sh` forwarders); treat legacy forwarders as transitional, not the operator interface. Canonical policy and ML action locations are `spectre/policies/*` and `spectre/actions/ml-anomaly/*` (untracked local artifacts, e.g. a local ML venv, may exist on disk but are not canonical). See `docs/migration/2026-11-06-phase4-c1-repo-inventory-plan.md`.
- **Canonical exporter implementations:** `spectre/monitoring/exporters/*`
- **Registry source of truth:** `spectre/dispatch/registry_data.json` / dispatch modules
- **Verification:** `spectre actions verify` checks registry↔disk↔scheduler consistency and fails loudly on missing/unexecutable/bad syntax/unsafe scheduled-mutation cases (it never silently skips)

```bash
spectre actions list
spectre actions show backups/backup-all
spectre actions verify
spectre run backups/backup-all
```

## Automated Schedule (reference)

Scheduled jobs should be owned by **one scheduler path per job** and invoke `spectre run <job>`. Exact schedules/timers vary by host; confirm with `crontab -l`, `systemctl list-timers --all`, `systemctl --user list-timers --all`, and `spectre actions verify`.

| Typical job | `spectre run` target | Notes |
|---|---|---|
| Database backup | `backups/backup-databases` | daily |
| Docker volume backup | `backups/backup-docker-volumes` | as scheduled |
| Full backup | `backups/backup-all` | weekly/as scheduled |
| DB vacuum | `maintenance/vacuum-databases` | daily |
| Off-site replication | `backups/replicate-backups` | daily |
| Backup health check | `backups/check-backup-health` | daily; verifies archives/markers, not just logs |
| Missed-backup catch-up | `backups/run-missed-backups` | persistent timer (`Persistent=true`), runs after boot/resume; checks health before running |
| Adopted restic backup | `backups/restic/backup` | user timer (e.g. 04:10), local-first/tag-scoped |
| Adopted restic verify | `backups/restic/verify` | user timer (e.g. Sun 05:30) |
| Cleanup/maintenance | `maintenance/cleanup-*`, `maintenance/cleanup-unused-resources` | scheduled as configured |
| Performance/cost checks | `performance/*` | scheduled as configured |
| Metrics exporters | `prometheus/business-metrics-exporter`, `prometheus/security-metrics-exporter` | cron-driven textfile exporters; exporters must run or stale/absent metrics can hide failures |

> **Cron does not catch up after sleep.** Use persistent systemd timers for catch-up-sensitive jobs. `run-missed-backups`/catch-up is cheap when backups are healthy because it checks first.
>
> **Health over logs:** `check-backup-health` inspects archives/markers (e.g., PostgreSQL dump header, Redis RDB magic, tar members, recent success markers) and exits non-zero on problems; exporter/alerts should key off verified health signals.

## Monitoring Stack

Credentials are **required**. `docker compose` refuses to start without them. Populate `.env` first:

```bash
cp .env.example .env
$EDITOR .env          # GRAFANA_ADMIN_PASSWORD, POSTGRES_PASSWORD,
                      # REDIS_PASSWORD, POSTGRES_EXPORTER_DSN

docker compose -f docker-compose.monitoring.yml up -d
```

```text
# Default local access points (verify compose bindings on your host)
Grafana:      http://localhost:3002
Prometheus:   http://localhost:9090
Alertmanager: http://localhost:9093
Blackbox:     http://localhost:9115
Dashboard:    http://localhost:8081
```

> **Upgrading an existing deployment:** `POSTGRES_PASSWORD` only initializes a new `postgres-data` volume. To rotate an existing volume, use `ALTER USER ... PASSWORD ...` or recreate the volume (data loss).

### Alertmanager / notifications
Alertmanager config does not perform `${VAR}` substitution. Use the repo’s notification setup flow:

```bash
SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' \
  spectre run setup-notification-channels -- --test
# canonical action: spectre/actions/setup-notification-channels.sh
```

The script writes the webhook secret to `prometheus/alertmanager-secrets/slack_webhook_url` (mode `0600`, gitignored), restarts/waits for Alertmanager, and `--test` verifies delivery behavior. `Watchdog` acts as a dead-man’s-switch alert. See `prometheus/alertmanager-secrets/README.md`.

## Security

Vulnerability scanning runs in CI (Trivy/OPA workflows). Local helpers (canonical under `spectre/actions/security/`, legacy paths may forward):

```bash
# Examples (review sudo/mutates before running)
sudo spectre run security/run-security-hardening
spectre run security/scan-docker-images
spectre run security/scan-dependencies
sudo spectre run security/docker-security-hardening
spectre run security/api-security-hardening

# Policy audit (canonical)
opa check spectre/policies/
```

## Security Metrics from the Spectre Agent

`spectre run prometheus/security-metrics-exporter` (or the scheduled exporter path) publishes Spectre agent security findings as node-exporter textfile metrics. It is cron/timer-driven; nothing is published unless scheduled.

Configuration (environment): `SPECTRE_AGENT_URL` (default `http://127.0.0.1:8106`), `SPECTRE_API_KEY_FILE` (default `<repo>/.spectre-api-key`, mode `0600`), `SPECTRE_TIMEOUT`. The API is fail-closed (`X-API-Key` required).

The exporter verifies service identity before trusting responses (to distinguish “agent down” from “wrong service on port”). Key metrics/states include `spectre_agent_up`, `spectre_agent_up_reason`, and collision signaling (`SecurityAgentWrongServiceOnPort`). Finding counts are omitted (not zeroed) when the agent state is unknown/untrusted; `security_last_scan_timestamp` reflects the agent’s recorded scan time, not exporter poll time.

## Restic (adopted)

The adopted restic engine keeps existing backup producers and `check-backup-health.sh` intact. It is **local-first, tag-scoped** (`spectre-suite,workstation` by default behavior/config), and offsite failures are degraded (they must not block local backup success).

```bash
# Store secrets outside the repo
cp config/backups/restic/env.example "$HOME/.secrets/spectre-suite-backups.env"
chmod 600 "$HOME/.secrets/spectre-suite-backups.env"  # and password file
export RESTIC_CONFIG="$HOME/.secrets/spectre-suite-backups.env"

spectre run backups/restic/backup
spectre run backups/restic/verify
# direct action helpers (not registered as spectre jobs):
spectre/actions/backups/restic/prune.sh --dry-run --repo local   # tag-scoped forget+prune
spectre/actions/backups/restic/restore.sh --latest --target /tmp/restore --dry-run
```

Optional per-user timers (require configured `RESTIC_CONFIG`; do not interfere with `spectre-backup-catchup`):
- `spectre/actions/systemd/install-restic-timer.sh` (daily adopted backup)
- `spectre/actions/systemd/install-restic-verify-timer.sh` (weekly verify)

See `config/backups/restic/` (templates only). **Never commit passwords/keys/backend credentials.** Operational cutover/rollback details: `docs/migration/2026-11-06-absorb-spectre-backup.md`.

## Configuration & Portability

Scripts/actions generally use `set -euo pipefail` and support environment overrides where implemented. Common variables (verify per action): `PROJECTS_ROOT`, `PROJECTS_DIR`, `BACKUP_DIR`, `BACKUP_STATE_DIR`, `LOG_FILE`, `POSTGRES_CONTAINER`, `REDIS_CONTAINER`, `NEO4J_CONTAINER`, `PROMETHEUS_CONTAINER`, `ALERTMANAGER_CONTAINER`, `SECRETS_DIR`, `READY_TIMEOUT`, `TEST_TIMEOUT`, `SPECTRE_REPO_ROOT`, `RESTIC_CONFIG`.

**Secrets in backups:** `.env` files, secret directories, and credential material are intentionally excluded from relevant backup/config actions. Keep secrets outside the repo and use supported secret files (`.env`, Alertmanager secret files, restic password/config outside git).

## Project Structure (high level)

```text
spectre-suite/
├── spectre/                     # Python package (CLI, dispatch, agents, API/TUI/daemon, monitoring/deploy helpers)
│   ├── actions/                 # Canonical job implementations (dispatched by registry)
│   ├── dispatch/                # Registry, resolve, verify, run records/provenance
│   ├── monitoring/              # Prometheus/Grafana assets, exporters
│   └── ...
├── scripts/                     # Legacy Phase 1 forwarders/compatibility paths (C1 in progress); canonical implementations: spectre/actions/*
├── prometheus/                  # Monitoring config/rules/alertmanager assets (canonical exporter impls: spectre/monitoring/exporters/*, spectre/actions/prometheus/*)
├── grafana-dashboards/          # Dashboards/provisioning assets
├── config/                      # Config templates (including restic templates)
├── systemd/                     # Unit/timer helpers (legacy/repo paths; verify canonical usage)
├── docs/                        # Docs, runbooks, migration notes, superpowers specs/plans
├── tests/                       # Test suite (`bash tests/run_tests.sh`)
├── docker-compose.monitoring.yml
├── install.sh                   # §8.2-aligned root installer (installs /usr/local/bin/spectre only; review before use)
└── pyproject.toml
```

## Quick Commands (prefer `spectre run`)

```bash
# Dispatch / verification
spectre actions list
spectre actions verify
spectre run maintenance/system-health-check
spectre run backups/backup-all
spectre run backups/check-backup-health
spectre run backups/run-missed-backups

# Monitoring stack
docker compose -f docker-compose.monitoring.yml up -d
spectre run prometheus/business-metrics-exporter
spectre run check-config-consistency

# Maintenance / security (review sudo/mutates)
spectre run maintenance/vacuum-databases
spectre run maintenance/compliance-report
spectre run security/scan-docker-images
sudo spectre run security/run-security-hardening
```

Legacy `scripts/...` forwarders may still exist during C1 (Tier A top-level `prometheus/*-exporter.sh` forwarders removed); prefer `spectre run <job>` and canonical `spectre/actions/*` / `spectre/monitoring/exporters/*` / `spectre/policies/*` paths.

## Testing

```bash
bash tests/run_tests.sh
# Dispatcher/registry checks
python3 -c "from spectre.dispatch.verify import verify, read_host_inventory; print(verify(read_host_inventory()))"
```

## Documentation

| Document | Description |
|----------|-------------|
| `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` | Consolidation design/spec |
| `docs/migration/2026-11-06-phase2-3-repointing-runbook.md` | Phase 2/3 repointing status |
| `docs/migration/2026-11-06-phase4-c1-repo-inventory-plan.md` | Phase 4/C1 repo inventory plan (no deletions) |
| `docs/migration/2026-11-06-absorb-spectre-backup.md` | Restic absorption/cutover runbook |
| `docs/DISASTER_RECOVERY.md` | RTO/RPO and recovery procedures |
| `docs/RUNBOOKS.md` | Incident runbooks |
| `docs/TESTING_AND_CICD.md` | Test suite and CI/CD |
| `docs/ADVANCED_SECURITY_FEATURES.md` | IDS/IPS, threat detection notes |
| `docs/TROUBLESHOOTING.md` | Troubleshooting guide |

## License

MIT
