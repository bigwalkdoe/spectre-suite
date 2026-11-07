<p align="center">
  <img src="assets/spectre-suite-banner.svg" alt="Spectre Suite — Linux maintenance, backups, monitoring, and security automation" width="100%">
</p>

<h1 align="center">SPECTRE SUITE ☤</h1>

<p align="center">
  <strong>Linux system maintenance, backup, and monitoring automation — dispatched through one truthful CLI.</strong>
</p>

<p align="center">
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-22c55e?style=for-the-badge"></a>
  <a href="pyproject.toml"><img alt="Python 3.11+" src="https://img.shields.io/badge/Python-3.11%2B-3776AB?style=for-the-badge&logo=python&logoColor=white"></a>
  <a href="https://www.linux.org/"><img alt="Linux" src="https://img.shields.io/badge/Platform-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=111827"></a>
  <a href="docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md"><img alt="Dispatch: spectre run" src="https://img.shields.io/badge/Dispatch-spectre%20run-60a5fa?style=for-the-badge"></a>
  <a href="docs/TESTING_AND_CICD.md"><img alt="Ops Suite" src="https://img.shields.io/badge/Focus-Backups%20%7C%20Monitoring%20%7C%20Security-a78bfa?style=for-the-badge"></a>
</p>

<p align="center">
  <code>◆ backups/restic</code> · <code>◆ prometheus/grafana/alertmanager</code> · <code>◆ security &amp; maintenance actions</code> · <code>◆ registry + provenance</code>
</p>

---

## ▸ What Spectre Suite is

Spectre Suite is a consolidated Linux operations suite for **automated backups**, **restic snapshot workflows**, **monitoring/alerting** (Prometheus + Grafana + Alertmanager), **security/hardening helpers**, **maintenance jobs**, and **operational reporting**.

Instead of calling legacy scripts directly, scheduled and manual jobs run through the unified `spectre` dispatch surface:

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│  spectre run <job>  ──► registry resolve ──► action/exporter ──► provenance │
│  spectre actions verify  checks registry ↔ disk ↔ scheduler (truthful gate) │
└──────────────────────────────────────────────────────────────────────────────┘
```

> [!IMPORTANT]
> **Treat runtime truth as authoritative.** Do not assume a README claim, schedule, or host state is current — verify with `spectre actions list` / `spectre actions verify`, `crontab -l`, and `systemctl list-timers --all` (including `--user`).

---

## ✦ Feature map

| Area | What it covers |
|---|---|
| **Dispatch** | `spectre run <job>`, `spectre actions list/show/verify`; registry metadata (`sudo`, `mutates`, `timeout`, `schedule_hint`, `concurrency`) and run provenance. |
| **Backups** | Database, Docker volume, config, and project backups; replication, encryption/verification helpers; missed-backup catch-up; adopted **restic** engine with tag-scoped retention and degraded-offsite behavior. |
| **Monitoring** | Prometheus + Grafana + Alertmanager, Blackbox exporter, business/security textfile exporters, restic marker metrics, dashboards/provisioning. |
| **Security** | Fail2Ban/IDS-IPS helpers, Docker/API/network hardening actions, dependency/image scan helpers, OPA policies, Spectre agent security metrics with port/identity collision detection. |
| **Maintenance** | Cache/temp/download/resource cleanup, disk/performance checks, DB vacuum, system health, compliance/audit helpers. |
| **Network & performance** | VPN/network hardening/monitoring and optimization/right-sizing actions where implemented (review `sudo`/`mutates`). |
| **ML (optional)** | ML anomaly pipeline/actions where dependencies/config are present. |

<details>
<summary><strong>Not implemented in this repository</strong> (avoid assuming these exist)</summary>

Loki, Promtail, Wazuh, OWASP ZAP orchestration, SonarQube orchestration, Trivy wrapper script (Trivy runs in CI; run locally via container if needed), PgBouncer/read-replica/Vault deployment, k6/Locust harnesses, or a standalone AIDE scheduler/script beyond host-tool reporting.

</details>

---

## ◈ Visuals & screenshots

<p align="center">
  <img src="assets/monitoring-preview.svg" alt="Illustrative Spectre Suite monitoring preview" width="100%">
</p>

<table>
  <tr>
    <td align="center" width="33%">
      <strong>CLI surface</strong><br>
      <img src="assets/spectre-cli-help.png" alt="spectre --help terminal screenshot" width="100%">
    </td>
    <td align="center" width="33%">
      <strong>Action registry</strong><br>
      <img src="assets/spectre-actions-list.png" alt="spectre actions list terminal screenshot" width="100%">
    </td>
    <td align="center" width="34%">
      <strong>Truth gate</strong><br>
      <img src="assets/spectre-actions-verify.png" alt="spectre actions verify terminal screenshot" width="100%">
    </td>
  </tr>
</table>

```text
╭─ screenshot note ───────────────────────────────────────────────────────────╮
│ Terminal PNGs above are rendered locally from real command output.          │
│ Add redacted Grafana/Alertmanager/dashboard captures to assets/ for         │
│ full observability screenshots (see assets/README.md).                      │
╰─────────────────────────────────────────────────────────────────────────────╯
```

---

## ▸ Quick start

```bash
git clone https://github.com/bigwalkdoe/spectre-suite.git
cd spectre-suite

