# spectre-security Ops De-duplication & Retirement Plan (coordinated)

**Date:** 2026-11-07  
**Status:** draft — **coordination and explicit confirmation required** (cross-repo + host)  
**Principle:** `spectre-suite` is canonical for execution/scheduling/provenance (`spectre run`, registry, `actions verify`, health/catch-up/restic semantics where applicable). `spectre-security` may temporarily own deep evidence generation during A/D hybrid; migrate only gaps, then retire parallels to avoid two truths.

## 1. Scope
- **spectre-security repo** (`/home/deon/dev/github/spectre-security`, `git@github.com:bigwalkdoe/spectre-security.git`): overlapping scripts, baseline exporters/services/timers, OPA, CI/workflows, installers.
- **spectre-suite repo**: canonical actions/registry/monitoring/policies; absorbs capabilities in verified slices.
- **Host (fedora, reference findings 2026-11-07):** installed artifacts/schedulers/exporters. **No host deletion/mutation without explicit confirmation.**

## 2. Observed overlaps (inventory seed)

| Area | spectre-security examples | spectre-suite canonical/target | Action |
|---|---|---|---|
| Security baseline phases | `security/baseline-runner.sh`, drift/SBOM/scan/alert helpers, exporters/timers | `security/baseline/run` + `spectre/actions/security/baseline/*`, `prometheus/security-baseline-metrics-exporter` (`spectre_security_baseline_*`) | Port parity (in progress), reconcile metrics/dashboards/alerts, migrate systemd timers/exporters to suite templates/installers |
| Hardening/scanning | `security/run-security-hardening.sh`, Trivy/Gitleaks/ZAP/Sonar assets, IDS/IPS | `spectre/actions/security/*` + registry jobs; monitoring exporters | Map gaps; keep evidence formats; retire duplicates after parity |
| OPA | `security/opa/*` (tests, k8s admission, versions) | `spectre/policies/*`, CI fail-closed gates | Govern via A/C plan; merge with adapters |
| Backups/maintenance/perf/network/setup | top-level `setup-*`, `setup-backup-cron.sh`, maintenance/perf/network scripts | suite registry actions, backup health/catch-up/restic semantics | **Prefer suite semantics**; do not run spectre-security installers that (re)create `/home/deon/scripts` or legacy cron; migrate only gaps |
| Host `/usr/local/bin` legacy refs | 14 files found referencing `/home/deon/scripts` (2026-11-07) | `spectre run` + canonical installers/wrappers | Cross-repo/host coordination (see §3) |

## 3. Host findings — `/usr/local/bin` (fedora, 2026-11-07)
**Evidence:** `rg -l /home/deon/scripts /usr/local/bin` found 14 files (root-owned, Jul 26 2026). No active scheduler references found in `/etc/systemd/system`, readable `/etc/cron*`, or `~/.config/systemd/user` (spot check); `/var/spool/cron` unreadable. Matching names exist in `spectre-security`, but sampled hashes **differ** from current `spectre-security` files → likely installed from spectre-security/older state.

**High-risk:** `setup-backup-cron.sh` would install legacy `/home/deon/scripts/backups/*` cron entries, regressing the current clean `spectre run` crontab — **do not execute**.  
**Broken/legacy:** `check-performance-wrapper.sh` targets missing `/home/deon/scripts/...` (unused by active `performance-check.service`).  
**Legacy generators:** `setup-audit-logging.sh`, `setup-database-optimization.sh`, `setup-intrusion-detection.sh`, `setup-logging.sh`, `setup-opa-policies.sh`, `setup-resource-monitoring.sh`, `setup-secrets-management.sh`, `setup-security-scanning.sh` create `/home/deon/scripts/*`/legacy cron/jobs.  
**Runtime helpers (stale paths):** `run-trivy-scan.sh`, `run-zap-scan.sh`, `container-logrotate.sh`, `centralized-log-shipper.sh`.

**Required handling:** classify manual/external use, confirm disposition with operator + spectre-security ownership, archive/remove/replace only with explicit confirmation, then re-scan and update Phase 4 checklist §1.17/§4.34.

## 4. spectre-security retirement boundary (decide per capability)
- **Absorb into suite:** baseline orchestration phases (parity proven), OPA governance (per decision), metrics/exporters, provenance/scheduling, drift/SBOM/reporting semantics.
- **Possibly external infra (evaluate):** SonarQube/ZAP hosted services/compose — may remain operational dependencies while suite owns orchestration/evidence collection.
- **Archive/read-only after parity:** overlapping setup scripts, duplicate exporters/timers, superseded top-level scripts. Keep git history; record retirement evidence.

## 5. Migration/retirement checklist (template)
For each capability:
- [ ] Canonical suite job/action exists and is registered/verified.
- [ ] Evidence/metric/dashboard/alert parity proven (or intentional, documented change).
- [ ] CI/gates cover the canonical path.
- [ ] Schedulers/host units repointed (confirmed per host).
- [ ] Legacy script/installer retired or clearly marked non-canonical.
- [ ] spectre-security artifact archived/read-only or removed only after coordination.

## 6. Immediate coordinated actions (no destructive changes here)
1. Confirm whether `spectre-security` is active, superseded, or in maintenance on this host and in org workflows.
2. Freeze/guard legacy installers: ensure `setup-backup-cron.sh` and other `/usr/local/bin` generators are not used (operator awareness; consider renaming/archiving with confirmation).
3. Migrate baseline systemd exporter/timer (spectre-security) to suite `prometheus/security-baseline-metrics-exporter` + canonical textfile wiring — host change, confirm.
4. After OPA governance decision + parity, reconcile `security/opa` and retire duplicate CI/workflows.
5. Update Phase 4 checklist evidence as host items are resolved.