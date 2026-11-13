# Automation Hardening for Self-Maintenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe, scheduled self-maintenance for backups (automatic restic/local trimming to reclaim space) and security posture (every-15-minute lightweight scan with safe, idempotent remediation).

**Architecture:** Extend the existing restic backup engine with configurable, tag-scoped prune scheduling and add a conservative local backup-artifact trim action/timer. Add a new lightweight security posture maintenance action + 15-minute timer that refreshes posture signals/status and applies only safe, idempotent fixes. Wire actions into `spectre/dispatch/registry_data.json` and repo-managed systemd/install patterns consistent with existing timers.

**Tech Stack:** Bash scripts under `spectre/actions/`, systemd service/timer units/installers, `spectre/dispatch/registry_data.json`, shell-based tests in `tests/`, existing restic/common helpers and Prometheus textfile/security exporters.

**Spec:** `docs/superpowers/specs/2026-11-11-automation-hardening-self-maintenance-design.md`

## Global Constraints

- Restic operations must remain **tag-scoped** (`--tag ${RESTIC_TAG:-spectre-suite}`); never perform unscoped `forget`/prune.
- Backup trimming must be conservative: no deletion of restic repo internals via filesystem ops, no size-only deletion that can remove valid small backups, and no deletion outside configured/owned paths and retention bounds.
- Security posture automation runs every **15 minutes** as a lightweight cycle; self-remediation is **safe and idempotent by default** (ensure dirs/state, clean known-stale temp artifacts, refresh exports/markers only). No service/container restarts, no firewall/SELinux/AppArmor/network changes, no package install/remove, no broad config rewrites, and no risky/destructive actions unless explicitly added later behind opt-in.
- Preserve existing behavior/contracts unless intentionally and safely extended (backup/verify/catchup flows, marker semantics, existing exporters/timers).
- Follow repo conventions: canonical actions in `spectre/actions/`, dispatchable via `spectre run` with registry entries, repo-managed systemd/install patterns similar to existing restic/baseline timers.

## Review Focus

- **Unscoped or over-broad deletion:** restic prune must stay tag-scoped; local trim must only touch known Spectre-owned artifact/state paths/patterns and respect retention/safety minimums.
- **Valid small backups deleted:** hollow/unusable detection must be structural/content-aware (not raw size thresholds) so legitimate small archives/dumps are preserved.
- **Overly aggressive 15-minute remediation:** posture maintenance must not restart services, mutate security/network/system configs, or run heavy scans; only safe idempotent fixes and status refresh.
- **Timer/schedule wiring mistakes:** prune/local-trim/posture timers must run intended commands on intended cadence (`Persistent=true`, jitter as appropriate) without breaking existing timers or requiring GUI/session-only assumptions.
- **Silent failure:** trim/prune/posture failures must be observable (non-zero exit and/or logs/markers) rather than quietly skipping space reclamation or stale posture reporting.

---

### Task 1: Make restic retention configurable (backward-compatible)

**Files:**
- Modify: `spectre/actions/backups/restic/common.sh`
- Modify: `config/backups/restic/env.example`
- Test: `tests/test_restic_retention_config.sh` (create)

**Interfaces:**
- Consumes: existing env loading in restic scripts; `RESTIC_TAG` default behavior.
- Produces: `restic_forget_args` emits tag-scoped forget args using env-overridable keep values with defaults `RESTIC_KEEP_HOURLY=24`, `RESTIC_KEEP_DAILY=30`, `RESTIC_KEEP_WEEKLY=12`, `RESTIC_KEEP_MONTHLY=12`, `RESTIC_KEEP_LAST=1`.

- [x] **Step 1: Write the failing test**

