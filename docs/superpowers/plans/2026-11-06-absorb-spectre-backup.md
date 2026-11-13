# Absorb spectre-backup into spectre-suite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make spectre-suite the single owner of workstation restic backups by adopting the proven spectre-backup engine, absorbing the home-backup scope, keeping the existing `/backups/spectre-backup` repo/password/Drive remote, and retiring the standalone installs only after a verified cutover.

**Architecture:** Copy/adapt the proven shell engine from `~//dev/github/spectre-backup` into `scripts/backups/restic/` (library, git mirror, backup/prune/verify/restore). The new engine reads `~/.config/spectre-suite/backups/*` and `~/.secrets/spectre-suite-backups.env` / `~/.secrets/spectre-restic-password`, writes state markers under `~/.local/state/spectre-suite/backups/`, tags every snapshot `spectre-suite,workstation`, and scopes `forget` to that tag so it never touches the grandfathered `spectre-backup` snapshots. Local success is never blocked by an offsite failure. Monitoring reads markers, not `restic`.

**Tech Stack:** Bash + coreutils + jq, `restic`, `rclone`, `pg_dumpall`/Podman config copy, `systemd --user` timers, Prometheus textfile metrics + `promqltest`/alert rules, the suite's `tests/run_tests.sh` shell runner.

**Spec:** `docs/superpowers/specs/2026-11-06-absorb-spectre-backup-design.md` (the plan argues from the spec; read both).

## Global Constraints

- Option B: adopt the proven engine; do not rewrite in Python (spec §6).
- One restic engine in the suite after this change: retire the three-day-old `scripts/backups/restic-*.sh` / maintenance timer / their tests when the adopted engine replaces them.
- Keep the existing repository, snapshots, and password: `RESTIC_REPOSITORY_LOCAL=/backups/spectre-backup`, `RESTIC_REPOSITORY=rclone:spectre-backup:`, key copied from `~/.config/spectre-backup/password` to `~/.secrets/spectre-restic-password` (no re-key).
- Every snapshot: `--tag spectre-suite --tag workstation --host <hostname>`. Every `forget`: `--tag spectre-suite`. Old `spectre-backup` snapshots are grandfathered; never unscoped.
- Offsite leg is degraded, not fatal: a broken rclone remote must not prevent local backup success.
- Absorb home-backup scope locally: `~/dev`, `~/docs`, `~/.secrets`, `~/archive/old-projects`, `~/archive/installers`, `~/archive/README.md` (real paths, not `~/code`/`~/documents`/`~/archives` symlinks). Exclude `~/archive/backups` and the repo key. `~/dev` local-only.
- Offsite adds `/backups/databases` + dump dir + `~/docs`; excludes `~/dev`, `~/.secrets`, volumes/configs/projects.
- Retention: `--keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1`, tag-scoped.
- Preserve host `pg_dumpall` and container artifact coverage; never omit one DB population.
- Config artifacts for restic must be readable by the invoking user (fix `backup-configurations.sh` `root:root 0600` copies; §2.3).
- `spectre-backup-catchup.timer`/`.service` are suite-owned artifact catch-up (`run-missed-backups.sh`) — do not remove or disable them in wildcard cleanup.
- No compatibility shims for old command names; document the mapping. No server-role installer. No `~/archive/backups` deletion. No repo rename.

## Review Focus

The spec implies inputs no task tests by default that are most likely to bite. Each item is owned by a task below; the test lives in that task.

1. **Repository key in a snapshot** — a path under `~/.secrets` or `~/.config/spectre-backup` that resolves to the restic password is backed up; a reasonable person expects the key never inside the repo. (Task 3 excludes + Task 4/9 rehearsal asserts absence.)
2. **Unscoped retention touches old snapshots** — `forget`/prune without `--tag spectre-suite` selects `fad2bfa8` (`spectre-backup,workstation`); expect only new tagged snapshots selected. (Task 3 unit test + Task 5 args.)
3. **`~/archives` symlink hides `/archive` content** — listing the symlink stores a link, not `~/archive/old-projects`; expect real source paths and `~/archive/backups` excluded. (Task 2 config + Task 3 build_targets/fixture.)
4. **Offsite failure fails the whole backup** — rclone/Drive error during the remote leg returns non-zero and skips local markers; expect local success markers written and remote marked degraded. (Task 4.)
5. **`root:root 0600` artifacts unreadable** — `backup-configurations.sh` copies `sshd_config`/`fail2ban_jail_*` so only root can read them; restic runs as `deon` and must read what it snapshots. (Task 1.)

## File Map

