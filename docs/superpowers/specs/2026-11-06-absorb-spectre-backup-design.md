# Absorb spectre-backup into spectre-suite — Design

**Date:** 2026-11-06
**Status:** Draft for approval — decisions recorded 2026-11-06
**Decision:** Option B — adopt the proven spectre-backup engine into spectre-suite.
spectre-suite becomes the single owner of backup code, configuration, scheduling,
retention, health, and restore for this workstation. Two jobs are retired after
cutover: the standalone spectre-backup install and the separate home-backup
timer. The spectre-backup GitHub repository is archived once the parity checklist
in §8.1 passes and seven consecutive days are green.

## 1. Intent and why

Two backup systems currently write to the same restic repository with unscoped
retention. Either one can delete the other's snapshots. Today that is prevented
only by the two installs using different password files, which is an accident,
not a design. We want one source of truth: one engine, one config, one schedule,
one retention policy, one health surface, one restore procedure.

The workstation engine already works and has months of snapshots. The goal is to
adopt it into the suite, not to rewrite it. A native port (option A) was rejected
as the larger risk; orchestration only (option C) was rejected because it leaves
two codebases and therefore two sources of truth.

## 2. Verified current state

### 2.1 What each system covers

| | `spectre-backup` | `spectre-suite` | `home-backup` |
|---|---|---|---|
| Home scope | `~/.bashrc`, `~/.bash_profile`, `~/.zshrc`, `~/.gitconfig`, `~/.gitignore_global`, `~/.ssh`, `~/.gnupg`, `~/.config`, `~/.local/share`, `~/.git-mirror`, `~/archives` (symlink), `~/resources`, `~/downloads`, `~/Screenshots` | none | `~/code` (symlink to `~/dev`) working trees, `~/docs`, `~/.secrets`, and the dotfiles repo |
| Data producers | `git-mirror.sh`, host `pg_dumpall` (socket, user `deon`), Podman/Docker configs | DB dumps from the `postgres` container, Docker volume tars, configurations, weekly project tars | none; it is a consumer of paths |
| Restic scope | the paths above plus the pre-backup dump directory | `/backups/databases/postgres_*.sql.gz`, `redis_backup_*.rdb`, `/backups/docker-volumes/spectre-suite_*.tar.gz`; optionally `/backups/configurations` and `/backups/projects` | n/a — tarballs under `~/archive/backups`, not a restic repo |
| Local repo | `/backups/spectre-backup` | default `/backups/spectre-backup` (same path) | `~/archive/backups`, last 7 tarballs |
| Offsite repo | `rclone:spectre-backup:` (Google Drive) | none; separate `replicate-backups.sh` to SSH/S3/B2 | none |
| Schedule | user timer daily 04:00 + up to 1h jitter, `Persistent=true` | cron 01:00 DB, 03:00 volumes, Sat 02:00 `backup-all`, 04:40 replication, 04:50 health; catch-up timer 05:00 | user timer daily 02:00, `Persistent=true` |
| Retention | hourly 24 / daily 30 / weekly 12 / monthly 12 / keep-last 1; prune after backup | default `forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`; installer exists, timer not installed | keep last 7 tarballs |
| Health | snapshot age (local/remote), disk free, Drive quota; exit 0/1/2 | archive structure and recency, markers, Prometheus metrics | none |
| Restore | `spectre-backup-restore.sh` (`--list`, `--snapshot`, `--local`, `--dry-run`, `--target`, `--verify`) | none for restic | untar by hand |

### 2.2 The collision

Both tools default to `/backups/spectre-backup`. They currently use different
password files:

- `~/.config/spectre-backup/password` (the repository's real key)
- `~/.secrets/restic-repo-password` (created for the new suite integration)

The suite's password cannot open the repository, so no snapshot has been
deleted. That is luck. Both `forget` invocations are unscoped: neither passes
`--tag` or `--host`.

The repository contains one snapshot:

```
fad2bfa8  2026-11-06T04:01:55  fedora  [spectre-backup, workstation]  14.560 GiB
```

The repository directory is 4.0 GiB on disk. No `spectre-restic-*` timer is
installed.

### 2.3 Permission and secret findings

`/backups/configurations` contains artifacts copied with `sudo cp` and left
`root:root 0600` (for example `sshd_config_*` and `fail2ban_jail_*`). A restic
backup running as `deon` cannot read them, and restic treats unreadable files as
an incomplete backup. The adopted scope therefore requires a small fix in
`backup-configurations.sh`: create copied artifacts owned by the invoking user
(for example `sudo install -o "$USER" -g "$USER" -m 640`), or chown them after
the copy. The tarballs created with `sudo tar` are already world-readable; only
the copied files are affected.

The old local scope includes `~/.config`, which includes
`~/.config/spectre-backup/password` — the restic repository key. The new scope
must exclude the retired config directory and the new repository-key file.
Recovery of the repository password is through the password manager, not through
a copy inside the repository.

### 2.4 Coverage gaps that matter

- The host PostgreSQL server (socket) has `modelink*` databases. The `postgres`
  container has `anomaly`. `backup-databases.sh` dumps the container;
  `pg_dumpall` dumps the host. Neither covers the other. Both must survive.
- The suite's artifact scope is not in the workstation restic scope. The
  workstation scope is not in the suite's artifact scope.
- A separate `home-backup.timer` (enabled, daily 02:00) tars `~/code` (a symlink
  to `~/dev`), `~/docs`, `~/.secrets`, and the dotfiles repo into
  `~/archive/backups`, keeping 7. It is the only protection for working trees,
  `~/docs`, and `~/.secrets`, none of which is in the restic scope. It is a
  third backup system. This change absorbs its scope and retires it (§8.2).
- `~/archives` is a symlink to `~/archive`. Restic archives the symlink itself,
  not its target, so the 13G under `~/archive/backups` and the 192M under
  `~/archive/old-projects` are not in the snapshot. The snapshot's only matching
  entry is `~/archives` as a link. Absorbing the home scope must list
  real paths, not the symlink.
- `/usr/local/bin/backup-all.sh` is a transitional forwarder to `spectre run
  backups/backup-all`. No system `backup.timer`/`backup.service` is installed.
- `prometheus/business-metrics-exporter.sh` auto-detects
  `/backups/spectre-backup` for repository size and free-space metrics.
  `BackupStale` reads the DB backup marker, not restic.

## 3. Goals

1. One engine for restic backups, owned by spectre-suite.
2. One canonical config location; no second active config directory.
3. One schedule; old and new timers never run together after cutover.
4. Retention scoped by tag, so a run can only forget snapshots it created.
5. Preserve the existing repository, its snapshots, and its password.
6. Preserve both database coverages (host and container) and both artifact
   scopes (home and `/backups`).
7. Keep the Drive offsite leg working.
8. Make snapshot health visible to Prometheus and the runbook.
9. Prove restore works before retiring anything.
10. Absorb home-backup's scope (`~/dev` working trees, `~/docs`, `~/.secrets`)
    into the local restic run and retire the third job.
11. Retire and archive spectre-backup only after the workstation functions in
    §8.1 are covered and the old install is no longer needed.

## 4. Non-goals

- Rewriting the engine in Python or doing a native port (option A).
- Changing the offsite provider or the Drive quota.
- Re-keying the restic repository.
- Fixing unrelated defects (`backup-projects.sh` referencing the retired
  `~/scripts` fork, the `backup-configurations.sh` Guardrail-only
  project tar) as part of this change.
- Providing a server-role installer for other machines. Parity for this change
  is the workstation role on this host; the server role is explicitly outside
  the §8.1 checklist and would need a separate project.
- Deleting `~/archive/backups` or rewriting the archive tree. The tarballs stay
  on disk after home-backup is retired; they are simply no longer the backup.
- Changing the local `~/.config` browser-profile coverage (Chrome, Code,
  Cursor). It is existing scope; trimming it is a separate optimisation.

## 5. Anti-goals

- Both backup timers enabled after cutover.
- Any `forget`/`prune` without a tag filter.
- Losing the existing snapshot, the repository password, or the Drive remote.
- Deleting the old install before a restore has been rehearsed.
- Retiring home-backup before `~/dev`, `~/docs`, and `~/.secrets` are in a
  verified snapshot.
- Archiving spectre-backup before every workstation function in §8.1 is covered
  and seven consecutive days are green.
- Two directories that both look canonical.
- A "successful" backup that omits one of the two database populations.

## 6. Approaches considered

| | How | Trade-off |
|---|---|---|
| A. Native port | Reimplement the workstation flow inside the suite's existing `restic-*.sh` | Cleanest code, largest rewrite, highest risk to the only working backup |
| **B. Adopt engine** (chosen) | Move the proven scripts, library, config templates, and tests into the suite; adapt paths, tags, and scheduling; retire the old install | Fast, low risk, one owner; inherits a second code lineage until it is trimmed |
| C. Orchestrate only | Keep spectre-backup installed and have the suite call it | Smallest change, but two codebases remain; not a real source of truth |

B is chosen. The engine is adopted as the implementation; the suite owns it.

## 7. Target design

### 7.1 Repository layout

```
scripts/backups/restic/
  backup.sh          # adopted from scripts/spectre-backup.sh
  restore.sh         # adopted from scripts/spectre-backup-restore.sh
  verify.sh          # adopted from scripts/spectre-backup-verify.sh
  prune.sh           # adopted from scripts/spectre-backup-prune.sh
  common.sh          # adopted from lib/spectre-backup-common.sh
  git-mirror.sh      # adopted from scripts/git-mirror.sh
config/backups/restic/
  env.example
  include.conf
  exclude.conf
  include-remote.conf
  include-artifacts.conf
scripts/systemd/
  install-restic-timer.sh              # rewritten for the adopted engine
  install-restic-verify-timer.sh       # weekly verify (replaces forget/prune timer)
tests/
  test_restic_backup.sh
  test_restic_retention.sh
docs/
  migration/2026-11-06-absorb-spectre-backup.md
```

Retired in this change:

- `scripts/backups/restic-backup.sh`
- `scripts/backups/restic-maintenance.sh`
- `scripts/backups/restic-forget-prune.sh`
- `scripts/backups/restic.env.example`
- `scripts/systemd/install-restic-maintenance-timer.sh` (replaced by the verify
  timer)
- the active `~/.config/spectre-backup/` install
- `spectre-backup.timer` and `spectre-backup.service`
- the installed `~/.local/bin/spectre-backup*.sh` copies

`spectre-backup-catchup.timer` and `spectre-backup-catchup.service` are **not**
retired. Despite the name, they run the suite's
`scripts/backups/run-missed-backups.sh`; they are the 05:00 artifact catch-up,
not the old engine. A wildcard removal of `spectre-backup*` would break the
suite.

The suite's existing `restic-*.sh` scripts are three days old and unscheduled.
They are removed so there is exactly one restic engine.

`install.sh` currently copies `scripts/backups/*.sh` flat into
`/usr/local/bin`. It must be updated so the new `scripts/backups/restic/`
directory is either installed deliberately or explicitly left as a user-level
tool; it must not silently omit the engine that the timer runs.

### 7.2 Canonical configuration

Non-secret config:

```
~/.config/spectre-suite/backups/
  include.conf            # home/workstation paths
  exclude.conf            # exclusions
  include-remote.conf     # small offsite scope
  include-artifacts.conf  # explicit /backups globs
```

Secrets and environment:

```
~/.secrets/spectre-suite-backups.env   # mode 600; repository, PG, rclone, notify
~/.secrets/spectre-restic-password     # mode 600; the existing repository key
```

The environment file carries forward the deployed `spectre-backup` settings
rather than reverting to defaults:

| Setting | Value to preserve |
|---|---|
| `RESTIC_REPOSITORY` | `rclone:spectre-backup:` |
| `RESTIC_REPOSITORY_LOCAL` | `/backups/spectre-backup` |
| `RESTIC_PASSWORD_FILE` | `~/.secrets/spectre-restic-password` |
| `PG_ENABLED`, `PG_HOST`, `PG_PORT`, `PG_USER` | host cluster settings (socket) |
| `CONTAINERS_ENABLED` | `true` |
| `NOTIFY_ENABLED`, `NOTIFY_DESKTOP` | `true` |
| `RCLONE_TPSLIMIT`, `RCLONE_TPSLIMIT_BURST` | the current Drive pacing values |
| `RCLONE_DRIVE_CHUNK_SIZE`, `RCLONE_RETRIES`, `RCLONE_LOW_LEVEL_RETRIES` | current values |
| `RESTIC_TAG` | `spectre-suite` |

The password migration is: copy (not move) the existing
`~/.config/spectre-backup/password` to `~/.secrets/spectre-restic-password`,
verify it opens the repository, and keep the old copy until the retirement step.
The unused `~/.secrets/restic-repo-password` cannot open the repository and is
removed only after the cutover.

`~/.secrets`, `~/dev`, and `~/docs` are now in the local scope, so the exclude
file must contain:

```
**/.config/spectre-backup          # old install; contains the old key
**/.secrets/spectre-restic-password # the repository key; never inside
**/.secrets/restic-repo-password    # unused key that cannot open the repo
**/archive/backups                  # home-backup output; redundant
**/archives                         # symlink to ~/archive; see below
```

The environment file `~/.secrets/spectre-suite-backups.env` is intentionally
*not* excluded: it holds repository, PostgreSQL, and rclone settings, not the
repository key. If it ever gains a credential, that credential moves to its own
file and is excluded. Recovery of the repository key remains via the password
manager.

`~/archive/backups` is the retired home-backup output. It is 13G of copies whose
sources are in the new snapshot, so backing it up again would only inflate the
repository. `~/archive/old-projects` (192M) and `~/archive/installers` (632K)
are small and included by real path; `~/archives` is excluded because restic
stores the symlink itself, not the target.

Sizing: `~/dev` is 25G on disk and 7.4G after the existing excludes
(`node_modules`, `.venv`, `dist`, `build`, `.cache`, `target`); `~/docs` is 83M
and `~/.secrets` is 40K. The repository is 4.0G for a 14.56G snapshot, and
`/backups` has 65G free. The first run adds less than 7.5G (restic compresses;
the current repository is 4.0G for a 14.56G snapshot), so free space stays well
above the 20G `BackupRepoFreeSpaceLow` floor. The first incremental run will take
longer than a normal night; it is run manually at cutover.

State and logs:

```
~/.local/state/spectre-suite/backups/
  backup.log
  dumps/<timestamp>/
  last-attempt
  last-success
  last-offsite-success
  last-health
  last-verify
```

The repository paths stay as they are for continuity:

```
RESTIC_REPOSITORY_LOCAL=/backups/spectre-backup
RESTIC_REPOSITORY=rclone:spectre-backup:
```

`/backups/spectre-backup` keeps its historical name. Renaming it is deferred:
the path is embedded in Prometheus, docs, and the existing config, and a rename
adds a cutover failure mode without changing ownership. The design records the
name as historical, not as a second product.

Tags:

- new snapshots: `--tag spectre-suite --tag workstation --host <hostname>`
- old snapshots keep `spectre-backup` + `workstation`

### 7.3 Scope construction

`backup.sh` builds two target lists.

Local targets:

1. Every existing path in `include.conf` (home scope).
2. Every glob in `include-artifacts.conf` that matches:
   - `/backups/databases/postgres_*.sql.gz`
   - `/backups/databases/redis_backup_*.rdb`
   - `/backups/docker-volumes/spectre-suite_*.tar.gz`
   - `/backups/configurations`
   - `/backups/projects`
3. The pre-backup dump directory.

The artifact list is explicit, not `/backups`, because `/backups` is shared and
contains other projects' volumes and the restic repository itself. The latter
must never be a backup target.

`include.conf` additions for the absorbed home-backup scope:

```
~/dev
~/docs
~/.secrets
~/archive/old-projects
~/archive/installers
~/archive/README.md
```

`~/code` and `~/documents` are symlinks to `~/dev` and
`~/docs`; they are not listed, so each byte is stored once under its real path.
The existing `~/archives` symlink entry is removed and replaced by the real paths
above. The non-existent `~/resources`, `~/downloads`, and `~/Screenshots`
entries are removed from the template and the deployed config, so the run stops
warning about them. The `.git` directories under `~/dev` are included: the git
mirror covers committed history, but the working-tree copy is what makes the
snapshot a complete replacement for home-backup. `~/dev` remains local-only.

The restic exclude list is a superset of home-backup's rsync excludes: it keeps
the same `node_modules`, `.venv`, `__pycache__`, `dist`, and `build` rules and
also drops `target`, `.cache`, `go/pkg`, and similar regenerable directories.
The absorbed copy is therefore not byte-for-byte identical to the old tarball,
by design; source, commits, and untracked files remain.

Offsite targets:

1. Every path in `include-remote.conf`.
2. `/backups/databases` and the pre-backup dump directory (which contains the
   host `pg_dumpall` and the container configs). These are small and
   irreplaceable; the current offsite scope omits the host dump entirely.
3. `~/docs` (83M of source, irreplaceable). This replaces the `~/docs`
   coverage that only home-backup had.
4. Deliberately not the Docker volumes, configurations, projects, working trees,
   or `~/.secrets`. The Drive quota governs this list, and credentials beyond
   `.ssh`/`.gnupg` stay off the Drive leg.

The dump directory is created in step 2 of the flow, before targets are built,
so it is a real path when the offsite list is constructed. If PostgreSQL is
disabled or unreachable, the dump is absent and the offsite list simply omits
it; the rest of the backup still runs.

`build_targets` is extended to expand globs, skip missing paths with a warning,
and de-duplicate. It must reject any resolved path under
`$RESTIC_REPOSITORY_LOCAL`.

### 7.4 Flow

1. Refresh the git mirror (`git-mirror.sh`).
2. Dump the host PostgreSQL cluster with `pg_dumpall` into the dump directory.
3. Copy Podman/Docker configuration into the dump directory, with the ownership
   fix from §2.3.
4. Build local and offsite targets.
5. `restic backup` the local repository with the tags above.
6. `restic backup` the offsite repository with the offsite targets and the same
   tags. If the rclone remote is unavailable, log the offsite leg as degraded,
   leave the local success marker intact, and continue. A broken remote must
   never prevent the local backup from completing.
7. `restic forget --tag spectre-suite` with the adopted policy, then `prune`,
   once per repository.
8. Write success markers; run the health check; notify on failure or degraded
   offsite.

The retired `home-backup` script is not invoked. Its content scope is covered by
the local targets in §7.3; no tarball is produced. The dotfiles repo under
`~/dev/github/dotfiles` is already inside `~/dev`.

Retention policy (adopted):

```
--keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1
```

`restic prune` has no tag filter. Prune only removes data unreferenced after
`forget`; scoping `forget` is what prevents another owner's snapshots from being
forgotten. The old `spectre-backup` snapshots are therefore grandfathered: the
new policy never selects them. A one-time manual cleanup is documented for
later, with a dry run first.

### 7.5 Schedule

| Time | Job | Owner |
|---|---|---|
| 01:00 | DB dumps (container) | suite cron (unchanged) |
| 02:00 | `home-backup` (retired at cutover) | old user timer |
| 03:00 | Docker volume tars | suite cron (unchanged) |
| Sat 02:00 | `backup-all.sh` (configs, projects) | suite cron (unchanged) |
| 04:00 | `spectre-backup` (retired at cutover) | old user timer |
| 04:10 | restic backup + prune | new `spectre-restic-backup.timer` |
| 04:40 | `replicate-backups.sh` | suite cron (unchanged) |
| 04:50 | `check-backup-health.sh` | suite cron (unchanged) |
| 05:00 | artifact catch-up | suite timer (unchanged) |
| weekly | `restic verify` (quick) | new `spectre-restic-verify.timer` |

The new timer is `Persistent=true` with a small randomized delay, so a missed
run catches up after wake or boot. The old `spectre-backup.timer` is stopped and
disabled at cutover. The separate `home-backup.timer` is stopped and disabled
only after the new snapshot and restore rehearsal prove its scope is covered; it
is not rescheduled. No window has two home-scope backups running.

The 05:00 catch-up is suite-owned and misnamed
`spectre-backup-catchup.timer`; it runs `run-missed-backups.sh` and is not
retired with the engine. Its name is historical, not a second owner.

### 7.6 Health and monitoring

The adopted engine keeps `--health` (local snapshot age, offsite snapshot age,
disk free, quota; exit 0/1/2). It runs at the end of every backup and writes a
verdict marker; it is not run by the five-minute exporter.

Marker files under `~/.local/state/spectre-suite/backups/`:

| File | Contents | Written by |
|---|---|---|
| `last-attempt` | Unix timestamp | backup start |
| `last-success` | `<timestamp> <snapshot-id>` | local backup success |
| `last-offsite-success` | `<timestamp> <snapshot-id>` | offsite backup success |
| `last-health` | `<0-or-1> <timestamp>` | health check at end of run |
| `last-verify` | `<0-or-1> <timestamp>` | weekly `verify.sh` |

Marker semantics for the exporter:

- Timestamps are Unix seconds. `<snapshot-id>` is the second whitespace-separated
  field of `last-success` / `last-offsite-success`; it is diagnostic only.
- A missing, empty, or unparseable marker is exported as `0`, so a missing
  success is visible as `restic_last_success_timestamp == 0`, not as a
  disappeared series. The exporter logs the parse failure.
- `last-attempt` is written before the first dump; it is not a success signal.
- `last-health` is written on every completed run, including failures, as
  `<0-or-1> <timestamp>`. `restic_health_ok` is 1 only for exit 0; it is 0 for
  exit 1 (failed) or 2 (degraded).
- `last-verify` is written only by `verify.sh`; the first write is the cutover
  rehearsal, not the first timer run.

`prometheus/business-metrics-exporter.sh` gains, read from those markers:

```
restic_last_attempt_timestamp
restic_last_success_timestamp
restic_last_offsite_success_timestamp
restic_health_ok
restic_health_timestamp
restic_verify_ok
restic_verify_timestamp
```

`backup_repo_size_bytes` and the filesystem metrics keep working because the
repository path does not change.

`prometheus/alert_rules.yml` gains:

```yaml
- alert: ResticBackupMissing
  expr: restic_last_success_timestamp == 0
  for: 1h
  labels: { severity: critical }

- alert: ResticBackupStale
  expr: restic_last_success_timestamp > 0 and time() - restic_last_success_timestamp > 129600   # 36h
  for: 1h
  labels: { severity: warning }

- alert: ResticOffsiteMissing
  expr: restic_last_offsite_success_timestamp == 0 and restic_last_success_timestamp > 0
  for: 72h
  labels: { severity: warning }

- alert: ResticOffsiteStale
  expr: restic_last_offsite_success_timestamp > 0 and time() - restic_last_offsite_success_timestamp > 259200   # 72h
  for: 1h
  labels: { severity: warning }

- alert: ResticHealthFailed
  expr: restic_health_timestamp > 0 and restic_health_ok == 0
  for: 30m
  labels: { severity: warning }

- alert: ResticVerifyFailed
  expr: restic_verify_timestamp > 0 and restic_verify_ok == 0
  for: 30m
  labels: { severity: critical }

- alert: ResticVerifyStale
  expr: restic_verify_timestamp > 0 and time() - restic_verify_timestamp > 691200   # 8d
  for: 1h
  labels: { severity: warning }
```

The existing `BackupStale` and `BackupHealthCheckFailed` alerts remain for the
artifact backups.

### 7.7 Restore and verify

`restore.sh` keeps the adopted interface:

```
restore.sh --list
restore.sh --snapshot <id> --dry-run
restore.sh --snapshot <id> --target /tmp/restore-test
restore.sh            # latest, local by default
```

`verify.sh` keeps quick and `--full` modes.

The cutover rehearsal restores one file from each newly absorbed scope (`~/dev`,
`~/docs`, `~/.secrets`), one artifact, and one host dump, in addition to the
small-file check. It also lists the snapshot to confirm the excluded repository
key is absent.

The runbook documents the snapshot path separately from the artifact path, so an
operator knows which restore tool matches which failure.

### 7.8 Tests

Unit tests, no real repository:

- `build_targets` expands globs, skips missing paths, and refuses the repository
  path.
- `forget` arguments always include `--tag spectre-suite`.
- backup arguments always include `--tag spectre-suite` and `--host`.
- config resolution honours the suite's config/state directories.
- the absorbed scope adds `~/dev`, `~/docs`, and `~/.secrets`, but not the
  `~/code` / `~/documents` symlinks.
- the exclude set keeps the repository key out of the target list.
- `~/archive/backups` is excluded and `~/archive/old-projects` is included.
- marker parsing returns 0 for missing or unparseable files and returns the
  snapshot id from the success marker.
- restore/verify argument parsing accepts the documented flags.

Integration test in a temporary directory:

- initialise a throwaway restic repo under `mktemp -d`
- back up a small fixture home and artifact tree
- run `forget` and confirm only tagged snapshots are selected
- run `verify` and a dry-run restore

Checks: `shellcheck` on every adopted script; the existing suite test runner
passes; no secrets in the repository.

### 7.9 Documentation

- Rewrite the README backup section around one command surface, one schedule,
  one restore procedure.
- Update `docs/RUNBOOKS.md` runbook 4.
- Add `docs/migration/2026-11-06-absorb-spectre-backup.md` with the cutover
  checklist, verification evidence, and rollback.
- Document the legacy `/backups/spectre-backup` name and the grandfathered
  snapshots.

## 8. Cutover

### 8.1 Feature parity checklist (archive gate)

The spectre-backup repository is archived only when every row below is true on
this workstation. "Suite" means the adopted engine after cutover.

| Function | Covered by | Evidence |
|---|---|---|
| Home-scope backup | `include.conf` + `backup.sh` | snapshot lists all paths |
| Git history mirror | `git-mirror.sh` | mirror runs in the backup flow |
| Host `pg_dumpall` | dump step | dump file in the snapshot |
| Podman/Docker configs | dump step | config copy in the snapshot |
| Artifact scope (DB, volumes, configs, projects) | `include-artifacts.conf` | globs match |
| Local repo `/backups/spectre-backup` | env | `restic snapshots` |
| Drive offsite repo | env | `restic snapshots -r rclone:...` |
| Retention policy | `forget --tag spectre-suite` | dry-run selects only new snapshots |
| Prune | `prune` | completes without error |
| Health check | `--health` + markers | metrics present |
| Verify | `verify.sh` + timer | `last-verify` |
| Restore | `restore.sh` | rehearsed restore of every new scope |
| Notifications | adopted env | test notification |
| Daily schedule | new timer | `systemctl --user list-timers` |
| Installer for this host | `install-restic-timer.sh` | timer installed |

Not in parity scope: the old server-role installer and multi-distro support. No
server currently uses them. The archive is therefore conditional on confirming
that no machine still needs that role; if one does, keep the repository
maintained instead of archiving. The archive is reversible and the code remains
in git history.

### 8.2 Retire home-backup

`home-backup.timer` is disabled only after the first new snapshot has been
verified and a file from each absorbed scope has been restored. The script
(`~/.local/bin/backup-home`), the units in `~/.config/systemd/user/`, and the
timer are removed at the archive step, not before. `~/archive/backups` is left
untouched; it is redundant, not wrong, and deleting it is a separate decision.

### 8.3 Sequence

1. Record the baseline: `restic snapshots`, old `--health`, timer state, and
   checksums of the old config. The old spectre-backup units live in
   `~/.local/share/systemd/user/`; the home-backup units and the suite's
   `spectre-backup-catchup` units live in `~/.config/systemd/user/`. The
   installed scripts are copies under `~/.local/bin/`. Record the catch-up unit
   so it is not removed by a wildcard.
2. Add the adopted code, config templates, installers, and tests. Do not switch
   production yet.
3. Fix the `backup-configurations.sh` permissions so the restic user can read
   every artifact it is expected to snapshot.
4. Disable (do not remove) `spectre-backup.timer` before the first real run, so
   the old and new engines cannot overlap. Rollback is a re-enable.
5. Copy the repository password to `~/.secrets/spectre-restic-password` and
   prove it opens `/backups/spectre-backup` with `restic snapshots`.
6. Run the new `backup.sh` manually against the real repositories with the
   `spectre-suite` tag. The run is incremental and safe. Confirm the snapshot
   contains home paths, `~/dev`, `~/docs`, `~/.secrets`,
   `~/archive/old-projects`, artifact globs, the host dump, and the container
   config copy. Confirm the repository key is absent.
7. Run `verify.sh`, then `restore.sh --snapshot <new> --dry-run`, then restore
   one file from each newly absorbed scope, one artifact, and one host dump to
   `/tmp`, and compare them.
8. Disable (do not remove) `home-backup.timer`. Its scope is now in the verified
   snapshot; its files stay for rollback.
9. Install and enable `spectre-restic-backup.timer` and the weekly verify timer.
10. Update Prometheus/exporter, README, and runbook; run the health check and
    confirm the new metrics appear.
11. After seven consecutive green days and a complete §8.1 checklist, archive
    the spectre-backup GitHub repository, remove the old config, units, and
    installed scripts, remove the home-backup unit and script, and record the
    retirement. Leave `spectre-backup-catchup.timer`/`.service` in place. Keep
    the local spectre-backup clone as a read-only reference until a later
    cleanup.
12. Keep the old snapshots and the `~/archive/backups` tarballs. Nothing in this
    cutover deletes repository data.

Rollback until step 11: stop the new timers, re-enable `spectre-backup.timer`
and `home-backup.timer`, and keep the old config and password copy. No repository
data is rewritten by the cutover, so rollback does not need a restore. After the
archive, rollback means unarchiving the repository and reinstalling; the data is
unaffected.

## 9. Decisions

1. **home-backup** (2026-11-06): absorb `~/dev` as well as `~/docs` and
   `~/.secrets`, and retire the third job. The older engine's working-tree
   exclusion is deliberately reversed: one backup is worth more than the saved
   space, and 7.4G after excludes fits the 65G free. `~/dev` is local-only.
2. **spectre-backup repository** (2026-11-06): archive the GitHub repository
   entirely once the §8.1 parity checklist passes and seven consecutive days are
   green. "All its functions" is read as the workstation functions in §8.1; the
   only uncovered function is the server-role installer. If any machine still
   needs that role, do not archive; keep the repository maintained instead. The
   archive is reversible. The local clone is kept until a later cleanup;
   `~/archive/backups` is not deleted.
3. **Offsite scope** (2026-11-06): add `/backups/databases` and the host dump to
   the Drive leg, plus `~/docs`. `~/dev` and `~/.secrets` stay local-only. This
   was the recommendation; correct it at approval if unwanted.
4. **Repository rename**: keep `/backups/spectre-backup`; renaming is deferred.

## 10. What is left to the builder

- Exact function and variable renames inside the adopted library.
- Unit-file contents and the installer's `--print`/`--uninstall` behaviour.
- The precise Prometheus metric names within the proposed set.
- The final `include.conf` / `exclude.conf` contents and the marker parser.
- Whether to keep compatibility shims for the old command names. Recommendation:
  none; map old to new in the migration document.
- Test fixture layout and shellcheck wiring.
- The wording of the migration and runbook documents.
- The exact GitHub archive step and whether the local clone stays or moves to
  `~/archive/superseded`.
