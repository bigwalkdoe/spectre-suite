# Phase 2/3 — Scheduler Repointing Runbook

**Generated:** 2026-11-06 on `feat/consolidation-phase1-shims` @ Phase 1 complete (repo-side).  
**Updated:** 2026-11-06 (session follow-up) — host repointing completed; reconciles with `spectre.dispatch.verify`.  
**Updated:** 2026-11-09 — A1/B/C progress, `spectre-security-metrics` repointed+deduped, `spectre actions verify` clean (0 findings).  
**Source of truth:** `spectre.dispatch.verify` (unified layout).

## Current state (verified)
- `spectre actions verify` (repo `PYTHONPATH`, host inventory via `read_host_inventory()`): **0 findings** (0 blocking, 0 advisory). No `legacy-path` / `unregistered` findings (2026-11-09 recheck).
- **Crontab:** user crontab invokes `/usr/local/bin/spectre run <job>` for exporter/backup/maintenance/performance targets (including `prometheus/security-metrics-exporter`).
- **Systemd units (repointed, observed):** `disk-space-check.service`, `performance-check.service`, `security-scan.service`, `spectre-backup-catchup.service` (user), `spectre-dashboard-actions.service` (user), `spectre-restic-backup.service` (user), `spectre-restic-verify.service` (user) all `ExecStart=/usr/local/bin/spectre run …`. `~/.config/systemd/user/spectre-security-metrics.service` repointed to `spectre run prometheus/security-metrics-exporter -- ...` (2026-11-09); duplicate `spectre-security-metrics.timer` disabled/stopped (crontab kept).
- **CLI:** `/usr/local/bin/spectre` is a wrapper to `~/.local/share/spectre-venv/bin/spectre`.
- **`~//scripts`:** absent (Phase 4 item satisfied on host).
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
1. **`~/.config/systemd/user/spectre.service` and `spectre-api.service` (203/EXEC, old layout):** **Resolved on host (verified 2026-11-09).** Both units use `%h/.local/share/spectre-venv/bin/python -m spectre.daemon.main` / `… -m uvicorn spectre.api.main:app --host 127.0.0.1 --port 8106 --proxy-headers` and are **active (running)** (daemon health-checks and API 200 observed). No restart/change made in 2026-11-09 session (daemon path must not break cron; §12.2).
2. **SELinux / exec contexts:** repointed units exec `/usr/local/bin/spectre`; no legacy exec denial observed in 2026-11-09 checks. Confirm next timer runs succeed. If any legacy/forwarder path is still executed, relabel per precondition: `sudo bash scripts/systemd/label-exec-context.sh` then `bash tests/run_tests.sh` — **root/host change, confirm**.
3. **Operational (not dispatch):** `disk-space-check.service` exits 2 when root fs critical (observed 93% earlier; **82% on 2026-11-09**) — expected script behavior/capacity. `security-scan` last run **failed 2026-11-07 04:00:01 PKT** (`HOME` unbound under systemd + `set -u`); fix in repo `spectre/actions/security/run-security-hardening.sh` (`120e598`, 2026-11-07 10:23 +0500). Unit runs `spectre run security/run-security-hardening` (resolves to repo action); next timer **Sat 2026-11-14 04:00 PKT** should include fix (not manually triggered; `sudo true, mutates true`).
   - **A2/A3 recheck (2026-11-09):** `performance-check` succeeded repeatedly 01:00–06:00 PKT and `disk-space-check` succeeded 00:01:23 PKT via `spectre run` (no exec/AVC symptoms in journals); `actions verify` clean. **Manual `security-scan` validation (2026-11-09 09:06:34–09:06:38 PKT, option 2, `sudo systemctl start security-scan.service`):** `security/run-security-hardening` → **`success in 2075ms (exit 0)`**, `status=0/SUCCESS`; **no `HOME: unbound variable`** (HOME fix `120e598` confirmed). **Read-only readiness recheck (2026-11-09, `maintenance/check-security-scan-outcome`):** `security-scan.timer` next `Sat 2026-11-14 04:00:00 PKT` (last scheduled 2026-11-07 04:00 PKT); last service run remains the 2026-11-09 manual success (`ExecStart=/usr/local/bin/spectre run security/run-security-hardening`, `status=0/SUCCESS`); journal `2026-11-14 03:55–04:15` has no entries (expected); `actions verify` clean. **Still pending scheduled proof (time-gated):** verify the **2026-11-14 04:00 PKT** `security-scan.timer` run and record evidence with the same commands/helper.