# Inspect available jobs and registry/host consistency
python3 -m spectre.cli.main actions list
python3 -m spectre.cli.main actions verify

# Run a job through the dispatcher
python3 -m spectre.cli.main run maintenance/system-health-check
python3 -m spectre.cli.main run backups/backup-all -- --help
```

If you have the package installed in an environment where `spectre` is on `PATH`, use `spectre ...` directly.

### Install / host integration notes

```text
╭─ caution ───────────────────────────────────────────────────────────────────╮
│ install.sh is root/host-mutating. Review before use.                        │
│ Prefer the installed `spectre` CLI and systemd timers that invoke          │
│ `spectre run <job>`. Consolidation intent: only `spectre` belongs in       │
│ /usr/local/bin (not arbitrary scripts).                                     │
╰─────────────────────────────────────────────────────────────────────────────╯
```

For sleep/resume-safe catch-up (checks health first; runs only when stale):

```bash
./spectre/actions/systemd/install-backup-catchup-timer.sh
```

---

## ▸ Unified dispatch model

```text
spectre/actions/<group>/<job>.sh          ← canonical job implementations
spectre/monitoring/exporters/*            ← canonical exporter implementations
spectre/policies/*                        ← OPA rego + baseline.json (real dir)
spectre/dispatch/registry_data.json        ← registry source of truth (with dispatch modules)
```

```bash
spectre actions list
spectre actions show backups/backup-all
spectre actions verify
spectre run backups/backup-all
```

**C1 complete:** no tracked legacy `scripts/` compatibility tree (`git ls-files scripts` = 0). Use `spectre run <job>` and canonical paths. CI guardrails block reintroducing tracked `scripts/` paths.

---

## ▸ Schedule reference (host-dependent)

Scheduled jobs should have **one scheduler path per job** and invoke `spectre run <job>`. Exact schedules vary by host — confirm with `crontab -l`, `systemctl list-timers --all`, `systemctl --user list-timers --all`, and `spectre actions verify`.

| Typical job | `spectre run` target | Notes |
|---|---|---|
| Database backup | `backups/backup-databases` | daily / as scheduled |
| Full backup | `backups/backup-all` | weekly / as scheduled |
| Backup health check | `backups/check-backup-health` | verifies archives/markers, not just logs |
| Missed-backup catch-up | `backups/run-missed-backups` | persistent timer; checks health before running |
| Adopted restic backup | `backups/restic/backup` | local-first, tag-scoped |
| Adopted restic verify | `backups/restic/verify` | scheduled verify |
| DB vacuum | `maintenance/vacuum-databases` | daily / as scheduled |
| Cleanup / performance | `maintenance/*`, `performance/*` | as configured |
| Metrics exporters | `prometheus/*-metrics-exporter` | cron/timer-driven textfile exporters |

> **Cron does not catch up after sleep.** Use persistent systemd timers for catch-up-sensitive jobs.
> **Health over logs:** exporters/alerts should key off verified health signals.

---

## ▸ Monitoring stack

Credentials are **required**. `docker compose` refuses to start without them.

```bash
cp .env.example .env
$EDITOR .env   # GRAFANA_ADMIN_PASSWORD, POSTGRES_PASSWORD, REDIS_PASSWORD, POSTGRES_EXPORTER_DSN

docker compose -f docker-compose.monitoring.yml up -d
```

```text
Default local access points (verify compose bindings on your host):
  Grafana      → http://localhost:3002
  Prometheus   → http://localhost:9090
  Alertmanager → http://localhost:9093
  Blackbox     → http://localhost:9115
  Dashboard    → http://localhost:8081
```

> **Upgrading an existing deployment:** `POSTGRES_PASSWORD` initializes a new `postgres-data` volume only. To rotate an existing volume, use `ALTER USER ... PASSWORD ...` or recreate the volume (data loss).

### Alertmanager notifications

Alertmanager config does not do `${VAR}` substitution. Use the notification setup flow (writes a gitignored secret file, mode `0600`):

```bash
SLACK_WEBHOOK_URL='https://hooks.slack.com/services/...' \
  spectre run setup-notification-channels -- --test
```

`Watchdog` acts as a dead-man’s-switch alert. See `prometheus/alertmanager-secrets/README.md`.

---

## ▸ Restic (adopted)

The adopted restic engine is **local-first, tag-scoped** and treats offsite failures as **degraded** (they must not block local backup success). Existing backup producers and `check-backup-health.sh` remain intact.

```bash
# Store secrets outside the repo
cp config/backups/restic/env.example "$HOME/.secrets/spectre-suite-backups.env"
chmod 600 "$HOME/.secrets/spectre-suite-backups.env"
export RESTIC_CONFIG="$HOME/.secrets/spectre-suite-backups.env"

spectre run backups/restic/backup
spectre run backups/restic/verify
```

Optional user timers: `spectre/actions/systemd/install-restic-timer.sh`, `spectre/actions/systemd/install-restic-verify-timer.sh`. **Never commit passwords/keys/backend credentials.** See `docs/migration/2026-11-06-absorb-spectre-backup.md`.

---

## ▸ Security & metrics notes

```bash
# Examples (review sudo/mutates before running)
spectre run security/scan-docker-images
spectre run security/scan-dependencies
sudo spectre run security/run-security-hardening
opa check spectre/policies/
```

`spectre run prometheus/security-metrics-exporter` (scheduled) publishes Spectre agent findings as node-exporter textfile metrics. Key signals include `spectre_agent_up` / `spectre_agent_up_reason`; finding counts are omitted (not zeroed) when agent state is unknown/untrusted. The agent API is fail-closed (`X-API-Key` required). Configure via `SPECTRE_AGENT_URL`, `SPECTRE_API_KEY_FILE` (default `<repo>/.spectre-api-key`, mode `0600`), `SPECTRE_TIMEOUT`.

---

## ◇ Project layout

```text
spectre-suite/
├── assets/                      # README visuals (banner, previews, screenshot placeholders)
├── spectre/
│   ├── actions/                 # Canonical dispatched job implementations
│   ├── dispatch/                # Registry, resolve, verify, run records/provenance
│   ├── monitoring/              # Prometheus/Grafana assets, exporters
│   ├── policies/                # OPA policies + baseline.json
│   └── cli/, agents/, ...       # Python package (CLI, services, API/TUI/daemon)
├── prometheus/                  # Monitoring config/rules/alertmanager assets
├── grafana-dashboards/          # Dashboards/provisioning assets
├── config/                      # Templates (including restic templates)
├── systemd/                     # Unit/timer helpers
├── docs/                        # Runbooks, migration notes, specs/plans
├── tests/                       # bash suite + agent tests
├── docker-compose.monitoring.yml
└── pyproject.toml
```

---

## ▸ Testing

```bash
bash tests/run_tests.sh

# Dispatcher/registry checks
python3 -c "from spectre.dispatch.verify import verify, read_host_inventory; print(verify(read_host_inventory()))"
```

---

## ▸ Documentation

| Document | Purpose |
|---|---|
| [`docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md`](docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md) | Consolidation design/spec |
| [`docs/migration/2026-11-06-phase2-3-repointing-runbook.md`](docs/migration/2026-11-06-phase2-3-repointing-runbook.md) | Phase 2/3 repointing status |
| [`docs/migration/2026-11-06-absorb-spectre-backup.md`](docs/migration/2026-11-06-absorb-spectre-backup.md) | Restic absorption/cutover runbook |
| [`docs/DISASTER_RECOVERY.md`](docs/DISASTER_RECOVERY.md) | RTO/RPO and recovery procedures |
| [`docs/RUNBOOKS.md`](docs/RUNBOOKS.md) | Incident runbooks |
| [`docs/TESTING_AND_CICD.md`](docs/TESTING_AND_CICD.md) | Test suite and CI/CD |
| [`docs/ADVANCED_SECURITY_FEATURES.md`](docs/ADVANCED_SECURITY_FEATURES.md) | IDS/IPS, threat detection notes |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Troubleshooting guide |

---

## ▸ License

MIT — see [`LICENSE`](LICENSE).

<p align="center">
  <sub>┄┄┄  spectre suite  ·  keep runtime truth authoritative  ·  <code>spectre actions verify</code>  ┄┄┄</sub>
</p>
