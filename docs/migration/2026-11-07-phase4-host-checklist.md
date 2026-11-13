# Phase 4 Host/Ops Checklist (post-C1 repo cleanup)

**Date:** 2026-11-07  
**Context:** C1 (tracked legacy `scripts/` removal) complete on `main` (`4c211c9` lineage, CI green; guardrail `fe2e851`); `spectre/policies/` is a real canonical directory. This checklist covers **spec §8.4 Phase 4** items that are **host/ops/external** (not fully satisfied by repo-only changes).

**Spec ref:** `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` §8.4 Phase 4 — *“Remove shims; delete `/home/deon/scripts`; archive the agent repo read-only — done when no path outside the repo is referenced.”*

## Preconditions
- [x] On the target host, confirm `spectre` CLI/dispatch is installed and working: `spectre actions list`, `spectre actions verify` (expect 0 legacy-path findings where applicable). **Fedora 2026-11-07:** 67 jobs, `actions verify` no findings.
- [x] Confirm schedulers (cron, system/user timers) invoke `spectre run <job>` or approved canonical entrypoints — no repo `scripts/` paths, no `/home/deon/scripts`. **Fedora 2026-11-07 (active schedulers checked):** crontab uses `/usr/local/bin/spectre run ...`; `performance-check.service`/`security-scan.service` use `spectre run`; no legacy scheduler refs found in `/etc/systemd/system`, `~/.config/systemd/user`, readable cron dirs. Caveat: stale `/usr/local/bin` artifacts contain legacy refs (see §1.17) but no active references found.
- [ ] Have rollback/host access appropriate for scheduler and filesystem changes. (Operational — not verified in-session.)

## Checklist

### 1) In-repo shims / legacy `scripts/` (repo-side, C1)
- [x] Tracked legacy `scripts/` tree removed from repo (`git ls-files scripts` = 0); active refs rewired; CI guardrail blocks tracked reintroduction.
- [ ] Verify no deployed/installed artifacts on the host still reference repo `scripts/` paths (generated units, copied scripts under `/usr/local/bin` or elsewhere, local wrappers). Use `rg` on host config locations as appropriate; `spectre actions verify`/dispatcher checks where available. **Fedora 2026-11-07: NOT fully satisfied (cross-repo ownership caveat).** Active schedulers/units checked use `spectre run` (crontab, `performance-check.service`, `security-scan.service`), but `rg` found `/usr/local/bin` artifacts with `/home/deon/scripts/...` references (e.g. `check-performance-wrapper.sh` → missing target; `setup-*`/`run-*`/`container-logrotate.sh`/`centralized-log-shipper.sh`). **Ownership:** matching filenames exist in separate repo `/home/deon/dev/github/spectre-security` (e.g. `security/run-trivy-scan.sh`, `security/setup-security-scanning.sh`, `performance/check-performance-wrapper.sh`, `setup-backup-cron.sh`), but sampled `/usr/local/bin` hashes **differ** from current `spectre-security` copies — likely installed from `spectre-security`/older state, **not** from `spectre-suite`. No active scheduler refs found in `/etc/systemd/system`, readable `/etc/cron*`, or `~/.config/systemd/user`; `/var/spool/cron` unreadable. **Handle as `spectre-security`/host coordination, not blind spectre-suite Phase 4 deletion.** Requires explicit confirmation; coordinate whether `spectre-security` is superseded/should stop installing legacy `/home/deon/scripts` paths.

### 2) Delete `/home/deon/scripts` (host)
- [x] Confirm `/home/deon/scripts` is absent **or** contains no live, scheduler-referenced, or PATH-installed operational scripts. (Reference host noted absent in earlier migration context; do not assume.) **Fedora 2026-11-07:** `test ! -e /home/deon/scripts` → absent.
  ```bash
  test ! -e /home/deon/scripts && echo "absent" || find /home/deon/scripts -maxdepth 3 | head
  ```
- [x] If present and unused after verification, remove/archive per ops policy (confirm no `ConditionPathExists`, no cron/systemd/user-timer, no `/usr/local/*` wrapper depends on it). **N/A — `/home/deon/scripts` absent on this host (2026-11-07).** Note: legacy `/usr/local/bin` files still *contain* `/home/deon/scripts` references (see §1.17); they do not make `/home/deon/scripts` present, but they are stale/risky artifacts.
- [x] Re-run scheduler/dispatch verification after removal. **N/A — nothing removed (absent).** `actions verify` re-run 2026-11-07: no findings.

