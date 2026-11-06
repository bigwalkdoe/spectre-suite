# Phase 2/3 — Scheduler Repointing Runbook

**Generated:** 2026-11-06 on `feat/consolidation-phase1-shims` @ Phase 1 complete (repo-side).  
**Updated:** 2026-11-06 (session follow-up) — reflects **host repointing completed**; reconciles with `spectre.dispatch.verify`.  
**Source of truth:** `spectre.dispatch.verify` (unified layout).

## Current state (verified)
- `spectre actions verify` (repo `PYTHONPATH`, host inventory via `read_host_inventory()`): **0 findings** (0 blocking, 0 advisory). No `legacy-path` / `unregistered` findings.
- **Crontab (14 entries):** all invoke `/usr/local/bin/spectre run <job>` (exporters, backups, maintenance, performance) — matches the original inventory targets.
- **Systemd units (repointed, observed):** `disk-space-check.service`, `performance-check.service`, `security-scan.service`, `spectre-backup-catchup.service` (user), `spectre-dashboard-actions.service` (user), `spectre-restic-backup.service` (user), `spectre-restic-verify.service` (user) all `ExecStart=/usr/local/bin/spectre run …`.
- **CLI:** `/usr/local/bin/spectre` is a wrapper to `~/.local/share/spectre-venv/bin/spectre`.
- **`/home/deon/scripts`:** absent (Phase 4 item satisfied on host).
- **`/usr/local/bin/cleanup-downloads.sh`:** absent.

## Original legacy-path inventory (historical, now repointed)
The 21-entry table below is the pre-repoint plan/inventory (kept for audit). All listed schedulers now dispatch via `spectre run` on the host (verify: 0 legacy-path).

| Scheduler | Former call (legacy path) | Target job | Schedule | Notes |
|---|---|---|---|---|
| crontab: `*/5 * * * *` | `prometheus/business-metrics-exporter.sh` | `prometheus/business-metrics-exporter` | */5 * * * * | exporter, forbid |
| crontab: `*/5 * * * *` | `prometheus/security-metrics-exporter.sh` | `prometheus/security-metrics-exporter` | */5 * * * * | exporter, forbid |
| crontab: `0 */4 * * *` | `scripts/performance/resource-rightsizing.sh` | `performance/resource-rightsizing` | 0 */4 * * * | |
| crontab: `0 1 * * *` | `scripts/backups/backup-databases.sh` | `backups/backup-databases` | 0 1 * * * | |
| crontab: `0 2 * * *` | `scripts/maintenance/cleanup-temp.sh` | `maintenance/cleanup-temp` | 0 2 * * * | |
| crontab: `0 2 * * 6` | `scripts/backups/backup-all.sh` | `backups/backup-all` | 0 2 * * 6 | |
| crontab: `0 3 * * *` | `scripts/backups/backup-docker-volumes.sh` | `backups/backup-docker-volumes` | 0 3 * * * | |
| crontab: `0 3 * * 0` | `scripts/maintenance/cleanup-downloads.sh` | `maintenance/cleanup-downloads` | 0 3 * * 0 | |
| crontab: `0 4 * * 0` | `scripts/maintenance/cleanup-unused-resources.sh` | `maintenance/cleanup-unused-resources` | 0 4 * * 0 | |
| crontab: `0 4 * * 1` | `scripts/maintenance/cleanup-cache.sh` | `maintenance/cleanup-cache` | 0 4 * * 1 | |
| crontab: `0 9 * * 1` | `scripts/performance/cloud-cost-tracker.sh` | `performance/cloud-cost-tracker` | 0 9 * * 1 | |
| crontab: `30 2 * * *` | `scripts/maintenance/vacuum-databases.sh` | `maintenance/vacuum-databases` | 30 2 * * * | |
| crontab: `40 4 * * *` | `scripts/backups/replicate-backups.sh` | `backups/replicate-backups` | 40 4 * * * | |
| crontab: `50 4 * * *` | `scripts/backups/check-backup-health.sh` | `backups/check-backup-health` | 50 4 * * * | |
| unit: `disk-space-check.service` | `scripts/maintenance/check-disk-space.sh` | `maintenance/check-disk-space` | (system timer) | repointed; confirm §2.5a scope |
| unit: `performance-check.service` | `scripts/performance/check-performance.sh` | `performance/check-performance` | (system timer) | repointed; confirm §2.5a scope |
| unit: `security-scan.service` | `scripts/security/run-security-hardening.sh` | `security/run-security-hardening` | (system timer) | repointed; timer active (next Sat 04:00) |
| unit: `spectre-backup-catchup.service` | `scripts/backups/run-missed-backups.sh` | `backups/run-missed-backups` | (timer/path) | repointed (user) |
| unit: `spectre-dashboard-actions.service` | `scripts/dashboard-actions/process-triggers.sh` | `dashboard-actions/process-triggers` | (path-triggered) | repointed (user) |
| unit: `spectre-restic-backup.service` | `scripts/backups/restic/backup.sh` | `backups/restic/backup` | (timer) | repointed (user) |
| unit: `spectre-restic-verify.service` | `scripts/backups/restic/verify.sh` | `backups/restic/verify` | (timer) | repointed (user) |

