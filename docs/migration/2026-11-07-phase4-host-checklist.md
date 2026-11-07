# Phase 4 Host/Ops Checklist (post-C1 repo cleanup)

**Date:** 2026-11-07  
**Context:** C1 (tracked legacy `scripts/` removal) complete on `main` (`4c211c9` lineage, CI green; guardrail `fe2e851`); `spectre/policies/` is a real canonical directory. This checklist covers **spec §8.4 Phase 4** items that are **host/ops/external** (not fully satisfied by repo-only changes).

**Spec ref:** `docs/superpowers/specs/2026-10-05-spectre-consolidation-design.md` §8.4 Phase 4 — *“Remove shims; delete `/home/deon/scripts`; archive the agent repo read-only — done when no path outside the repo is referenced.”*

## Preconditions
- [ ] On the target host, confirm `spectre` CLI/dispatch is installed and working: `spectre actions list`, `spectre actions verify` (expect 0 legacy-path findings where applicable).
- [ ] Confirm schedulers (cron, system/user timers) invoke `spectre run <job>` or approved canonical entrypoints — no repo `scripts/` paths, no `/home/deon/scripts`.
- [ ] Have rollback/host access appropriate for scheduler and filesystem changes.

## Checklist

### 1) In-repo shims / legacy `scripts/` (repo-side, C1)
- [x] Tracked legacy `scripts/` tree removed from repo (`git ls-files scripts` = 0); active refs rewired; CI guardrail blocks tracked reintroduction.
- [ ] Verify no deployed/installed artifacts on the host still reference repo `scripts/` paths (generated units, copied scripts under `/usr/local/bin` or elsewhere, local wrappers). Use `rg` on host config locations as appropriate; `spectre actions verify`/dispatcher checks where available.

### 2) Delete `/home/deon/scripts` (host)
- [ ] Confirm `/home/deon/scripts` is absent **or** contains no live, scheduler-referenced, or PATH-installed operational scripts. (Reference host noted absent in earlier migration context; do not assume.)
  ```bash
  test ! -e /home/deon/scripts && echo "absent" || find /home/deon/scripts -maxdepth 3 | head
  ```
- [ ] If present and unused after verification, remove/archive per ops policy (confirm no `ConditionPathExists`, no cron/systemd/user-timer, no `/usr/local/*` wrapper depends on it). **Destructive host action — explicit confirmation required.**
- [ ] Re-run scheduler/dispatch verification after removal.

### 3) Archive the agent repo read-only (external/ops)
- [ ] Identify the agent repo location(s) used historically; confirm suite/dispatch no longer depends on writable agent-repo paths for scheduled work.
- [ ] Archive or mark read-only per ops policy (e.g., git remote/archive, filesystem permissions, documented deprecation). Record location and date.
- [ ] Confirm no schedulers or installed units reference the archived repo.

### 4) “No path outside the repo is referenced” (definition of done)
- [ ] `spectre actions verify` reports no legacy-path findings (where host inventory is available).
- [ ] Manual spot-check: crontab, `systemctl list-timers --all`, `systemctl --user list-timers --all`, and any `/etc/systemd/system` or user unit files for jobs — no references to removed `scripts/` paths or `/home/deon/scripts`.
- [ ] Prometheus/exporter/timer installs regenerated from canonical installers if previously installed from legacy paths.

## Evidence to record
- Hostname, date, operator
- `spectre actions verify` output
- `crontab -l` / timer listings (redact secrets)
- Result of `/home/deon/scripts` check
- Agent repo archive/read-only action taken

## Notes
- Repo-only C1 did **not** perform host filesystem changes. Treat host checks as per-host; reference-host status may differ from other machines.
- Next spec phase after Phase 4 completion: **Phase 5** — README truth pass; merged CI; docs match `actions list` (§8.4, §9).