Create `tests/test_restic_retention_config.sh` that sources `spectre/actions/backups/restic/common.sh` in a temp shell context and asserts:
- Default `restic_forget_args` contains `--tag spectre-suite --keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1`.
- With env overrides (e.g. `RESTIC_TAG=mytag RESTIC_KEEP_DAILY=14 RESTIC_KEEP_WEEKLY=8`) output contains overridden values and `--tag mytag` (still tag-scoped).

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_restic_retention_config.sh`
Expected: FAIL because `restic_forget_args` currently ignores env keep overrides (and/or tag override expectations not met as specified).

- [x] **Step 3: Implement configurable retention in `common.sh` and document in env example**

Update `restic_forget_args` in `spectre/actions/backups/restic/common.sh` to read keep values from env with the existing defaults; keep output tag-scoped. Update `config/backups/restic/env.example` with commented optional retention knobs/defaults and note that pruning reclaims space.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_restic_retention_config.sh`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add spectre/actions/backups/restic/common.sh config/backups/restic/env.example tests/test_restic_retention_config.sh
git commit -m "Make restic retention configurable with safe defaults"
```

### Task 2: Add scheduled restic prune automation (tag-scoped)

**Files:**
- Create: `spectre/actions/systemd/install-restic-prune-timer.sh`
- Create: `systemd/spectre-restic-prune.service` (repo-managed example/unit, consistent with repo patterns)
- Create: `systemd/spectre-restic-prune.timer`
- Modify: `spectre/dispatch/registry_data.json` (prune schedule hint/replaces as appropriate)
- Test: `tests/test_restic_prune_timer_units.sh` (create)

**Interfaces:**
- Consumes: `spectre run backups/restic/prune` (`spectre/actions/backups/restic/prune.sh`), existing restic config env (`RESTIC_CONFIG` default `~/.secrets/spectre-suite-backups.env`).
- Produces: user/systemd automation to run tag-scoped prune daily (default **05:30:00**, `Persistent=true`, randomized delay) to reclaim space; installer supports `--print` and `--uninstall` like existing restic timer installers.

- [x] **Step 1: Write the failing test**

Create `tests/test_restic_prune_timer_units.sh` that asserts:
- `spectre/actions/systemd/install-restic-prune-timer.sh --print` outputs service/timer units referencing `spectre run backups/restic/prune`, includes `OnCalendar` (default daily) and `Persistent=true`.
- Repo `systemd/spectre-restic-prune.timer` and `.service` exist and contain expected cadence/ExecStart intent (tag-scoped prune via canonical action/entrypoint).

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_restic_prune_timer_units.sh`
Expected: FAIL because installer/units do not yet exist.

- [x] **Step 3: Implement prune timer installer and unit files; update registry metadata**

Create installer script modeled on `install-restic-timer.sh`/`install-restic-verify-timer.sh` but targeting `backups/restic/prune` and daily prune schedule (configurable via env/arg consistent with pattern). Add repo `systemd/spectre-restic-prune.service` and `.timer` (daily, persistent, jitter). Update `backups/restic/prune` registry entry `schedule_hint`/notes as appropriate without changing mutates/concurrency safety.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_restic_prune_timer_units.sh`
Expected: PASS.

Run: `bash -n spectre/actions/systemd/install-restic-prune-timer.sh`
Expected: no syntax errors.

- [x] **Step 5: Commit**

```bash
git add spectre/actions/systemd/install-restic-prune-timer.sh systemd/spectre-restic-prune.service systemd/spectre-restic-prune.timer spectre/dispatch/registry_data.json tests/test_restic_prune_timer_units.sh
git commit -m "Add scheduled tag-scoped restic prune automation"
```

### Task 3: Implement conservative local backup artifact trimming

**Files:**
- Create: `spectre/actions/backups/trim-backup-artifacts.sh`
- Test: `tests/test_trim_backup_artifacts.sh` (create)

**Interfaces:**
- Consumes: env/flags for paths and retention, e.g. `BACKUP_ARTIFACT_DIRS` or `BACKUP_DB_DIR`/`BACKUP_VOLUME_DIR` (defaults `/backups/databases`, `/backups/docker-volumes`), `BACKUP_ARTIFACT_RETENTION_DAYS` (default 30), `BACKUP_TRIM_STATE_DIR`/dumps path; `--dry-run`.
- Produces: safe trimming action that (a) removes structurally hollow/unusable archives in owned Spectre backup patterns, (b) removes old valid timestamped backup artifacts beyond retention in configured dirs, (c) cleans stale dump temp dirs beyond a safe age; prints actions, exits non-zero on operational errors.

- [x] **Step 1: Write the failing test**

Create `tests/test_trim_backup_artifacts.sh` using temp fixture dirs (like `tests/test_backup_health.sh`) to assert:
- `--dry-run` reports but does not delete candidates.
- Hollow/unusable archives matching owned patterns are removed (or reported in dry-run) while a valid small backup (e.g. valid small `*.sql.gz` with PostgreSQL dump header / valid RDB magic as applicable) is preserved.
- Valid old artifacts beyond retention are removed and recent ones kept.
- Files outside configured dirs/patterns are untouched.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_trim_backup_artifacts.sh`
Expected: FAIL because `spectre/actions/backups/trim-backup-artifacts.sh` does not exist.

- [x] **Step 3: Implement `trim-backup-artifacts.sh`**

