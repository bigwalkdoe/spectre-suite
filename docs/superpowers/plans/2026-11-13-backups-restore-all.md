# Backups/Restore All Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new scheduled job `backups/restore-all` that runs a full restore of every backup artifact (databases, Docker volumes, configuration, projects, off-site/remote) on a regular cadence, registered in the dispatch registry and wired to a systemd service + timer, so a single command `spectre run backups/restore-all` executes it.

**Architecture:** A new action script lives next to the other `backups/*` scripts; the script is invoked by the CLI dispatcher through the registry; a matching `systemd` service + timer gives it a persistent, oneshot run. The job replaces its crontab/user service entries in the registry ledger.

**Tech Stack:** Bash orchestration (existing style), paths relative to `spectre/` package root, `registry_data.json` declarative data, `hatchling` build, Python 3.11+, `fastapi`/`uvicorn` for API exposure (not part of this job).

## Spec
- Design spec: `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` (Section 5.5 Delegation, Section 6.1 Envelope, Section 7.5 Out of scope, Section 8.3 Forwarder shims).
- Test suite: `tests/run_tests.sh` (bash lint, python pytest); no dedicated pytest for shell scripts yet — verification via `spectre run -- --help` and manual execution.

## Global Constraints
- Project version: `0.3.0` (pyproject.toml).
- Python requires `>=3.11`.
- Dependencies pinned in `pyproject.toml`; do not introduce new runtime deps beyond what existing scripts use.
- Naming convention: `group/action-name.sh` under `spectre/actions/<group>/<action>.sh`.
- Registry keys required: `name`, `action`, `group`, `summary`; omitted keys fall back to `FIELD_DEFAULTS` (sudo=False, timeout=1800, mutates=False, concurrency="allow", schedule_hint=None, replaces=[]).
- Jobs with `mutates=true` must have `concurrency="forbid"`; read-only jobs `concurrency="allow"`.
- Every job must resolve to an executable inside the checkout (`Path(spectre.__file__).parent`).
- Silent skip is a bug class: missing files must cause non-zero exit.
- `schedule_hint` is a cron expression; `replaces` lists crontab + user service entries it supersedes.
- Do NOT commit credentials/secrets; use `$BACKUP_DIR`, `$LOG_FILE`, env vars only.

## Review Focus
1. **Job not in registry** → exit 2, suggest `spectre actions list`. (Covered by registry entry.)
2. **Registered but action file absent** → non-zero, names the path. (Script creation task.)
3. **Resolves outside the checkout** → hard error (path resolution guard in dispatcher).
4. **Exceeds `timeout`** → kill process group, report status.
5. **Non-zero exit** → record exit code, notify via logger/notify-send.
6. **Concurrent runs of `concurrency="forbid"`** → refuse, name holding PID/start time.
7. **SQLite busy** → WAL + `busy_timeout=5000` on connect (handled by run records).
8. **Missing success marker** (`last-backup-health`) → alert if never written.

---

## Tasks

### Task 1: Create `spectre/actions/backups/restore-all.sh`

**Files:**
- Create: `spectre/actions/backups/restore-all.sh`

**Interfaces:**
- Consumes: none external; uses environment variables `BACKUP_DIR`, `VOLUME_BACKUP_DIR`, `BACKUP_STATE_DIR`, `DRY_RUN`, `--purge-hollow`, `--dry-run`, `LOG_FILE`.
- Produces: executed restore actions (databases, docker volumes, configs, projects, remote, restic) and a summary report; writes verdict to `$BACKUP_STATE_DIR/last-backup-health`.

- [ ] **Step 1: Write the script**
  ```bash
  #!/bin/bash
  set -euo pipefail
  
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ...
  ```
  (body TBD)

- [ ] **Step 2: Syntax check**
  `bash -n spectre/actions/backups/restore-all.sh`
  Expected: PASS.

- [ ] **Step 3: Dry-run / sanity execution**
  `bash -x spectre/actions/backups/restore-all.sh` (or `--dry-run`)
  Expected: no fatal errors; prints "Backup orchestration completed: <date>".

- [ ] **Step 4: Run end-to-end (manual)**
  `spectre run backups/restore-all` (or `spectre actions show backups/restore-all`)
  Expected: exits 0 when all restores succeed; exits non-zero listing failures.

- [ ] **Step 5: Commit**
  ```bash
  git add spectre/actions/backups/restore-all.sh
  git commit -m "feat(backups): add restore-all orchestrator action"
  ```

### Task 2: Register the new job in `registry_data.json`

**File:** `spectre/dispatch/registry_data.json` (edit, insert new object after `backups/run-missed-backups` block, before `dashboard-actions/process-triggers`).

New entry:
```json
{
  "name": "backups/restore-all",
  "action": "backups/restore-all.sh",
  "group": "backups",
  "summary": "Full restore of all backup artifacts: databases, Docker volumes, configs, projects, remote, and off-site",
  "mutates": true,
  "concurrency": "forbid",
  "schedule_hint": "0 4 * * *",
  "replaces": [
    "crontab:0 4 * * *",
    "user:backups-restore-all.service"
  ]
}
```

- [ ] **Step 1: Insert entry** (preserve alphabetical order).
- [ ] **Step 2: Validate registry loads** (`python3 -c "from spectre.dispatch.registry import get_job('backups/restore-all')"`).
- [x] **Step 3: Commit**.

### Task 2: Complete.

**Files:**

**Files:**

**Files:**
- Create: `spectre/systemd/backups-restore-all.service`
- Create: `spectre/systemd/backups-restore-all.timer`

Service template (modeled on `backup.service`):
```ini
[Unit]
Description=Backups Restore All Service
After=network.target docker.service
[Service]
Type=oneshot
ExecStart=/usr/local/bin/spectre run backups/restore-all.sh
Environment=PATH=... 
```
Timer template (modeled on `backup.timer`):
```ini
[Unit]
Description=Scheduled Full Restore Timer
Requires=backups-restore-all.service
[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
[Install]
WantedBy=timers.target
```

- [x] **Step 1: Write `backups-restore-all.service`**.
- [x] **Step 2: Write `backups-restore-all.timer`** with `OnCalendar=*-*-* 04:00:00 Persistent=true`.
- [ ] **Step 3: Install into systemd** (`sudo cp ... /etc/systemd/system/`, `systemctl enable --now backups-restore-all.timer`).
- [ ] **Step 4: Verify** (`systemctl list-timers | grep restore-all`).

### Task 4: Wire cron entry (optional, via registry `replaces`)

The registry `replaces` field already points at crontab and user service entries. After Task 2, update the `schedule_hint` value accordingly; no separate crontab edit needed if `replaces` handles it.

### Task 5: Add a quick smoke test / CI gate (optional)

No new pytest needed; existing `tests/run_tests.sh` covers bash syntax. Ensure `spectre run backups/restore-all --help` works.

**Estimated effort:** ~4–5 hours total (script + registry + two systemd files + install).

---

## Execution Handoff

Plan saved to `docs/superpowers/plans/2026-11-13-backups-restore-all.md`. 

**Which execution approach would you prefer?**
- **Subagent-driven** – fresh subagent implements each task and a reviewer checks before proceeding (most thorough; costs a context per task).
- **Native** – I implement every task myself in this session, then a final reviewer checks the branch (cheapest/fastest; fine with a mid-tier model since the plan carries the design).

Given the interdependencies (script → registry → systemd service/timer), **subagent-driven** is recommended for quality assurance. Please confirm or tell me your preference.
