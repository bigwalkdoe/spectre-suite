# Migration: absorb spectre-backup into spectre-suite

**Date:** 2026-11-06  
**Spec:** `docs/superpowers/specs/2026-11-06-absorb-spectre-backup-design.md`  
**Plan:** `docs/superpowers/plans/2026-11-06-absorb-spectre-backup.md`  
**Status:** Tasks 1–8 landed. Task 9 executed 2026-11-06 on `fedora` (explicit approval). **Initial Step 4 FAILED (Review Focus 1):** snapshot `45e5f7c4` contained key material because `~` was not expanded in `--exclude-file`; it was **not** propagated offsite (orphaned offsite upload terminated) and was **forgotten locally** (`restic forget 45e5f7c4`; local repo now only `fad2bfa8` + validated snapshot below). `spectre-backup.timer` was re-enabled as interim rollback, excludes fixed to absolute paths (repo+deployed), 61 historical `root:root 600` `/backups/configurations/sshd_config_*` made readable (`0644`), and Task 9 was re-run/validated successfully (Steps 4–8). `spectre-backup.timer` and `home-backup.timer` are **disabled** (rollback units/files kept); `spectre-backup-catchup.timer` remains **enabled**; `spectre-restic-backup.timer` (04:10 daily) and `spectre-restic-verify.timer` (Sun 05:30 weekly) are **enabled**. **Do not** archive the spectre-backup repo, delete old configs/units/scripts, or delete `~/archive/backups` until §8.1 + seven consecutive green days and (for archive) no machine needs the server role.

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
| *(new)* restore | `spectre/actions/backups/restic/restore.sh --list\|--snapshot <id>\|--latest [--dry-run] [--target DIR] [--local] [--include <path>] [paths...]` |
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
   `spectre/actions/backups/restic/restore.sh --snapshot <id> --dry-run`  
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
- **Restore from a restic snapshot** (adopted engine): `spectre/actions/backups/restic/restore.sh --list`, then `--snapshot <id> --dry-run`, then `--snapshot <id> --target /tmp/restore-test [--include <path> | paths...]`. Use `--local` to read the local repo. Verify restored files before replacing originals.

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

## Evidence (Task 9, 2026-11-06 — STOPPED at Step 4)

### Baseline (Step 1)
- Date/host: `2026-11-06T07:30:59+05:00`, `fedora`
- Local snapshots (`/backups/spectre-backup`): 1 — `fad2bfa8` 2026-11-06 04:01:55 `spectre-backup,workstation` 14.560 GiB
- Offsite snapshots (`rclone:spectre-backup:`): 30 — latest `16cd965d` 2026-11-06 04:06:36 `spectre-backup,workstation`
- Timers (active): `home-backup.timer` (02:00, next 2026-11-07), `spectre-backup.timer` (04:25), `spectre-backup-catchup.timer` (05:00, **enabled**)
- Free space: `/` `/home` `/backups` 236G size, 158G used, 65G avail (71%)
- Config/password (pre-cutover): `~/.config/spectre-backup/.env` sha256 `20c95f9c…`, `password` sha256 `ad371f4d…`

### Step 2 (canonical config + password copy, no switch)
- Created `~/.config/spectre-suite/backups/` (deployed `include/exclude/include-remote/include-artifacts.conf` from `config/backups/restic/`) and `~/.local/state/spectre-suite/backups/`.
- Wrote `~/.secrets/spectre-suite-backups.env` (0600, preserved repo/rclone/PG/container/notify; `RESTIC_PASSWORD_FILE=$HOME/.secrets/spectre-restic-password`, `LOG_DIR=$HOME/.local/state/spectre-suite/backups`, `RESTIC_TAG=spectre-suite`).
- `install -m 600 ~/.config/spectre-backup/password ~/.secrets/spectre-restic-password` (sha256 matches old; old kept). Proven: `restic -r /backups/spectre-backup snapshots --compact` succeeded with new password file.

### Step 3
- `systemctl --user disable --now spectre-backup.timer` → removed `timers.target.wants/spectre-backup.timer` (units preserved). `spectre-backup-catchup.timer` remained **enabled**. `home-backup.timer` still active.