4. **§2.5a:** **clean (2026-11-09).** `performance-check`/`security-scan`/`disk-space-check` present as **system** timers only (no `--user` duplicates). `security-metrics-exporter` duplicate scheduler resolved (user timer disabled; crontab kept).

### C — Phase 4 (destructive/host + repo; explicit approval required)
Per spec: “Remove shims; delete `~//scripts`; archive the agent repo read-only”. 
- `~//scripts` already absent. 
- **Forwarder shims in repo:** no `transitional forwarder` / `exec spectre run` shim files found under `scripts/` or `prometheus/` (only spec text). No tracked `scripts/` tree and no tracked `prometheus/*.sh` found in repo; `spectre actions verify` clean (2026-11-09) — no obvious safe legacy-compatibility removals identified. Determine carefully before any removal; schedulers no longer call legacy paths.
- **Archive agent repo read-only (progress 2026-11-09, explicit approval):** dependency check found no active scheduler/service/process dependents. `spectre-agent` marker committed (`fe65acc`, local, not pushed); mirror `~/.git-mirror/github_spectre-agent.git` origin repointed to `git@github.com:bigwalkdoe/spectre-agent.git`; working copy moved to `~//archive/archived-repos/spectre-agent-20261109` (best-effort `a-w`); user applied `chattr -R +i` (top-level immutable; symlinks reported unsupported).
- **Read-only execution/evidence (2026-11-09, no destructive actions):** `spectre actions verify` → no findings; `~//scripts` absent; `git ls-files scripts`/`prometheus/*.sh` = 0; `~//archive/archived-repos/spectre-agent-20261109` present; no `~//scripts` references found under `/usr/local/bin` on this host. Crontab/timers observed dispatching via `spectre run` (one stale crontab *comment* mentions `~//scripts` — not an active scheduler reference). **Remaining (needs explicit approval/ops coordination before host changes):** exporter/timer install provenance not verified; any stale legacy host artifacts outside verified paths; full per-host “no path outside the repo is referenced” acceptance per Phase 4 host checklist. No deletions, unit edits, archive mutations, or host filesystem changes performed.

### B — Repo-side follow-up
- Phase 5 README truth pass / doc-drift vs `actions list` completed in `de247a3` (pushed, CI green, 2026-11-09): removed inaccurate Fail2Ban claim, clarified Wazuh/status-check nuance, removed stale Trivy-wrapper/AIDE-not-implemented claims; `check-docs-references.sh`/config checks OK. Keep README from advertising capabilities absent from `actions list`.

## Per-entry procedure (reference; repointing complete)
1. `spectre actions show <job>` / verify resolves it.
2. Manual `spectre run <job>` (respect `sudo`/`mutates`/time) confirms success + provenance.
3. Repoint scheduler to `spectre run <job>` (**host change, confirm**). Reload (`daemon-reload` for units). Trigger safely.
4. `spectre actions verify` → 0 blocking, legacy-path advisories eliminated.

## Acceptance (Phase 2/3)
- **Met (host, current):** `spectre actions verify` → 0 blocking and 0 legacy-path advisories; schedulers dispatch via `spectre run` (rechecked 2026-11-09; `security-metrics-exporter` repointed+deduped). §8.6 agent/daemon user unit module paths/interpreter resolved on host (A.1, 2026-11-09). §2.5a clean for targeted jobs (A.4).
- **Open/ongoing:** A.2 SELinux/next timer-run confirmation as needed; A.3 operational follow-up (`security-scan` next scheduled 2026-11-14 04:00 PKT should include HOME fix `120e598`; disk capacity). B/Phase 5 README truth pass done (`de247a3`, 2026-11-09) — keep docs aligned to `actions list`. C/Phase 4: `spectre-agent` archived/moved (2026-11-09, approved); continue any remaining destructive/repo cleanup only with explicit approval.
