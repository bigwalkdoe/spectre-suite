# Backups/Restore All Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dispatchable `backups/restore-all` operator job that orchestrates a disaster-recovery restore of every backup artifact — PostgreSQL databases, Docker volumes, and a restic snapshot — from local or off-site sources. It is **operator-only**: it defaults to `--dry-run`, only mutates with `--execute --yes`, and is **not scheduled**.

**Why not a timer:** the existing restore actions restore *in place* — `restore-databases.sh` pipes a dump into the live database, `restore-docker-volumes.sh` stops services and overwrites the live named volume. A recurring in-place restore would replace live data with the latest backup on every fire. A restore is a deliberate disaster-recovery action, not a maintenance cadence.

**Architecture:** A new Bash action beside the other `backups/*` scripts. It resolves its sibling restore scripts through `RESTORE_ACTION_DIR` (default: its own directory) so it is testable and so a missing component is a hard error rather than a silent skip. It writes a verdict to `$BACKUP_STATE_DIR/last-restore-health` (not `last-backup-health`, which belongs to the backup health exporter).

**Tech Stack:** Bash orchestration (existing style), `registry_data.json` declarative data, Python 3.11+, existing `spectre run` dispatcher. No new runtime dependencies.

## Spec

- Plan-authority spec: `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` (Sections 5.5 Delegation, 6.1 Envelope, 7.5 Out of scope, 8.3 Forwarder shims).
- Test convention: `tests/run_tests.sh` shell suites; new suite `tests/test_restore_all.sh` uses stub sibling scripts in a temp dir and never touches real backup paths.

## Global Constraints

- Project version: `0.3.0` (`pyproject.toml`); Python requires `>=3.11`.
- Naming convention: `group/action-name.sh` under `spectre/actions/<group>/<action>.sh`; registry `name` must equal `action` without `.sh`.
- `mutates=true` jobs must use `concurrency="forbid"`.
- Missing component scripts must exit non-zero and name the path (silent skip is a bug class).
- No credentials in the script or repo; use `$BACKUP_DIR`, `$VOLUME_BACKUP_DIR`, `$BACKUP_STATE_DIR`, `$LOG_FILE`.
- Restores are destructive: dry-run is the default, `--execute` requires `--yes`, and the job has no timer.

## Review Focus

1. **Nothing scheduled** — registry `schedule_hint` is `null`; `systemd/backups-restore-all.{service,timer}` are removed.
2. **Dry-run mutates nothing** — no sibling restore script runs, no marker is written, exit 0.
3. **Execute is explicit** — `--execute` without `--yes` exits 2 and runs nothing.
4. **Missing component script** — non-zero exit naming the absolute path.
5. **Partial failure** — remaining components still run; exit 1; verdict records the failure.
6. **No accidental in-place restic restore** — `--restic` with `--execute` requires `--restic-target`.
7. **Remote is opt-in** — `--remote` with `--execute` requires both a source and a location.
8. **Unknown flag / usage error** — exit 2 with usage text.

---

## Tasks

### Task 1: Implement `spectre/actions/backups/restore-all.sh`

**Files:**
- Create/Replace: `spectre/actions/backups/restore-all.sh`
- Create: `tests/test_restore_all.sh`
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: `RESTORE_ACTION_DIR` (default script dir), `BACKUP_DIR`, `VOLUME_BACKUP_DIR`, `BACKUP_STATE_DIR`, `LOG_FILE`; sibling scripts `restore-databases.sh`, `restore-docker-volumes.sh`, `restic/restore.sh`, `restore-from-remote.sh`.
- Produces: a human-readable plan (dry-run) or executed restores plus a summary; writes `$BACKUP_STATE_DIR/last-restore-health` as `ok <epoch>` or `failed <epoch> <detail>` on `--execute` only.

**CLI:**
```
restore-all.sh [--dry-run] [--execute --yes] [--all]
               [--databases [--database NAME]]
               [--volumes]
               [--restic [--snapshot ID] [--restic-target DIR]]
               [--remote --remote-source rsync|s3|b2
                         [--remote-type databases|docker-volumes|configurations]
                         --remote-location SERVER|BUCKET]
```

- [ ] **Step 1: Write the failing test** — `tests/test_restore_all.sh`. Stub sibling scripts in a temp `RESTORE_ACTION_DIR`; assert dry-run runs nothing, `--execute` without `--yes` exits 2, `--execute --yes --databases --volumes` calls both stubs and writes `ok`, a failing stub yields exit 1 and `failed`, a missing stub yields non-zero naming the path, restic without `--restic-target` exits 2, restic with a target passes the expected args, and unknown flags exit 2.
- [ ] **Step 2: Run test to verify it fails** — `bash tests/test_restore_all.sh`; expect failures because the current script is a backup-all copy with no flags.
- [ ] **Step 3: Implement the script** — parse flags strictly, default `DRY_RUN=1`, refuse `--execute` without `--yes`, resolve/validate every selected component before running any, run components capturing status, print a summary, write the verdict marker only on execute, notify via logger/notify-send on failure.
- [ ] **Step 4: Run test to verify it passes** — `bash tests/test_restore_all.sh`, `bash -n spectre/actions/backups/restore-all.sh`; both PASS.
- [ ] **Step 5: Wire the test and commit** — add `test_restore_all.sh` to `tests/run_tests.sh`; commit.

### Task 2: Make the registry entry operator-only

**File:** `spectre/dispatch/registry_data.json`

- [ ] **Step 1: Update the entry** — keep `name`/`action`/`group`, replace the summary with the DR wording, keep `mutates: true` and `concurrency: "forbid"`, set `schedule_hint: null`, and set `replaces` to the retired units `unit:backups-restore-all.service` and `unit:backups-restore-all.timer`.
- [ ] **Step 2: Validate** — `python3 -c "from spectre.dispatch.registry import get_job; j=get_job('backups/restore-all'); assert j.schedule_hint is None and j.mutates and j.concurrency=='forbid'"`.
- [ ] **Step 3: Commit**.

### Task 3: Retire the scheduler units

**Files:**
- Delete: `systemd/backups-restore-all.service`
- Delete: `systemd/backups-restore-all.timer`

- [ ] **Step 1: Delete the unit files** (`git rm`).
- [ ] **Step 2: Confirm nothing references them** — `grep -rn 'backups-restore-all' --exclude-dir=.git .` only finds the plan/ledger/registry hardware-retirement entries.
- [ ] **Step 3: Commit**.

### Task 4: Smoke test / CI gate

- [ ] **Step 1: CLI visibility** — `python3 -m spectre.cli.main actions show backups/restore-all` shows `schedule: manual`.
- [ ] **Step 2: Help path** — `python3 -m spectre.cli.main run backups/restore-all -- --help` exits 0 and prints the usage block.
- [ ] **Step 3: Dry-run path** — `python3 -m spectre.cli.main run backups/restore-all` exits 0 and prints `DRY RUN` (no live data touched).
- [ ] **Step 4: Full related suite** — `bash tests/run_tests.sh` (or the subset named in the ledger).

## Operator follow-up (requires root; not performed by the agent)

The crashed session installed and enabled the units on this host. Disable and remove them before the next 04:00 fire:

```bash
sudo systemctl disable --now backups-restore-all.timer
sudo rm -f /etc/systemd/system/backups-restore-all.timer /etc/systemd/system/backups-restore-all.service
sudo systemctl daemon-reload
systemctl list-timers --all | grep restore-all || echo "restore-all timer removed"
```