### 3) Archive the agent repo read-only (external/ops)
- [x] Identify the agent repo location(s) used historically; confirm suite/dispatch no longer depends on writable agent-repo paths for scheduled work. **Host `fedora` (2026-11-07):** searched `/home/deon` depth 3 outside `spectre-suite` — no separate `spectre-agent` repo found; operator confirmed **none on this host**. Suite/dispatch runs from this merged repo; no external writable agent repo identified for scheduled work.
- [x] Archive or mark read-only per ops policy (e.g., git remote/archive, filesystem permissions, documented deprecation). Record location and date. **N/A (none on this host, confirmed 2026-11-07).**
- [x] Confirm no schedulers or installed units reference the archived repo. **N/A (none on this host, confirmed 2026-11-07).**

### 4) “No path outside the repo is referenced” (definition of done)
- [x] `spectre actions verify` reports no legacy-path findings (where host inventory is available). **Fedora 2026-11-07:** 67 jobs, 0 blocking, 0 legacy-path, 0 unregistered — **no findings**.
- [ ] Manual spot-check: crontab, `systemctl list-timers --all`, `systemctl --user list-timers --all`, and any `/etc/systemd/system` or user unit files for jobs — no references to removed `scripts/` paths or `/home/deon/scripts`. **Partially satisfied (2026-11-07):** `crontab -l` uses `spectre run` only; system/user timers reviewed (spectre/perf/sec timers present, no legacy refs observed). `rg` over `/etc/systemd/system` and `~/.config/systemd/user` found no `/home/deon/scripts`/repo-`scripts/` legacy scheduler refs (permission denied on `/etc/systemd/system/alloy.service.d/env.conf`; `/var/spool/cron` unreadable). **However**, stale `/usr/local/bin` artifacts contain legacy refs (see §1.17) — until inspected/cleaned per ops decision, do not claim full Phase 4 DoD.
- [ ] Prometheus/exporter/timer installs regenerated from canonical installers if previously installed from legacy paths. **Not verified (2026-11-07).** Check exporter/timer/service install provenance; regenerate from canonical installers if any legacy-installed. **Requires explicit confirmation before host changes.**

## Evidence to record
- Hostname, date, operator
- `spectre actions verify` output
- `crontab -l` / timer listings (redact secrets)
- Result of `/home/deon/scripts` check
- Agent repo archive/read-only action taken

## Host evidence (fedora, 2026-11-07, investigation/read-only)
- **Host/date:** `fedora`, 2026-11-07T10:04:36+05:00 (operator: session-assisted).
- **CLI/dispatch:** `PYTHONPATH=. python3 -m spectre.cli.main actions list` → 67 jobs; `actions verify` → **no findings** (0 missing/not-executable/syntax/unlocked-mutation/duplicate; 0 legacy-path/unregistered).
- **`/home/deon/scripts`:** absent (`test ! -e /home/deon/scripts`).
- **Crontab (sampled):** uses `/usr/local/bin/spectre run backups/...` (no repo `scripts/` paths visible in sampled lines). **Full host/unit/wrapper scan not exhaustively completed.**
- **Timers/units (spot check):** user has `spectre-restic-backup/verify/catchup` timers; system has `security-scan.timer` + `performance-check.timer` (no user duplicates found for perf/sec). No system `spectre-daemon.service`/`spectre-api.service` units found; **check `~/.config/systemd/user/` for legacy daemon units if daemon/API is expected** (spec §8.6/§12.2; migration runbook noted old user units on reference host).
- **Agent repo (§3):** searched `/home/deon` depth 3 outside `spectre-suite` — no separate `spectre-agent` repo found; **operator confirmed “none on this host” (2026-11-07)**. §3 recorded as N/A where applicable.
- **Daemon/API (Task 4, confirmed 2026-11-07):** `spectre-daemon.service`/`spectre-api.service` present as *user* units (`~/.config/systemd/user/`), enabled+active, using `~/.local/share/spectre-venv` and §8.6 module paths (`spectre.daemon.main`, `uvicorn spectre.api.main:app` on 127.0.0.1:8106); API `/openapi.json` and `/api/security/summary` returning 200 (journal). No system/user duplicates found for `performance-check`/`security-scan`.
- **Task 2 host cleanup (completed 2026-11-07):** deleted `/etc/systemd/system/{disk-space-check,performance-check,security-scan}.service.bak` (operator-confirmed `sudo rm -f`; post-check: `no .bak service files remain`).

## Notes
- Repo-only C1 did **not** perform host filesystem changes. Treat host checks as per-host; reference-host status may differ from other machines.
- Next spec phase after Phase 4 completion: **Phase 5** — README truth pass; merged CI; docs match `actions list` (§8.4, §9).