| File | Responsibility |
|---|---|
| `scripts/backups/backup-configurations.sh` (modify) | Copy config artifacts readable by invoking user (§2.3). |
| `config/backups/restic/env.example` (create) | Canonical env template (deployed values preserved). |
| `config/backups/restic/include.conf` (create) | Local home + archive-real-path scope. |
| `config/backups/restic/exclude.conf` (create) | Key/excludes/symlink/archive-backups suppression. |
| `config/backups/restic/include-remote.conf` (create) | Small offsite scope + `~//docs`. |
| `config/backups/restic/include-artifacts.conf` (create) | Explicit `/backups` globs (no repo path). |
| `scripts/backups/restic/common.sh` (create) | Adopted lib: distro/dirs/env, markers, `build_targets` (glob, skip, dedup, refuse repo path), restic arg helpers, degraded/offsite helpers. Source: `spectre-backup/lib/spectre-backup-common.sh` + engine helpers. |
| `scripts/backups/restic/git-mirror.sh` (create) | Adopted mirror. Source: `spectre-backup/scripts/git-mirror.sh`. |
| `scripts/backups/restic/backup.sh` (create) | Main flow: mirror, host pg_dumpall, container configs, local backup, offsite backup (degraded-ok), tag-scoped forget/prune, markers/health. Source: `spectre-backup/scripts/spectre-backup.sh`. |
| `scripts/backups/restic/prune.sh` (create) | Tag-scoped forget/prune wrapper. Source: `spectre-backup/scripts/spectre-backup-prune.sh`. |
| `scripts/backups/restic/verify.sh` (create) | Quick/full verify; writes `last-verify`. Source: `spectre-backup/scripts/spectre-backup-verify.sh`. |
| `scripts/backups/restic/restore.sh` (create) | List/dry-run/target restore. Source: `spectre-backup/scripts/spectre-backup-restore.sh`. |
| `scripts/systemd/install-restic-timer.sh` (rewrite) | User timer for `backup.sh` (04:10, `Persistent=true`, jitter), `--print/--uninstall`. |
| `scripts/systemd/install-restic-verify-timer.sh` (create) | Weekly `verify.sh` timer, `--print/--uninstall`. |
| `prometheus/business-metrics-exporter.sh` (modify) | Read `~/.local/state/spectre-suite/backups/` markers; export `restic_*` gauges; missing/unparseable => `0`. |
| `prometheus/alert_rules.yml` (modify) | Add spec §7.6 restic alerts; keep existing backup alerts. |
| `install.sh` (modify) | Install `scripts/backups/restic/*.sh` deliberately (not a blind flat glob that misses intent) or record user-level install; keep behavior explicit. |
| `scripts/backups/restic-backup.sh` (delete) | Retired suite restic stub. |
| `scripts/backups/restic-maintenance.sh` (delete) | Retired. |
| `scripts/backups/restic-forget-prune.sh` (delete) | Retired. |
| `scripts/backups/restic.env.example` (delete) | Replaced by `config/backups/restic/env.example`. |
| `scripts/systemd/install-restic-maintenance-timer.sh` (delete) | Replaced by verify timer. |
| `tests/test_restic_adopted.sh` (create) | Unit tests: build_targets, tag args, marker parse/write, config resolution, excludes. |
| `tests/test_restic_integration.sh` (create) | Temp-repo integration with `restic` (skip if unavailable): init, tagged backup, tag-scoped forget, verify, dry-run restore. |
| `tests/test_restic_exporter.sh` (create) | Marker -> `restic_*` metric parsing. |
| `tests/test_install_units.sh`, `tests/test_schedule_ownership.sh` (modify) | Cover new timer names/paths; never assert removal of `spectre-backup-catchup`. |
| `tests/run_tests.sh` (modify) | Wire new restic/adopted tests. |
| `README.md`, `docs/RUNBOOKS.md` (modify) | One command surface/schedule/restore path. |
| `docs/migration/2026-11-06-absorb-spectre-backup.md` (create) | Cutover checklist, evidence, rollback, command mapping, archive gate. |

---

### Task 1: Make configuration artifacts readable by the restic user

**Files:**
- Modify: `scripts/backups/backup-configurations.sh`
- Create: `tests/test_backup_configurations_permissions.sh`
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: existing `backup-configurations.sh` behavior (`BACKUP_DIR`, `DATE`, `sudo` copies/tars).
- Produces: copied artifacts (`sshd_config_*`, `fail2ban_jail_*`, `dnf-automatic_*`) owned by the invoking user with mode `0640` (or `0600` owner-readable is acceptable if group unset; the requirement is *readable by the restic user when run as that user in the backup flow* — prefer `0640` + invoking user/group, but do not require root group changes; simplest: `install -m 0640 -o "$(id -u)" -g "$(id -g)"` via `sudo install`). Directories/tarballs keep existing behavior. Root-only sources are still read via `sudo`.

- [x] **Step 1: Write the failing test**

Create `tests/test_backup_configurations_permissions.sh` that runs in a temp tree: override `BACKUP_DIR`, stub `sudo` to copy from fixture files in `$TMP/etc/...` (or run the copy logic against a temp source by setting a test hook if you add one — prefer the smallest seam: make the script accept `SUDO_CMD=${SUDO_CMD:-sudo}` and test with `SUDO_CMD=` against readable fixtures), run the script for the `sshd_config`, `fail2ban_jail.local`, `dnf5-automatic.conf` copy lines' observable effect, and assert the copied files are readable by the current user (`test -r`) and not world-writable.

```bash
# core assertion shape (adapt to the seam you choose)
out="$BACKUP_DIR/sshd_config_$DATE"
[ -r "$out" ] || fail "copied sshd_config not readable by restic user"
stat -c '%a' "$out" | grep -Eq '^(600|640)$' || fail "copied sshd_config mode too open/odd: $(stat -c '%a' "$out")"
```

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_backup_configurations_permissions.sh`
Expected: FAIL because current script uses `sudo cp` and leaves root-owned/0600 artifacts unreadable in the real case (or fails the seam assertion).

- [x] **Step 3: Implement the minimal fix in `scripts/backups/backup-configurations.sh`**

Replace the three `sudo cp <src> <dest>` lines with `sudo install -m 0640 -o "$(id -u)" -g "$(id -g)" <src> <dest>` (guarded as today). Keep `sudo tar ...` and firewall redirect behavior unchanged. The artifact content is configuration, not a secret key; `0640` is readable by the backup flow's user and not world-readable. If `id -g` is undesirable, `-g "$(id -gn)"` is fine; do not chown to root.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_backup_configurations_permissions.sh`
Expected: PASS.

- [x] **Step 5: Wire and commit**

Add `test_backup_configurations_permissions.sh` to `tests/run_tests.sh` (its shell-test list/runner convention). Run: `bash tests/run_tests.sh` filtered to the new test if the runner supports it, else run the new test directly and a quick sanity of the runner.