Implement a conservative bash script with argument/env parsing, dry-run mode, structural validation helpers for owned archive types/patterns (aligned with backup health semantics), age-based retention trimming for Spectre-owned timestamped artifacts, and safe stale dump-dir cleanup. Do not delete outside allowed dirs/patterns; log summary counts.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_trim_backup_artifacts.sh`
Expected: PASS.

Run: `bash -n spectre/actions/backups/trim-backup-artifacts.sh`
Expected: no syntax errors.

- [x] **Step 5: Commit**

```bash
git add spectre/actions/backups/trim-backup-artifacts.sh tests/test_trim_backup_artifacts.sh
git commit -m "Add conservative local backup artifact trimming action"
```

### Task 4: Schedule local backup trimming and register action

**Files:**
- Create: `spectre/actions/systemd/install-backup-trim-timer.sh`
- Create: `systemd/backup-trim.service`
- Create: `systemd/backup-trim.timer`
- Modify: `spectre/dispatch/registry_data.json`
- Test: `tests/test_backup_trim_timer_units.sh` (create)

**Interfaces:**
- Consumes: `spectre run backups/trim-backup-artifacts` (canonical path/name as registered).
- Produces: daily automated trimming (default **05:45:00**, `Persistent=true`, jitter) via installer and/or repo-managed units; registry entry for `backups/trim-backup-artifacts` (mutating, bounded concurrency).

- [x] **Step 1: Write the failing test**

Create `tests/test_backup_trim_timer_units.sh` asserting installer `--print` and repo unit files reference `backups/trim-backup-artifacts`, daily cadence, and `Persistent=true`.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_backup_trim_timer_units.sh`
Expected: FAIL (missing files/entries).

- [x] **Step 3: Implement installer, units, and registry entry**

Add installer following existing timer-installer patterns, create repo `systemd/backup-trim.service`/`.timer`, and register `backups/trim-backup-artifacts` in `spectre/dispatch/registry_data.json` with accurate summary, `mutates`, `concurrency`, and schedule hint.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_backup_trim_timer_units.sh`
Expected: PASS.

Run: `bash -n spectre/actions/systemd/install-backup-trim-timer.sh`
Expected: no syntax errors.

- [x] **Step 5: Commit**

```bash
git add spectre/actions/systemd/install-backup-trim-timer.sh systemd/backup-trim.service systemd/backup-trim.timer spectre/dispatch/registry_data.json tests/test_backup_trim_timer_units.sh
git commit -m "Schedule and register local backup artifact trimming"
```

### Task 5: Implement security posture maintenance (15-min scan + safe remediation)

**Files:**
- Create: `spectre/actions/security/security-posture-maintenance.sh`
- Test: `tests/test_security_posture_maintenance.sh` (create)

**Interfaces:**
- Consumes: optional flags/env `--check-only`/`--dry-run`, state dir (default under `${XDG_STATE_HOME:-$HOME/.local/state}/spectre-suite/security-posture`), ability to invoke available lightweight posture exporters/checks (e.g. `spectre run prometheus/security-baseline-metrics-exporter` and/or `prometheus/security-metrics-exporter` when present).
- Produces: lightweight posture scan/refresh that writes status summary/markers (timestamp, checks run, remediation actions/skipped, overall result) and performs only safe idempotent remediations by default (ensure required dirs, remove known-stale temp files in its own/state-managed temp areas older than threshold, refresh idempotent exports/markers). Exits non-zero on failure; never performs risky actions.

- [x] **Step 1: Write the failing test**

Create `tests/test_security_posture_maintenance.sh` that runs the script in a temp `HOME`/`XDG_STATE_HOME` with PATH-stubbed `spectre`/exporter commands as needed to assert:
- Creates/updates status marker/summary in state dir and exits 0 on successful lightweight run.
- `--dry-run`/`--check-only` does not apply filesystem cleanup/remediation side effects (only reports).
- Safe remediation creates expected state dirs and removes only stale temp files in the managed posture temp area (not arbitrary files) when applicable.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_security_posture_maintenance.sh`
Expected: FAIL because script does not exist.

- [x] **Step 3: Implement `security-posture-maintenance.sh`**