## Remaining items (require explicit confirmation before host changes)

### A — Stabilize host state
1. **`~/.config/systemd/user/spectre.service` and `spectre-api.service` (203/EXEC, old layout):** `ExecStart` uses missing `~/.config/spectre/venv/bin/python` and old module paths (`apps.daemon.main`, `uvicorn apps.api.main:app`). Consolidation §8.6 requires update to `spectre.daemon` / `spectre.api.main:app`. Working interpreter with `spectre` installed: `~/.local/share/spectre-venv/bin/python` (verified: `spectre.api.main.app` present). **Do not change without confirmation** (daemon path must not break cron; §12.2 flapping noted). Proposed fix (confirm): repoint both units to `~/.local/share/spectre-venv/bin/python -m spectre.daemon` and `… -m uvicorn spectre.api.main:app …`, `daemon-reload`, restart only if explicitly approved.
2. **SELinux / exec contexts:** prior `performance-check` failure showed legacy-path exec denied (before unit was repointed on disk). Repointed units now exec `/usr/local/bin/spectre`; confirm next timer runs succeed. If any legacy/forwarder paths remain and are executed, relabel per precondition: `sudo bash scripts/systemd/label-exec-context.sh` then `bash tests/run_tests.sh` — **root/host change, confirm**.
3. **Operational (not dispatch):** `disk-space-check.service` exits 2 when root fs critical (observed 93%) — expected script behavior; treat as capacity issue. `security-scan.timer` active, next trigger 2026-11-07 04:00 PKT (no recent run shown; confirm outcome).
4. **§2.5a:** confirm no unintended duplicate system/user runs for `performance-check`/`security-scan`/`disk-space-check`.

### C — Phase 4 (destructive/host + repo; explicit approval required)
Per spec: “Remove shims; delete `/home/deon/scripts`; archive the agent repo read-only”. 
- `/home/deon/scripts` already absent. 
- **Forwarder shims in repo:** no `transitional forwarder` / `exec spectre run` shim files found under `scripts/` or `prometheus/` (only spec text). `scripts/*` and `prometheus/*.sh` still exist as repo paths — determine whether any remain as legacy compatibility copies vs canonical sources before removal; schedulers no longer call legacy paths (verify clean).
- **Archive agent repo read-only:** `/home/deon/dev/github/spectre-agent` and mirror `~/.git-mirror/github_spectre-agent.git` exist — **do not archive/modify without explicit confirmation** (confirm no machine/process depends on it).

### B — Repo-side follow-up
- This runbook updated to reflect completed repointing and remaining A/C items (2026-11-06).
- Phase 5 still open: README truth pass, merged CI/doc-drift (README must not advertise capabilities absent from `actions list`).

## Per-entry procedure (reference; repointing complete)
1. `spectre actions show <job>` / verify resolves it.
2. Manual `spectre run <job>` (respect `sudo`/`mutates`/time) confirms success + provenance.
3. Repoint scheduler to `spectre run <job>` (**host change, confirm**). Reload (`daemon-reload` for units). Trigger safely.
4. `spectre actions verify` → 0 blocking, legacy-path advisories eliminated.

## Acceptance (Phase 2/3)
- **Met (host, current):** `spectre actions verify` → 0 blocking and 0 legacy-path advisories; schedulers dispatch via `spectre run`.
- **Open:** §8.6 agent/daemon unit module paths (A.1), any remaining SELinux/operational checks (A.2–A.4), Phase 4/5.
