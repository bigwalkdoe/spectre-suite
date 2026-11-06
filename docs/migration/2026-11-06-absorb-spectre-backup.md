# Migration: absorb spectre-backup into spectre-suite

**Date:** 2026-11-06  
**Spec:** `docs/superpowers/specs/2026-11-06-absorb-spectre-backup-design.md`  
**Plan:** `docs/superpowers/plans/2026-11-06-absorb-spectre-backup.md`  
**Status:** Code landed (Tasks 1–8). **Task 9 cutover/rehearsal is operator-only and must not be run without explicit human confirmation on this host.** Do not archive the spectre-backup repo, delete old configs/units/scripts, or delete `~/archive/backups` until §8.1 + seven consecutive green days are satisfied and no machine needs the server role.

## Goal

Make spectre-suite the single owner of workstation restic backups by adopting the proven spectre-backup engine, absorbing the home-backup scope, keeping the existing `/backups/spectre-backup` repo/password/Drive remote, and retiring standalone installs only after a verified cutover.

## Baseline (record before any live mutation)

```bash
restic snapshots --repo /backups/spectre-backup
restic snapshots --repo rclone:spectre-backup:
systemctl --user list-timers --all | grep -E 'backup|restic|spectre'
sha256sum ~/.config/spectre-backup/.env ~/.config/spectre-backup/password 2>/dev/null || true
systemctl --user cat spectre-backup.timer spectre-backup.service home-backup.timer home-backup.service 2>/dev/null || true
df -h / /backups /home
```

## Canonical paths (adopted)

| Purpose | Path |
|---|---|
| Engine | `scripts/backups/restic/{backup,verify,restore,prune,git-mirror,common}.sh` |
| Config templates (repo, no secrets) | `config/backups/restic/{env.example,include.conf,exclude.conf,include-remote.conf,include-artifacts.conf}` |
| Live env (secrets, outside repo) | `$RESTIC_CONFIG` (default for timers: `~/.secrets/spectre-suite-backups.env`) |
| Live config dir | `~/.config/spectre-suite/backups/` |
| State/markers | `~/.local/state/spectre-suite/backups/` (`last-success`, `last-offsite-success`, `last-verify`, `last-health`, etc.) |
| Repo password | `~/.secrets/spectre-restic-password` (copied from `~/.config/spectre-backup/password`; keep old copy) |
| Local repo (preserved) | `/backups/spectre-backup` (`RESTIC_REPOSITORY_LOCAL`) |
| Offsite repo (preserved) | `rclone:spectre-backup:` (`RESTIC_REPOSITORY`) |
| Daily backup timer | `spectre-restic-backup.timer` → `backup.sh` (default 04:10, `Persistent=true`) |
| Weekly verify timer | `spectre-restic-verify.timer` → `verify.sh` (default Sun 05:30, `Persistent=true`) |
| **Unchanged** artifact catch-up | `spectre-backup-catchup.timer` → `scripts/backups/run-missed-backups.sh` (05:00, after boot/resume) — **never disable/remove** |

## Snapshot/retention contract

- Every adopted snapshot: `--tag spectre-suite --tag workstation --host <hostname>`.
- Every `forget`: `--tag spectre-suite` (tag-scoped; never unscoped). Grandfathered `spectre-backup,workstation` snapshots (e.g. `fad2bfa8`) are never selected/touched.
- Retention (tag-scoped): `--keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1`.
- Offsite leg is **degraded, not fatal**: broken rclone/Drive must not prevent local backup success; local success markers are written and remote marked degraded (backup exits non-zero/degraded as implemented, but local snapshot/markers remain the source of local truth).

## Command mapping (no compatibility shims)

| Old | New |
|---|---|
| `~/.local/bin/spectre-backup.sh` / suite `scripts/backups/restic-backup.sh` | `scripts/backups/restic/backup.sh` |
| suite `scripts/backups/restic-maintenance.sh` / `restic-forget-prune.sh` | `scripts/backups/restic/prune.sh [--dry-run] [--repo local\|offsite\|all]` (tag-scoped) |
| *(new)* verify | `scripts/backups/restic/verify.sh [--full] [--local]` |
| *(new)* restore | `scripts/backups/restic/restore.sh --list\|--snapshot <id>\|--latest [--dry-run] [--target DIR] [--local] [paths...]` |
| `scripts/systemd/install-restic-maintenance-timer.sh` | `scripts/systemd/install-restic-verify-timer.sh` |
| `scripts/backups/restic.env.example` | `config/backups/restic/env.example` |

## Cutover sequence (§8.3 — stop on any failure)

1. **Baseline** — record snapshots, timers, checksums, free space (commands above).
2. **Install canonical config + password copy (no production switch yet)**  
   `mkdir -p ~/.config/spectre-suite/backups ~/.local/state/spectre-suite/backups`  
   Deploy templates from `config/backups/restic/`, overlay preserved live values (from `~/.config/spectre-backup/.env` as needed). `install -m 600` the env file.  
   `install -m 600 ~/.config/spectre-backup/password ~/.secrets/spectre-restic-password` (keep old copy).  
   Prove: `RESTIC_PASSWORD_FILE=~/.secrets/spectre-restic-password restic -r /backups/spectre-backup snapshots --compact`.
3. **Disable only `spectre-backup.timer` (preserve rollback)**  
   `systemctl --user disable --now spectre-backup.timer` (do **not** delete units). Leave `spectre-backup-catchup.timer` running. Record state.