### Step 4 (first adopted backup) — **FAILED Review Focus 1 / STOP**
- A timed-out first attempt (tool timeout killed wrapper) left partial state: `last-attempt=1793932376`, `backup.log` showed `restic` interrupted by `SIGTERM` (`context canceled`) and many `permission denied` errors on 61 historical `root:root 0600` files in `/backups/configurations/sshd_config_*` (no `sudo -n`; total unreadable under `/backups` = 61). No new snapshot.
- Mitigation for readability (temporary, restored): appended the 61 exact unreadable paths to deployed `exclude.conf` (backup `exclude.conf.bak-cutover`) and reran.
- Rerun (07:36 PKT) created local snapshot **`45e5f7c4`** `2026-11-06T07:36:47.47244738+05:00` host `fedora` tags `["spectre-suite","workstation"]` (22.812 GiB). `last-success=1793932807 45e5f7c4`. Offsite leg then retried against `rclone:spectre-backup:` with Google Drive rate-limit/transient 500 responses (degraded by design) and was still running when verification began.
- **`restic ls 45e5f7c4` key-absence check: FAIL (Review Focus 1).** Snapshot contained `/home/deon/.config/spectre-backup/password`, `/home/deon/.secrets/restic-repo-password`, `/home/deon/.secrets/spectre-restic-password`. Scope targets (`/home/deon/dev`, `/home/deon/docs`, `/home/deon/.secrets`, `/home/deon/archive/old-projects`, dumps, `/backups/{databases,configurations,docker-volumes,projects}`) were present in the snapshot root list.
- **Root cause:** canonical/deployed `exclude.conf` used `~` (e.g. `~/.config/spectre-backup`, `~/.secrets/spectre-restic-password`, `~/.secrets/restic-repo-password`); restic does **not** expand `~` in `--exclude-file`, so absolute paths were not excluded.
- **Protective/remediation actions:** restored `exclude.conf` (removed temp unreadable-path entries); **terminated** orphaned offsite restic/rclone (`3828594`/`3828614`, backing up to `rclone:spectre-backup:`) to prevent propagation — confirmed `45e5f7c4` **not present** offsite (`restic snapshots 45e5f7c4` on `rclone:spectre-backup:` → “no matching ID”). Removed stale lock (`258b711a`, `restic unlock`) and **forgot `45e5f7c4` locally** (`restic forget 45e5f7c4`); repo now contains only `fad2bfa8`.
- **Fix applied (must validate before re-attempt):** replaced `~` with absolute `/home/deon/...` paths and added `/home/deon/.secrets/spectre-suite-backups.env` in both `config/backups/restic/exclude.conf` (repo) and `~/.config/spectre-suite/backups/exclude.conf` (deployed).
- `last-offsite-success` / `last-health`: not finalized (run terminated during degraded offsite phase). `last-attempt`/`last-success` reflect the aborted/compromised run and were **superseded by forgetting 45e5f7c4**; treat markers as invalid for cutover until a clean successful run.

### Interim rollback + remediation (between attempts)
- User requested `spectre-backup.timer` re-enabled (`enable --now`, symlink restored; active schedule shown). Exclude fix committed in-repo and applied to deployed config. Fixed 61 historical unreadables: `sudo chmod 0644 /backups/configurations/sshd_config_*` → `find ... -not -readable | wc -l` = `0`. `spectre-backup.timer` disabled again before validated re-run.

### Validated re-run (Steps 4–5)
- Backup: `RESTIC_CONFIG=$HOME/.secrets/spectre-suite-backups.env scripts/backups/restic/backup.sh` completed. **Local snapshot `5a8836ff`** `2026-11-06T08:03:03.09893535+05:00` host `fedora` tags `["spectre-suite","workstation"]` 22.802 GiB (local repo). **Offsite snapshot `1ff42d3a`** (offsite success marker). Markers: `last-attempt=1793934178`, `last-success=1793934407 5a8836ff`, `last-offsite-success=1793934569 1ff42d3a`, `last-health=1 1793934578`, `last-verify=1793934763 1` (after verify).
- **`restic ls 5a8836ff` key-absence: OK (no matches)** for `spectre-restic-password|restic-repo-password|.config/spectre-backup/password|spectre-suite-backups.env|.config/spectre-backup/.env`. Required scope present (dev, docs, `.secrets` with allowed non-key files only — excluded keys/envs absent, `restic.env` present as a non-excluded `~/.secrets` file), `archive/old-projects`, dumps (`/home/deon/.local/state/spectre-suite/backups/dumps/20261106-080258/host-pg_dumpall.sql.gz`), `/backups/{databases,configurations,projects,volumes}` artifacts.
- **Verify:** `scripts/backups/restic/verify.sh` (quick, local) RC 0 — “check snapshots, trees and blobs … no errors were found” / “Verify OK”. (Non-critical note: 170 additional files/duplicate data; `prune` can address.) Initial attempts hit stale repo locks (PIDs gone, from completed/interrupted runs); `restic unlock` cleared them.
- **Restore rehearsal** (`/tmp/spectre-restore-rehearsal/20261106-081053/`, snapshot `5a8836ff`, local): `restore.sh --local --snapshot 5a8836ff --dry-run` RC 0. Targeted restore via `restic restore ... --target ... --include <5 paths>` RC 0 (5 files). Note (historical, 2026-11-06): at that time `scripts/backups/restic/restore.sh` did not pass extra path args as includes, so a full dry-run traversed the whole snapshot and targeted restore used `restic restore --include` directly. Current `spectre/actions/backups/restic/restore.sh` supports extra path args and `--include <path>`.