```bash
git add scripts/backups/backup-configurations.sh tests/test_backup_configurations_permissions.sh tests/run_tests.sh
git commit -m "fix(backups): make copied config artifacts readable by restic user"
```

---

### Task 2: Add canonical restic config templates

**Files:**
- Create: `config/backups/restic/env.example`
- Create: `config/backups/restic/include.conf`
- Create: `config/backups/restic/exclude.conf`
- Create: `config/backups/restic/include-remote.conf`
- Create: `config/backups/restic/include-artifacts.conf`
- Test: `tests/test_restic_adopted.sh` (create in Task 3, but add a fast config-shape check now if convenient) — or keep config assertions in Task 3. Prefer one test file; start it in Task 3.

**Interfaces:**
- Consumes: spec §7.2/§7.3 exact scope and the deployed spectre-backup values (`~/.config/spectre-backup/.env`, include/exclude/include-remote) as the truth for preserved settings.
- Produces: templates that, when deployed, produce the scope in spec §7.3. `env.example` documents `RESTIC_CONFIG` deployment target `~/.secrets/spectre-suite-backups.env` and password `~/.secrets/spectre-restic-password`; it must **not** contain the real password.

- [x] **Step 1: Write the env template**

`config/backups/restic/env.example` preserves: `RESTIC_REPOSITORY=rclone:spectre-backup:`, `RESTIC_REPOSITORY_LOCAL=/backups/spectre-backup`, `RESTIC_PASSWORD_FILE=$HOME/.secrets/spectre-restic-password`, `LOG_DIR=$HOME/.local/state/spectre-suite/backups`, `PG_ENABLED=true`, `PG_HOST=/var/run/postgresql`, `PG_PORT=5432`, `PG_USER=deon`, `CONTAINERS_ENABLED=true`, `NOTIFY_ENABLED=true`, `NOTIFY_DESKTOP=true`, Drive pacing (`RCLONE_TPSLIMIT=20`, `RCLONE_TPSLIMIT_BURST=40`, `RCLONE_DRIVE_CHUNK_SIZE=64M`, `RCLONE_RETRIES=10`, `RCLONE_LOW_LEVEL_RETRIES=15`), `RESTIC_TAG=spectre-suite`, `RESTIC_HOST=$(hostname -s)` (or resolved at runtime; document). Add `# Copy to ~/.secrets/spectre-suite-backups.env (chmod 600). Never commit real credentials.`

- [x] **Step 2: Write `include.conf` (local, real paths only)**

Start from `spectre-backup/config/defaults/include.conf` semantics, then apply spec §7.3: keep dotfiles/ssh/gnupg/config/local-share/git-mirror; **remove** `~/archives`, `~/resources`, `~/downloads`, `~/Screenshots`; **add** `~/dev`, `~/docs`, `~/.secrets`, `~/archive/old-projects`, `~/archive/installers`, `~/archive/README.md`. Use `$HOME`-style or `~` consistently with the parser you adopt (Task 3) — pick one and stick to it; the adopted `build_targets` expands `~`. Comment the `~/code`/`~/documents`/`~/archives` symlink rationale.

- [x] **Step 3: Write `exclude.conf`**

Superset per spec: keep the proven excludes (`node_modules`, `.venv`, caches, VMs, `baloo`, `OptGuideOnDeviceModel`, VS Code cache, opencode state, `core.[0-9]*`, container storage) and add the suite-specific key/symlink guards:

```
$HOME/.config/spectre-backup
$HOME/.secrets/spectre-restic-password
$HOME/.secrets/restic-repo-password
$HOME/archive/backups
$HOME/archives
```

(`$HOME/archives` excludes the symlink entry; real archive content included is only the three explicit paths.)

- [x] **Step 4: Write `include-remote.conf` and `include-artifacts.conf`**

`include-remote.conf`: keep the small offsite set (ssh, gnupg, shell/git, systemd/nvim/Code User) and add `~/docs`. Do **not** add `~/.config/spectre-backup` or broad `~/.secrets`. Comment quota and deliberate omissions.

`include-artifacts.conf`: explicit globs, one per line, comments allowed:

```
/backups/databases/postgres_*.sql.gz
/backups/databases/redis_backup_*.rdb
/backups/docker-volumes/spectre-suite_*.tar.gz
/backups/configurations
/backups/projects
```

Never `/backups` alone.

- [x] **Step 5: Commit**

```bash
git add config/backups/restic
git commit -m "feat(backups): add canonical restic config templates"
```

---

### Task 3: Adopted restic library, markers, git mirror, and unit tests

**Files:**
- Create: `scripts/backups/restic/common.sh`
- Create: `scripts/backups/restic/git-mirror.sh`
- Create: `tests/test_restic_adopted.sh`
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: spectre-backup behavior (`lib/spectre-backup-common.sh`, `scripts/git-mirror.sh`) and the Task 2 config layout.
- Produces (stable names used by later tasks/tests):

```bash
resolve_restic_dirs        # sets CONFIG_DIR STATE_DIR BIN_DIR LOG_DIR DUMPS_DIR MARKER_DIR
load_restic_env            # sources RESTIC_CONFIG or ~/.secrets/spectre-suite-backups.env
build_targets <file> <out_array_name>   # expands ~/$HOME/globs? (see below), skips missing, dedups, rejects RESTIC_REPOSITORY_LOCAL
build_artifact_targets <file> <out_array_name>  # glob expansion for include-artifacts.conf
refuse_repo_path <path>    # fails if path resolves under RESTIC_REPOSITORY_LOCAL
restic_backup_args <repo>  # echoes/sets args including --tag spectre-suite --tag workstation --host
restic_forget_args <repo>  # echoes/sets args including --tag spectre-suite and the spec retention policy
write_marker <name> <value...>  # writes under $MARKER_DIR
read_marker_epoch <file>   # prints Unix seconds or 0
read_marker_field <file> <n>  # prints field n or empty (used for snapshot id)
```