Implement the maintenance script: parse flags, set up state/log dirs, run lightweight posture refresh/check steps with graceful handling when optional components are unavailable, apply safe idempotent remediations (bounded to its managed dirs/state and exporter refresh), emit clear summary/logs and markers, and return appropriate exit code.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_security_posture_maintenance.sh`
Expected: PASS.

Run: `bash -n spectre/actions/security/security-posture-maintenance.sh`
Expected: no syntax errors.

- [x] **Step 5: Commit**

```bash
git add spectre/actions/security/security-posture-maintenance.sh tests/test_security_posture_maintenance.sh
git commit -m "Add 15-minute security posture maintenance action with safe remediation"
```

### Task 6: Schedule and register 15-minute security posture maintenance

**Files:**
- Create: `spectre/actions/systemd/install-security-posture-maintenance-timer.sh`
- Create: `systemd/security-posture-maintenance.service`
- Create: `systemd/security-posture-maintenance.timer`
- Modify: `spectre/dispatch/registry_data.json`
- Test: `tests/test_security_posture_timer_units.sh` (create)

**Interfaces:**
- Consumes: `spectre run security/security-posture-maintenance`.
- Produces: every-15-minute automation (`OnCalendar=*:0/15` or equivalent, `Persistent=true`, jitter) via installer and repo-managed units; registry entry for the posture maintenance action.

- [x] **Step 1: Write the failing test**

Create `tests/test_security_posture_timer_units.sh` asserting installer `--print` and repo unit files run `security/security-posture-maintenance` every 15 minutes with `Persistent=true`.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_security_posture_timer_units.sh`
Expected: FAIL (missing files/entries).

- [x] **Step 3: Implement installer, units, and registry entry**

Add installer, `systemd/security-posture-maintenance.service` and `.timer` (15-minute cadence, persistent, jitter), and register `security/security-posture-maintenance` in `spectre/dispatch/registry_data.json` with correct group/summary/mutates/concurrency/schedule hint.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_security_posture_timer_units.sh`
Expected: PASS.

Run: `bash -n spectre/actions/systemd/install-security-posture-maintenance-timer.sh`
Expected: no syntax errors.

- [x] **Step 5: Commit**

```bash
git add spectre/actions/systemd/install-security-posture-maintenance-timer.sh systemd/security-posture-maintenance.service systemd/security-posture-maintenance.timer spectre/dispatch/registry_data.json tests/test_security_posture_timer_units.sh
git commit -m "Schedule and register 15-minute security posture maintenance"
```

### Task 7: Documentation and end-to-end verification

**Files:**
- Modify: `docs/RUNBOOKS.md` and/or relevant backup/security docs as appropriate
- Modify: `README.md` or dispatch/help docs only if needed for discoverability
- Test: existing/new tests and CLI checks

**Interfaces:**
- Consumes: implemented actions, timers, registry entries.
- Produces: operator-facing docs describing automated restic/local trimming and 15-minute safe posture maintenance (cadence, how to dry-run/disable, safety boundaries) and passing verification checks.

- [x] **Step 1: Write/update verification checks (failing if docs/registration incomplete)**

Add or run targeted checks that will fail until docs/registration are complete (e.g. grep/assert new action names/timers documented and present in registry; extend existing docs/reference checks if the repo uses them).

- [x] **Step 2: Run checks to verify failures/gaps**

Run the chosen doc/registry verification commands.
Expected: FAIL or show gaps before updates.

- [x] **Step 3: Update documentation and any final registry/help alignment**

Document: restic prune timer + configurable retention, local backup artifact trimming action/timer and retention defaults, security posture maintenance 15-min scan and safe-remediation boundaries, and dry-run/check-only/disable guidance.

- [x] **Step 4: Run full relevant verification**

Run: `bash tests/test_restic_retention_config.sh && bash tests/test_restic_prune_timer_units.sh && bash tests/test_trim_backup_artifacts.sh && bash tests/test_backup_trim_timer_units.sh && bash tests/test_security_posture_maintenance.sh && bash tests/test_security_posture_timer_units.sh`
Expected: all PASS.

Run: `python3 -m spectre.cli.main actions verify` (or repo’s equivalent dispatch/verify command if available) and any existing relevant tests.
Expected: no blocking issues introduced.

- [x] **Step 5: Commit**

```bash
git add docs/RUNBOOKS.md README.md spectre/dispatch/registry_data.json docs/superpowers/specs/2026-11-11-automation-hardening-self-maintenance-design.md docs/superpowers/plans/2026-11-11-automation-hardening-self-maintenance.md
git commit -m "Document and verify self-maintenance automation hardening"
```

## Execution Handoff

After saving and self-reviewing the plan, ask for review and preferred execution method if not already specified. **Recommendation:** **Subagent-driven** for this multi-task change spanning backup, security, systemd, and registry/docs (several independent but safety-sensitive units benefit from per-task review gates); choose **Native** if you prefer lower overhead in-session execution.