| Source | Restored path (under `/tmp/spectre-restore-rehearsal/20261106-081053`) | sha256 (orig == restored) | Result |
|---|---|---|---|
| `~/dev` file | `home/deon/dev/github/actions-runner-light/_work/arcaden-labs/arcaden-labs/.gitignore` | `6c467f9465f512576fe9e3b46413aca9f004c856737cc312d19f871c263b4594` | OK |
| `~/docs` file | `home/deon/docs/Financial-Bills/E0692818000-May-2026.pdf` | `f4b639c7bbc2204061323a83876000f8eef7b3ea82ab1318c9cb1681a4d530a3` | OK |
| `~/.secrets` non-key file | `home/deon/.secrets/.gitignore` | `240a3e0d37d2e86b614063f5347eb02d4f99ca6c254de6b82871ff8d95532a7d` | OK |
| one artifact | `backups/configurations/dnf-automatic_20260831_201833` | `45c140275d0499070079635ef2b77cc0f209bcf4071ca6070e7d2e7d85945463` | OK |
| one host dump | `home/deon/.local/state/spectre-suite/backups/dumps/20261106-080258/host-pg_dumpall.sql.gz` | `42fe03cab68d0f47b6813f95af256d284b64852ec06a12197e0898078b9f25d4` | OK |

### Steps 6–8
- **Step 6:** `systemctl --user disable --now home-backup.timer` (symlink removed; files `~/.local/bin/backup-home`, `~/archive/backups` untouched). `spectre-backup-catchup.timer` **enabled/active**.
- **Step 7:** `scripts/systemd/install-restic-timer.sh` and `install-restic-verify-timer.sh` run — `spectre-restic-backup.timer` **enabled/active** (next 2026-11-07 ~04:18 PKT, `*-*-* 04:10:00`, `Persistent=true`) and `spectre-restic-verify.timer` **enabled/active** (next 2026-11-08 ~05:37 PKT, Sun 05:30, `Persistent=true`). `prometheus/business-metrics-exporter.sh` exported `restic_last_attempt/success/offsite_success_timestamp`, `restic_health_ok/timestamp`, `restic_verify_ok/timestamp` in `prometheus/business-metrics/backup_metrics.prom`. `prometheus/alert_rules.yml` contains `restic_backup_alerts`; `docker exec prometheus promtool check rules /etc/prometheus/alert_rules.yml` → **SUCCESS: 42 rules found**.
- **Step 8:** evidence recorded here.

### Notes / deviations
- **Key-leak incident (resolved):** first adopted snapshot `45e5f7c4` contained key paths due to `~` in `--exclude-file` (restic doesn’t expand `~`). Offsite propagation prevented (orphaned offsite run killed; `45e5f7c4` absent offsite); snapshot forgotten locally; repo lock/unlock handled. Fix: absolute-path excludes (+ `spectre-suite-backups.env`) in repo and deployed config. **Validated clean on `5a8836ff`.**
- 61 historical `root:root 600` config artifacts were made `0644` to unblock restic reads (separate from Task 1’s new-copy fix).
- `restore.sh` ignores extra positional/path args (no `--include` passthrough); targeted restore works with `restic restore --include`. Consider a follow-up improvement (not part of this cutover).
- **Not done (by design):** archive spectre-backup repo, delete old configs/units/scripts, delete `~/archive/backups`. Gate: §8.1 + 7 consecutive green days; archive only if no machine needs server role. Grandfathered `fad2bfa8` (`spectre-backup` tag) untouched; forget remains tag-scoped to `spectre-suite`. 