Exact names may differ if the adopted code keeps its style, but Task 4–8 must use the same names; pin them when you write `common.sh` and update this interface block in the plan only if you must — prefer to keep these names.

- [x] **Step 1: Write the failing unit tests**

`tests/test_restic_adopted.sh` (shell, temp dirs, no real restic repo). Source `scripts/backups/restic/common.sh` with `RESTIC_REPOSITORY_LOCAL=/backups/spectre-backup`, `RESTIC_TAG=spectre-suite`, temp `CONFIG_DIR/STATE_DIR`. Assert:

```bash
# tag scoping (Review Focus 2)
args=$(restic_backup_args /tmp/repo)
[[ "$args" == *"--tag spectre-suite"* ]] && [[ "$args" == *"--tag workstation"* ]] || fail
fargs=$(restic_forget_args /tmp/repo)
[[ "$fargs" == *"--tag spectre-suite"* ]] || fail
[[ "$fargs" == *"--keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1"* ]] || fail

# repo-path refusal
build_targets "$fixture_include" t && fail "should refuse repo path"
# fixture_include contains /backups/spectre-backup/data

# real paths, no symlink duplication (Review Focus 3)
[[ " ${t[*]} " == *" $HOME/dev "* ]] || fail
[[ " ${t[*]} " != *" $HOME/code "* ]] || fail

# marker parse (spec §7.6)
echo "1730000000 abc123" > "$tmp/last-success"
[ "$(read_marker_epoch "$tmp/last-success")" = "1730000000" ] || fail
[ "$(read_marker_field "$tmp/last-success" 2)" = "abc123" ] || fail
echo "garbage" > "$tmp/bad"; [ "$(read_marker_epoch "$tmp/bad")" = "0" ] || fail
[ "$(read_marker_epoch "$tmp/missing")" = "0" ] || fail
```

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_restic_adopted.sh`
Expected: FAIL (`common.sh` missing / functions undefined).

- [x] **Step 3: Implement `common.sh`**

Copy `spectre-backup/lib/spectre-backup-common.sh` as the base and adapt:
- config/state defaults to `~/.config/spectre-suite/backups` and `~/.local/state/spectre-suite/backups` (overrideable by env / test); env file default `~/.secrets/spectre-suite-backups.env`; `MARKER_DIR=$STATE_DIR` (markers live in state root per spec).
- `build_targets`: keep comment/`~` expansion and missing-path warnings; add dedup (seen set) and **reject** any resolved path equal to or under `$RESTIC_REPOSITORY_LOCAL` (realpath when available; string-prefix fallback for non-existent repo path). Preserve missing-path=skip behavior (warn).
- `build_artifact_targets`: expands globs (`shopt -s nullglob`), collects existing matches, dedups, rejects repo path.
- `restic_backup_args`/`restic_forget_args`: return the exact tag/host/retention values. Never omit `--tag spectre-suite` from forget.
- marker helpers: `write_marker name epoch [id]` atomic-ish (`tmp && mv`), `read_marker_epoch` => first numeric token else `0`, `read_marker_field` by awk field number.
- keep distro/logging helpers used by the engine; remove or isolate installer-only code not needed at runtime.

- [x] **Step 4: Adopt `git-mirror.sh`**

Copy `spectre-backup/scripts/git-mirror.sh` to `scripts/backups/restic/git-mirror.sh`, `chmod +x`. Keep behavior (mirror history, not worktrees; safe repeated runs). Only adjust `--help`/version text to reference the suite path if present; do not change semantics. It must run before local backup and be local-only in effect (it writes under `~/.git-mirror`, which is in the local include).

- [x] **Step 5: Run tests to verify they pass**

Run: `bash tests/test_restic_adopted.sh`
Expected: PASS.

- [x] **Step 6: Wire and commit**

Add `test_restic_adopted.sh` to `tests/run_tests.sh`. Run it.

```bash
git add scripts/backups/restic/common.sh scripts/backups/restic/git-mirror.sh tests/test_restic_adopted.sh tests/run_tests.sh
git commit -m "feat(backups): adopt restic library, markers, and git mirror"
```

---

### Task 4: Adopt the backup flow (local, offsite-degraded, markers)

**Files:**
- Create: `scripts/backups/restic/backup.sh`
- Create: `tests/test_restic_integration.sh`
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: `common.sh`, `git-mirror.sh`, config files, `restic`, `rclone`, `pg_dumpall`/`psql` (optional), Podman/Docker config collection logic from spectre-backup.
- Produces: a `backup.sh` entrypoint with the spectre-backup flag surface needed by the suite (`--help`, `--version`/equivalent if present, `--health` passthrough or delegated behavior, quiet/debug flags the adopted engine supports) **and** suite defaults. It writes markers: `last-attempt` at start; `last-success` `<ts> <id>` after local success; `last-offsite-success` after offsite success; `last-health` `<0|1> <ts>` on completed run (degraded => 0 per spec's ok=1-only metric? follow spec: "restic_health_ok is 1 only for exit 0; it is 0 for exit 1 (failed) or 2 (degraded)"). Offsite failure: log + notify if configured, keep local success, exit 0 (healthy local) or 2 (degraded) — choose one and make the marker/metric rule consistent; spec says degraded => `health_ok 0` and `ResticHealthFailed` warns: so exit 2, `last-health` records failure-grade for the ok metric, but `last-success` remains. Document the choice in a comment.

- [x] **Step 1: Write the failing integration test (skips without restic)**

`tests/test_restic_integration.sh`: if `! command -v restic`; then `echo "SKIP: restic not installed"; exit 0`; fi. Create a temp repo, password file, state/config dirs, fixture home+artifact tree, and a minimal include/exclude. Run `backup.sh` in a mode that targets only the temp local repo and skips offsite/pg/containers/git-mirror as supported by env/flags (add env overrides: `RESTIC_SKIP_OFFSITE=1`, `RESTIC_SKIP_PG=1`, `RESTIC_SKIP_CONTAINERS=1`, `RESTIC_SKIP_GIT_MIRROR=1`, `INCLUDE_FILE=...` — implement in step 3). Assert local snapshot exists with tag `spectre-suite`, `last-attempt` and `last-success` exist, `read_marker_epoch last-success > 0`.

Add a **degraded-offsite** subtest (Review Focus 4): set `RESTIC_REPOSITORY=rclone:nonexistent-remote-that-will-fail:` (or force offsite command to fail via a test hook like `RCLONE_CMD=false`) with a valid local repo; expect exit 0 or 2 per your chosen contract, `last-success` present, `last-offsite-success` absent/unchanged, and `last-health` reflects degraded.

```bash
RCLONE_CMD=false RESTIC_SKIP_OFFSITE=0 ... bash "$BACKUP" && status=0 || status=$?
[ -f "$STATE/last-success" ] || fail "local success missing after offsite failure"
[ ! -f "$STATE/last-offsite-success" ] || [ "$(read_marker_epoch "$STATE/last-offsite-success")" = "0" ] || fail "offsite should not succeed"
```

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_restic_integration.sh`
Expected: FAIL (missing `backup.sh`) or SKIP if restic absent — confirm it runs.