4. **First adopted backup (manual, foreground, log captured)**  
   `RESTIC_CONFIG=~/.secrets/spectre-suite-backups.env scripts/backups/restic/backup.sh`  
   Confirm exit/markers (`~/.local/state/spectre-suite/backups/last-*`) and latest snapshot tags `spectre-suite,workstation`.  
   `restic -r /backups/spectre-backup snapshots --latest 1 --json`  
   `restic -r /backups/spectre-backup ls <id>` must contain `home/deon/dev`, `home/deon/docs`, `home/deon/.secrets` (allowed), `home/deon/archive/old-projects`, dump dir, artifact paths; and must **not** contain `spectre-restic-password`, `restic-repo-password`, or `.config/spectre-backup/password` (Review Focus 1).
5. **Verify + restore rehearsal (to `/tmp`, compare)**  
   `scripts/backups/restic/verify.sh`  
   `scripts/backups/restic/restore.sh --snapshot <id> --dry-run`  
   Restore to `/tmp/spectre-restore-rehearsal/<ts>/`: one file from `~/dev`, one from `~/docs`, one non-key file from `~/.secrets`, one artifact, one host dump. `diff`/`cmp`/`sha256sum` against originals. Record all commands/results.
6. **Retire home-backup timer (files kept)** — only if Step 5 passed  
   `systemctl --user disable --now home-backup.timer` (do not delete `~/.local/bin/backup-home` or `~/archive/backups`).
7. **Enable new timers + confirm metrics**  
   `scripts/systemd/install-restic-timer.sh` and `scripts/systemd/install-restic-verify-timer.sh`  
   `systemctl --user list-timers | grep spectre-restic`  
   Run/await exporter and confirm `restic_*` metrics and alert rules load (`restic_backup_alerts`).
8. **Record evidence; stop** — append snapshot id, marker contents, restore diffs, timer state, metric sample below. Do **not** archive spectre-backup repo, do **not** delete old configs/units/scripts, do **not** delete `~/archive/backups`.

## Restore paths (keep clearly separated)

- **Restore an artifact backup** (tar/db dumps produced by suite backup scripts): use `scripts/backups/restore-databases.sh`, `scripts/backups/restore-docker-volumes.sh`, `scripts/backups/restore-from-remote.sh` as appropriate. These operate on `/backups/*` archives and are independent of restic snapshots.
- **Restore from a restic snapshot** (adopted engine): `scripts/backups/restic/restore.sh --list`, then `--snapshot <id> --dry-run`, then `--snapshot <id> --target /tmp/restore-test [paths...]`. Use `--local` to read the local repo. Verify restored files before replacing originals.

## Monitoring / alerts

- Exporter reads `~/.local/state/spectre-suite/backups/` markers and emits `restic_*` gauges (missing/unparseable => `0`). Key metrics: `restic_last_success_timestamp`, `restic_last_verify_timestamp`, `restic_repo_size_bytes`, `restic_snapshots_total`, etc.
- Alert group: `restic_backup_alerts` (stale backup, missing/failed verify, repo/marker issues as defined in `prometheus/alert_rules.yml`).
- Existing artifact-backup alerts/markers remain intact.

## §8.1 Parity checklist (satisfy before retirement/archive gates)

- [ ] `spectre-suite,workstation` snapshot contains: `~/dev`, `~/docs`, `~/.secrets` (minus excluded keys), `~/archive/old-projects`, `/backups` artifact globs, host `pg_dumpall`, container config copies.
- [ ] `restic ls <id>` shows **no** repo password / `spectre-restic-password` / `restic-repo-password` / `.config/spectre-backup/password`.
- [ ] Tag-scoped forget selects only `spectre-suite` snapshots (grandfathered `spectre-backup` untouched).
- [ ] Local backup succeeds when offsite is degraded/unreachable; local markers written.
- [ ] `verify.sh` passes; restore rehearsal diffs clean for `~/dev`, `~/docs`, non-key `~/.secrets`, one artifact, one host dump.
- [ ] `spectre-backup-catchup.timer` still running/enabled.
- [ ] `restic_*` metrics and `restic_backup_alerts` load/behave as expected.
- [ ] Seven consecutive green days after cutover before deleting retired configs/units/scripts.

## Home-backup retirement / catch-up / archive gate

- **home-backup:** disable `home-backup.timer` only after successful rehearsal (Step 6). Keep `~/.local/bin/backup-home` and `~/archive/backups` until gates satisfied. **Never delete `~/archive/backups`.**
- **Catch-up:** `spectre-backup-catchup.timer`/`.service` are suite-owned artifact catch-up — kept running throughout and after cutover.
- **GitHub archive (conditional):** do **not** archive the standalone spectre-backup repo if any machine still needs the server role. Archive only after confirmation.

## Rollback

- Re-enable old timer: `systemctl --user enable --now spectre-backup.timer` (and `home-backup.timer` if disabled), disable `spectre-restic-backup.timer`/`spectre-restic-verify.timer`.
- Keep old password copy and old config files; repo and snapshots are unchanged (additive new snapshots only).
- Because forget is tag-scoped to `spectre-suite`, grandfathered snapshots remain intact regardless of new-engine actions.

## Evidence (append during Task 9; do not fabricate)

### Baseline
- Date/host:
- Local snapshots:
- Offsite snapshots:
- Timers:
- Free space:

### Cutover run
- First adopted snapshot id/tags:
- `restic ls` key-absence check:
- Markers (`last-success` / `last-offsite-success` / `last-verify`):
- Verify output:

### Restore rehearsal (`/tmp/spectre-restore-rehearsal/<ts>/`)
| Source | Restored path | Comparison (sha/diff/cmp) | Result |
|---|---|---|---|
| `~/dev` file | | | |
| `~/docs` file | | | |
| `~/.secrets` non-key file | | | |
| one artifact | | | |
| one host dump | | | |

### Timers/metrics after enable
- `systemctl --user list-timers` excerpt:
- `restic_*` metric sample:

### Notes / deviations
- 
