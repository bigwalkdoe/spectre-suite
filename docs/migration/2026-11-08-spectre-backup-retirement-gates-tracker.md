# spectre-backup Retirement Gates Tracker (evidence, non-destructive)

**Date:** 2026-11-08  
**Scope:** Workstation cutover gates per `2026-11-06-absorb-spectre-backup-design.md` §8.1/§8.3 and migration record. **No GitHub archive and no retirement-gated deletions performed.** Local clone moved to `~/archive/superseded/spectre-backup-2026-11-08/` (`.git` preserved) as a local-only archival step (reversible).

## Gate status
| Gate | Required | Status (2026-11-09 read-only recheck) | Evidence |
|---|---|---|---|
| §8.1 parity checklist | All rows true on this workstation | **Mostly evidenced; some items not re-proven live** (notifications test, fresh restore rehearsal, live offsite `restic snapshots` without sourcing secrets, forget dry-run) | Markers healthy (`last-success`, `last-offsite-success`, `last-health=1`, `last-verify=1` present in `~/.local/state/spectre-suite/backups/`); timers enabled; `/backups/spectre-backup` exists. No secrets accessed; no restic commands run. |
| 7 consecutive green days | After cutover before deleting retired configs/units/scripts | **NOT SATISFIED** (progress: 3 restic backup-success days observed post-cutover; catchup recovered 2026-11-09) | Cutover validated 2026-11-06. `spectre-restic-backup.service` **success** (exit 0) observed **2026-11-07 04:24:46 PKT**, **2026-11-08 04:15:47 PKT**, **2026-11-09 04:21:48 PKT**. `spectre-restic-verify.service` success 2026-11-08 05:35:24 PKT. **Catchup failures (2026-11-07/08, investigated 2026-11-09, read-only):** legacy `check-backup-health` checks the newest `spectre-suite_*.tar.gz`; at those run times the newest redis volume archive was `/backups/docker-volumes/spectre-suite_redis-data_20261106_030000.tar.gz` (2026-11-06 03:02, 270B, 26h/50h old), so health failed age despite newer restic backups. Newer redis volume archives now exist (2026-11-08/09, incl. 2026-11-09 10:55/11:00), and catchup **succeeded** 2026-11-09 05:03:16 PKT. The 2026-11-06 file is no longer the active newest-age failure; it remains old history (optional cleanup only, host-mutating if removed). 2026-11-07/08 are not clean “green days” for catchup/legacy-health. |
| No machine needs server role | Before GitHub archive | **NOT CONFIRMED** | Cannot be confirmed from this host alone; requires operator/org confirmation. |
| Explicit confirmation | Before remote archive / destructive gated deletions | **NOT PROVIDED** | User must explicitly confirm all gates satisfied. |

## Current host evidence (2026-11-09, read-only)
- Timers (user): `spectre-restic-backup.timer` **enabled** (last 2026-11-09 04:16:35 PKT, next 2026-11-10 04:15:45 PKT), `spectre-restic-verify.timer` **enabled** (last 2026-11-08 05:35:20 PKT, next 2026-11-15 05:33:53 PKT), `spectre-backup-catchup.timer` **enabled** (last 2026-11-09 05:02:35 PKT, next 2026-11-10 05:09:19 PKT); `spectre-backup.timer`/`home-backup.timer` **disabled**.
- Service outcomes (journal, since 2026-11-06): restic backup **success** 2026-11-07/08/09 (exit 0); restic verify **success** 2026-11-08 05:35:24 PKT (exit 0); catchup **failed exit-code** 2026-11-07/08 despite "ok" backup-age lines, **success** 2026-11-09 05:03:16 PKT (exit 0).
- Markers: `last-attempt`, `last-success` (snapshot `5a8836ff`), `last-offsite-success`, `last-health=1`, `last-verify=1` present in `~/.local/state/spectre-suite/backups/`.
- Local repo path: `/backups/spectre-backup` exists (no restic commands run; no secrets accessed). GitHub archive status not rechecked.

## Safe next actions
- **Now (read-only):** continue collecting green-day evidence (catchup recovered 2026-11-09; 2026-11-07/08 catchup/legacy-health were not clean). Optional: archive/remove `/backups/docker-volumes/spectre-suite_redis-data_20261106_030000.tar.gz` as old history only if you want (not an active health blocker now) — **explicit approval required** (host-mutating). Re-run targeted §8.1 proofs only with explicit approval as needed (notification test, restore rehearsal sample, offsite listing with care, tag-scoped forget dry-run).
- **After explicit gate confirmation only:** archive GitHub repo (reversible) and execute planned local retirement steps (confirm each destructive step; keep `~/archive/backups` and restic data untouched; never touch `spectre-backup-catchup` except explicit instruction).