- [x] **Step 3: Implement `backup.sh`**

Copy `spectre-backup/scripts/spectre-backup.sh` and adapt to suite contracts:
- source `common.sh` from `scripts/backups/restic/`; set suite config/state defaults; load `~/.secrets/spectre-suite-backups.env`.
- preserve the deployed-value defaults from spec §7.2 and Task 2.
- step 1: run `git-mirror.sh` unless `RESTIC_SKIP_GIT_MIRROR=1`.
- step 2: host `pg_dumpall` into `$DUMPS_DIR` when `PG_ENABLED=true` and not skipped; socket/user from env; failure is warn+degraded (does not silently claim full coverage — but do not drop the container population; they are independent).
- step 3: Podman/Docker config copy into `$DUMPS_DIR` with ownership fix applied to any copied files (match Task 1 principle).
- step 4: build local targets = `include.conf` existing paths + `include-artifacts.conf` expanded globs + `$DUMPS_DIR` (if present); build offsite targets = `include-remote.conf` + `/backups/databases` + `$DUMPS_DIR` when present. Apply `refuse_repo_path`/`build_targets` guards.
- step 5: local `restic backup` with `restic_backup_args` (includes both tags + host).
- step 6: offsite `restic backup` with same tags; wrap in a function that captures failure, sets `offsite_ok=false`, does **not** exit.
- step 7: tag-scoped `restic forget $(restic_forget_args) --prune` per repository that succeeded the backup step (or per configured repo; never forget without tag).
- step 8: `write_marker last-attempt` at start; on local success write `last-success <ts> <snapshot-id>` (obtain id via `restic snapshots -r <repo> --latest 1 --json`/`--tag spectre-suite --host` and `jq -r '.[0].short_id // .[0].id'`); write `last-offsite-success` only on offsite success; run/write health verdict. Exit 0 if local ok and not degraded, 2 if local ok but offsite degraded (or per your consistent contract), 1 if local failed.
- add `RCLONE_CMD=${RCLONE_CMD:-rclone}` / command hooks only where needed for tests; no behavior change in production.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_restic_integration.sh` (and `bash tests/test_restic_adopted.sh`)
Expected: PASS or SKIP(restic absent) for integration; PASS for unit.

- [x] **Step 5: Commit**

```bash
git add scripts/backups/restic/backup.sh tests/test_restic_integration.sh tests/run_tests.sh
git commit -m "feat(backups): adopt restic backup flow with tag scoping and degraded offsite"
```

---

### Task 5: Adopt prune, verify, and restore wrappers

**Files:**
- Create: `scripts/backups/restic/prune.sh`
- Create: `scripts/backups/restic/verify.sh`
- Create: `scripts/backups/restic/restore.sh`
- Modify: `tests/test_restic_adopted.sh` (arg parsing / required tag presence)
- Modify: `tests/test_restic_integration.sh` (verify + dry-run restore)

**Interfaces:**
- Consumes: `common.sh`, `restic`.
- Produces:
  - `prune.sh [--dry-run] [--repo <local|offsite|all>]` (or keep spectre-backup flags and map; document). Always passes `--tag spectre-suite` to `forget`. Uses spec retention policy. No unscoped prune of snapshots.
  - `verify.sh [--full]` runs quick check by default, `restic check --read-data-subset`/full equivalent per adopted behavior; on completion writes `last-verify <0|1> <ts>` (1 = ok, 0 = failed). The first real write is the cutover rehearsal — that is fine.
  - `restore.sh --list | --snapshot <id> [--dry-run] [--target <dir>] [--local]` preserves the adopted interface (spec §7.7). Defaults to local repo.

- [x] **Step 1: Write failing tests**

Extend unit tests: invoking the wrappers with a stubbed `restic` (a temp executable earlier in PATH that records args) proves `forget` always receives `--tag spectre-suite` and never runs without it; `restore --list/--snapshot/--dry-run/--target/--local` parses. Extend integration: after the tagged backup, `verify.sh` exits 0 and writes `last-verify`; `restore.sh --snapshot <id> --dry-run` exits 0.

- [x] **Step 2: Run to verify failure**

Run: `bash tests/test_restic_adopted.sh && bash tests/test_restic_integration.sh`
Expected: FAIL for new wrapper cases.

- [x] **Step 3: Implement wrappers**

Copy/adapt from `spectre-backup/scripts/spectre-backup-{prune,verify,restore}.sh`. Repoint config/state/markers to `common.sh`. Ensure `prune.sh` cannot forget untagged snapshots. Ensure `verify.sh` records `last-verify`. Keep `restore.sh` safe defaults (explicit target for real restores; dry-run support).

- [x] **Step 4: Run to verify pass**

Run: `bash tests/test_restic_adopted.sh && bash tests/test_restic_integration.sh`
Expected: PASS/SKIP as appropriate.

- [x] **Step 5: Commit**

```bash
git add scripts/backups/restic/prune.sh scripts/backups/restic/verify.sh scripts/backups/restic/restore.sh tests/test_restic_adopted.sh tests/test_restic_integration.sh
git commit -m "feat(backups): adopt tag-scoped prune, verify, and restore wrappers"
```

---

### Task 6: Export restic marker metrics and alert rules

**Files:**
- Modify: `prometheus/business-metrics-exporter.sh`
- Modify: `prometheus/alert_rules.yml`
- Create: `tests/test_restic_exporter.sh`
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: markers under `${RESTIC_MARKER_DIR:-$HOME/.local/state/spectre-suite/backups}` (also accept the historical `~//...` form via a variable for tests).
- Produces: gauges with the exact names from spec §7.6:

```
restic_last_attempt_timestamp
restic_last_success_timestamp
restic_last_offsite_success_timestamp
restic_health_ok
restic_health_timestamp
restic_verify_ok
restic_verify_timestamp
```

Missing/empty/unparseable => `0` (log parse failure to stderr, do not break the exporter). Keep existing `backup_repo_*` and existing backup artifact metrics/behavior unchanged.

Alert names/expr/for/labels exactly as spec §7.6: `ResticBackupMissing`, `ResticBackupStale`, `ResticOffsiteMissing`, `ResticOffsiteStale`, `ResticHealthFailed`, `ResticVerifyFailed`, `ResticVerifyStale`. Keep `BackupStale` and `BackupHealthCheckFailed`.

- [x] **Step 1: Write the failing exporter test**

`tests/test_restic_exporter.sh`: create temp marker dir with `last-success="1730000000 deadbeef"`, missing `last-offsite-success`, `last-health="0 1730000100"`, `last-verify="garbage"`; run the exporter pointed at the temp dir and output file (`BACKUP_REPO_DIR` can point to a temp dir that exists to avoid side effects); grep the output:

```bash
grep -qx 'restic_last_success_timestamp 1730000000' "$out"
grep -qx 'restic_last_offsite_success_timestamp 0' "$out"
grep -qx 'restic_health_ok 0' "$out"
grep -qx 'restic_verify_timestamp 0' "$out"
```

- [x] **Step 2: Run to verify failure**

Run: `bash tests/test_restic_exporter.sh`
Expected: FAIL (metrics absent).

- [x] **Step 3: Implement exporter + alerts**

In `business-metrics-exporter.sh`, add a `read_marker_epoch`-equivalent (or reuse its existing numeric parsing style) for the restic marker dir and emit the seven gauges with `# HELP`/`# TYPE`. Use `RESTIC_MARKER_DIR` env override for tests; default to the user's state dir as the script resolves it (the exporter runs in cron/user context on this host — check existing style; do not hardcode `/root`).

In `alert_rules.yml`, append the restic rules under the backup group (or a clearly named group consistent with the file). Copy the expressions from the spec verbatim where possible.

- [x] **Step 4: Run to verify pass**

