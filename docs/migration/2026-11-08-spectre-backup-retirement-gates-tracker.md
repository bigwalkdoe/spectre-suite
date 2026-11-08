# spectre-backup Retirement Gates Tracker (evidence, non-destructive)

**Date:** 2026-11-08  
**Scope:** Workstation cutover gates per `2026-11-06-absorb-spectre-backup-design.md` §8.1/§8.3 and migration record. **No GitHub archive and no retirement-gated deletions performed.** Local clone moved to `~/archive/superseded/spectre-backup-2026-11-08/` (`.git` preserved) as a local-only archival step (reversible).

## Gate status
| Gate | Required | Status (2026-11-08) | Evidence |
|---|---|---|---|
| §8.1 parity checklist | All rows true on this workstation | **Mostly evidenced; some items not re-proven live** (notifications test, fresh restore rehearsal, live offsite `restic snapshots` without sourcing secrets, forget dry-run) | See §8.1 checklist response/migration evidence; markers healthy; timers enabled; local restic snapshot `5a8836ff` present. |
| 7 consecutive green days | After cutover before deleting retired configs/units/scripts | **NOT SATISFIED** | Cutover validated 2026-11-06; `spectre-restic-backup` successes observed 2026-11-07, 2026-11-08 (journal/markers). Re-check when 7 consecutive days are green. |
| No machine needs server role | Before GitHub archive | **NOT CONFIRMED** | Cannot be confirmed from this host alone; requires operator/org confirmation. |
| Explicit confirmation | Before remote archive / destructive gated deletions | **NOT PROVIDED** | User must explicitly confirm all gates satisfied. |

## Current host evidence (2026-11-08)
- Timers: `spectre-restic-backup.timer` **enabled** (success 2026-11-08), `spectre-restic-verify.timer` **enabled**, `spectre-backup-catchup.timer` **enabled**; `spectre-backup.timer`/`home-backup.timer` **disabled**.
- Markers: `last-success`/`last-offsite-success` recent, `last-health=1`, `last-verify=1` (see state dir `~/.local/state/spectre-suite/backups/`).
- Local repo: `/backups/spectre-backup` contains adopted snapshot `5a8836ff` (`spectre-suite,workstation`) via `restic snapshots` with password file (read-only check; no secrets printed).
- GitHub: `bigwalkdoe/spectre-backup` **not archived** (`isArchived:false`).

## Safe next actions
- **Now:** continue collecting green-day evidence; re-run targeted §8.1 proofs (notification test, restore rehearsal sample, offsite listing with care, tag-scoped forget dry-run).
- **After explicit gate confirmation only:** archive GitHub repo (reversible) and execute planned local retirement steps (confirm each destructive step; keep `~/archive/backups` and restic data untouched; never touch `spectre-backup-catchup` except explicit instruction).