Run: `bash tests/test_restic_exporter.sh`
Run: `bash tests/test_security_metrics.sh` or the repo's promtool/metrics tests if they validate alert syntax (use whatever `tests/run_tests.sh`/CI uses); if `promtool` is unavailable, `python -c "import yaml,sys; yaml.safe_load(open('prometheus/alert_rules.yml'))"` is a minimum.

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add prometheus/business-metrics-exporter.sh prometheus/alert_rules.yml tests/test_restic_exporter.sh tests/run_tests.sh
git commit -m "feat(monitoring): export restic markers and add restic alerts"
```

---

### Task 7: Installers, install.sh integration, and retirement of the old suite restic path

**Files:**
- Rewrite: `scripts/systemd/install-restic-timer.sh`
- Create: `scripts/systemd/install-restic-verify-timer.sh`
- Modify: `install.sh`
- Delete: `scripts/backups/restic-backup.sh`, `scripts/backups/restic-maintenance.sh`, `scripts/backups/restic-forget-prune.sh`, `scripts/backups/restic.env.example`, `scripts/systemd/install-restic-maintenance-timer.sh`
- Modify: `tests/test_install_units.sh`, `tests/test_schedule_ownership.sh`, `tests/run_tests.sh`

**Interfaces:**
- Consumes: `scripts/backups/restic/backup.sh` and `verify.sh`.
- Produces:
  - `install-restic-timer.sh [--print|--uninstall]`: installs `spectre-restic-backup.service/timer` as a **user** unit. `OnCalendar=*-*-* 04:10:00`, `Persistent=true`, `RandomizedDelaySec` small (e.g. 10m), `ExecStart` runs `scripts/backups/restic/backup.sh`, `WorkingDirectory` repo root, `RESTIC_CONFIG` default `~/.secrets/spectre-suite-backups.env`. `--print` emits units; `--uninstall` disables/removes only these two units.
  - `install-restic-verify-timer.sh [--print|--uninstall]`: weekly `spectre-restic-verify.service/timer` (pick a stable calendar, e.g. `Sun *-*-* 05:30:00`, after the 05:00 catch-up; `Persistent=true`), runs `verify.sh` (quick). Never touches `spectre-backup-catchup`.
  - `install.sh` installs `scripts/backups/restic/*.sh` with mode 0755 to a deliberate location (same `/usr/local/bin` convention only if the scripts are safe to run flat; `backup.sh` sources `common.sh` by relative path, so flat install breaks — therefore **do not** flat-copy the restic subdir. Install the directory or invoke from repo/user path; update the installer/test accordingly and document). Pick the least surprising option: keep restic engine repo-relative/user-installed and ensure the timer `ExecStart` points at the absolute script path (the current pattern already does this).

- [x] **Step 1: Write/adjust failing tests**

Update `test_install_units.sh` / `test_schedule_ownership.sh` to assert: backup timer is 04:10 and runs `scripts/backups/restic/backup.sh`; verify timer runs `verify.sh`; `spectre-backup-catchup` is still referenced/owned by the suite and not removed (Review Focus adjacency — protect the catch-up). Remove assertions for deleted `restic-maintenance` units. Run to confirm failure.

- [x] **Step 2: Implement installers and update install.sh**

Rewrite `install-restic-timer.sh` (replace the old stub that pointed at `restic-backup.sh`). Add `install-restic-verify-timer.sh`. In `install.sh`, replace any blind restic assumptions: do not copy `scripts/backups/restic/*.sh` flat unless you also install the library adjacency; the safe change is to leave the engine in place and let the user timer reference absolute paths (and/or document). Keep non-restic backup script installs working.

- [x] **Step 3: Delete retired files**

`git rm` the five retired files listed above. Confirm no remaining references except the migration doc/plan/spec history:

Run: `grep -rn 'restic-backup\.sh\|restic-maintenance\.sh\|restic-forget-prune\.sh\|install-restic-maintenance-timer\|restic\.env\.example' scripts tests install.sh README.md docs .github 2>/dev/null` (allow hits in `docs/superpowers/specs/*` and this plan and the migration doc).

- [x] **Step 4: Run tests**

Run: `bash tests/test_install_units.sh && bash tests/test_schedule_ownership.sh && bash tests/test_restic_adopted.sh`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add scripts/systemd/install-restic-timer.sh scripts/systemd/install-restic-verify-timer.sh install.sh tests/test_install_units.sh tests/test_schedule_ownership.sh tests/run_tests.sh
git rm scripts/backups/restic-backup.sh scripts/backups/restic-maintenance.sh scripts/backups/restic-forget-prune.sh scripts/backups/restic.env.example scripts/systemd/install-restic-maintenance-timer.sh
git commit -m "feat(backups): install adopted restic timers and retire suite restic stubs"
```

---

### Task 8: Documentation, runbook, and migration/cutover record

**Files:**
- Modify: `README.md`
- Modify: `docs/RUNBOOKS.md`
- Create: `docs/migration/2026-11-06-absorb-spectre-backup.md`

**Interfaces:**
- Consumes: the spec, the implemented command/marker/timer names, and the real cutover steps (Task 9 executes them; this task writes the checklist to follow).
- Produces: operator-facing docs with one command surface, one schedule, two restore paths clearly separated (restic snapshot restore vs artifact restore), the legacy `/backups/spectre-backup` name, grandfathered snapshots, and the §8.1 parity checklist + archive gate.

- [x] **Step 1: Write the migration doc**

`docs/migration/2026-11-06-absorb-spectre-backup.md` must include: baseline commands, the exact cutover sequence from spec §8.3, verification evidence template (snapshot id, `verify` output, restored files compared, `restic ls <id>` showing no password), rollback, retired units/paths, command mapping (old `~/.local/bin/spectre-backup*.sh` / suite `restic-*.sh` -> `scripts/backups/restic/*.sh`), §8.1 checklist, home-backup retirement, catch-up timer kept, and the conditional GitHub archive (do not archive if any machine still needs the server role).

- [x] **Step 2: Update README and runbook**

README backup section: daily 04:10 restic snapshot (home+artifacts+host dump+container configs) to local `/backups/spectre-backup` + Drive offsite, tag-scoped retention, weekly verify, 05:00 artifact catch-up unchanged. Document `scripts/backups/restic/{backup,verify,restore,prune}.sh` and the user timer installers. Runbook 4: split "restore an artifact" vs "restore from a restic snapshot"; include `--list`, `--dry-run`, `--target /tmp/restore-test`, and the marker/alert names.

- [x] **Step 3: Verify references**

Run: `bash scripts/check-docs-references.sh` if present and cheap; otherwise `grep -n 'restic-backup\.sh\|scripts/backups/restic-backup\.sh' README.md docs/RUNBOOKS.md` returns no stale command references (migration doc may mention old names in the mapping table — that is fine).

- [x] **Step 4: Commit**

```bash
git add README.md docs/RUNBOOKS.md docs/migration/2026-11-06-absorb-spectre-backup.md
git commit -m "docs(backups): document adopted restic engine, cutover, and restore paths"
```

---

### Task 9: Cutover rehearsal and retirement (operator steps, evidence recorded)

**Files:**
- Modify: `docs/migration/2026-11-06-absorb-spectre-backup.md` (append evidence)

**Interfaces:**
- Consumes: the implemented engine, real host config, `/backups/spectre-backup`, `rclone:spectre-backup:`, `~/.config/spectre-backup/password`.
- Produces: a verified `spectre-suite,workstation` snapshot containing home paths, `~/dev`, `~/docs`, `~/.secrets` (minus excluded keys), `~/archive/old-projects`, artifact globs, the host dump, and container config copies; `verify` pass; restore rehearsal from `~/dev`, `~/docs`, `~/.secrets`, one artifact, one host dump to `/tmp` compared; `restic ls` proves the repo key absent (Review Focus 1). Only after that: disable `home-backup.timer` (keep files), enable the new timers, confirm metrics.

**This task touches live timers and the real backup config. Do each mutating step deliberately and record output. Stop on any failure.**

- [x] **Step 1: Baseline**

Record `restic snapshots --repo /backups/spectre-backup` (and offsite), `systemctl --user list-timers --all | grep -E 'backup|restic|spectre'`, checksums of `~/.config/spectre-backup/*` and the relevant unit files, and free space. Append to the migration doc evidence section.

- [x] **Step 2: Install canonical config and password copy (no production switch yet)**

Create `~/.config/spectre-suite/backups/` and `~/.local/state/spectre-suite/backups/`. Deploy templates, then overlay the preserved live values (or copy from `~/.config/spectre-backup/.env` with the new paths/names). `install -m 600` the env file. Copy the key: `install -m 600 ~/.config/spectre-backup/password ~/.secrets/spectre-restic-password`. Prove: `RESTIC_PASSWORD_FILE=~/.secrets/spectre-restic-password restic -r /backups/spectre-backup snapshots --compact`. Keep the old password copy.

- [x] **Step 3: Disable `spectre-backup.timer` only (preserve rollback)**

`systemctl --user disable --now spectre-backup.timer` (do not delete units). Leave `spectre-backup-catchup.timer` running. Record state.

- [x] **Step 4: Run the first adopted backup manually**

Run `scripts/backups/restic/backup.sh` (foreground, log captured). Confirm exit status, `last-success`/`last-offsite-success`/`last-health` markers, and `restic snapshots --latest 1 --json` shows tags `spectre-suite,workstation`. Confirm `restic ls <id>` contains `home/deon/dev`, `home/deon/docs`, `home/deon/.secrets` (allowed files), `home/deon/archive/old-projects`, the dump dir, and artifact paths, and does **not** contain `spectre-restic-password`, `restic-repo-password`, or `.config/spectre-backup/password`.

- [x] **Step 5: Verify and rehearse restore**

Run `verify.sh`. Then `restore.sh --snapshot <id> --dry-run`. Restore to `/tmp/spectre-restore-rehearsal/<ts>/`: one file from `~/dev`, one from `~/docs`, one non-key file from `~/.secrets`, one artifact, one host dump. `diff`/`cmp`/`sha256sum` against originals. Record all commands and results.

- [x] **Step 6: Retire home-backup timer (files kept)**

Only if Step 5 passed: `systemctl --user disable --now home-backup.timer`. Do not delete `~/.local/bin/backup-home` or `~/archive/backups` yet.

- [x] **Step 7: Enable the new timers and confirm metrics**

Run the suite's `install-restic-timer.sh` and `install-restic-verify-timer.sh`. Confirm `systemctl --user list-timers`. Run the exporter (or wait for cron) and confirm the `restic_*` metrics and repo size/free metrics render; confirm alert rules load.

- [x] **Step 8: Record evidence and stop**

Append the snapshot id, marker contents, restore diffs, timer state, and metric sample to the migration doc. Do **not** archive the spectre-backup repo, do **not** delete old configs/units/scripts, and do **not** delete `~/archive/backups` — those wait for §8.1 + seven consecutive green days and, for the archive, confirmation that no machine needs the server role.

```bash
git add docs/migration/2026-11-06-absorb-spectre-backup.md
git commit -m "docs(backups): record restic absorption cutover rehearsal evidence"
```

## Self-Review

**1. Spec coverage:** §1-5 intent/goals/non-goals/anti-goals — Tasks 1-9 + Global Constraints. §7.1 layout — File Map. §7.2 config/secrets — Task 2,3,9. §7.3 scope incl. real paths/symlink fix/offsite docs — Task 2,3,4. §7.4 flow + degraded offsite — Task 4. §7.5 schedule — Task 7,9; catch-up protected. §7.6 markers/metrics/alerts — Task 3,4,6. §7.7 restore/verify — Task 5,9. §7.8 tests — Tasks 1,3-6. §7.9 docs — Task 8. §8 cutover/parity/archive gate/home-backup/catch-up — Tasks 7-9. §9 decisions — Global Constraints + Task 8/9. No spec requirement is without a task.

**2. Step scan:** Implementation steps give signatures, exact values, files, and commands; bodies are left to the implementer except where the spec pins values (tags, retention, markers, metrics, alert exprs, paths). Verification steps have commands and expected outcomes. No "TBD"/"handle edge cases" steps. Task 9 is operator-executed and evidence-driven, not a code transcript.

**3. Type consistency:** `restic_backup_args`/`restic_forget_args`/`build_targets`/`build_artifact_targets`/marker helpers are defined in Task 3 and reused by 4,5,6. Marker names and metric names match spec §7.6 exactly. Config/state paths are consistent across tasks.

**4. Review Focus:** (1) key in snapshot — Task 3 excludes, Task 9 `restic ls` asserts absence. (2) unscoped forget — Task 3 unit test + Task 5 wrapper test. (3) `~/archives` symlink — Task 2 real paths + Task 3 fixture. (4) offsite fails whole run — Task 4 degraded subtest. (5) unreadable config artifacts — Task 1. All five have owning tasks.

**5. Proportion:** Plan states decisions, interfaces, exact values, and checks; the adopted engine bodies remain in `~//dev/github/spectre-backup` to copy/adapt, not transcribed here.
