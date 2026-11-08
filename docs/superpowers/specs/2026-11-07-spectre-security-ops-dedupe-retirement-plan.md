# spectre-security Ops De-duplication & Retirement Plan (coordinated)

**Date:** 2026-11-07 (closure pass 2026-11-08)  
**Status:** **largely executed (coordinated)** — see `2026-11-07-spectre-security-retirement-execution.md` for evidenced steps. Remaining items require explicit operator/org decisions (notably hosted infra disposition).  
**Principle:** `spectre-suite` is canonical for execution/scheduling/provenance (`spectre run`, registry, `actions verify`, health/catch-up/restic semantics where applicable). `spectre-security` source repo is now **archived on GitHub**; suite compat paths degrade gracefully when `SPECTRE_SECURITY_ROOT` is absent. Migrate only gaps, retire parallels to avoid two truths.

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

## 3. Host findings — `/usr/local/bin` (fedora, 2026-11-07) — **resolved/archived (evidenced)**
**Evidence (2026-11-07):** `rg -l /home/deon/scripts /usr/local/bin` found 14 files referencing `/home/deon/scripts`. No active scheduler references found in `/etc/systemd/system`, readable `/etc/cron*`, or `~/.config/systemd/user` (spot check). Sampled hashes differed from then-current `spectre-security` files.

**Disposition (completed, evidenced 2026-11-07; see retirement execution Step 4):** `setup-backup-cron.sh`, `check-performance-wrapper.sh`, and all 12 remaining scripts were archived to `/usr/local/bin/.archived-spectre-security-20261107/` (0644, SHA256s recorded). Post-check: **no** `/home/deon/scripts` refs remain in `/usr/local/bin`. High-risk generators were **not executed**; archiving prevents execution from `/usr/local/bin` but does not undo prior system changes made by those scripts.

**Follow-up (operator):** if any external/manual workflow depended on these paths, restore/replace deliberately from archive with confirmation.

## 4. spectre-security retirement boundary (status 2026-11-08)
- **Absorbed/isolated in suite (evidenced):** baseline orchestration phases + compat path, `spectre_security_baseline_*` observability (exporter/alerts/dashboard/tests), OPA Path C groundwork (shared core + adapters), k8s admission/versions **vendored and isolated** with separate CI in `lint.yml` (`opa-isolated-k8s`), CI/OPA core gates 38/0, `actions verify` green (see retirement execution doc).
- **Hosted/external infra (evaluate separately — disposition tracking needed):** SonarQube/ZAP hosted services/compose may remain operational dependencies while suite owns orchestration/evidence collection. **Owner/disposition not recorded in this repo;** confirm with operator/org and document the decision.
- **Retired/archived:** overlapping `/usr/local/bin` legacy generators/helpers archived (Step 4). GitHub `bigwalkdoe/spectre-security` **archived/read-only** (Step 5b, 2026-11-08). Local clone removed (Step 5a). Keep git history/evidence.

## 5. Migration/retirement checklist (template)
For each capability:
- [ ] Canonical suite job/action exists and is registered/verified.
- [ ] Evidence/metric/dashboard/alert parity proven (or intentional, documented change).
- [ ] CI/gates cover the canonical path.
- [ ] Schedulers/host units repointed (confirmed per host).
- [ ] Legacy script/installer retired or clearly marked non-canonical.
- [ ] spectre-security artifact archived/read-only or removed only after coordination.

## 6. Coordinated actions — closure status (2026-11-08)
1. **Done (decisions/evidence):** `spectre-security` treated as superseded for absorbed capabilities; GitHub repo archived (5b); local clone removed (5a); Path C (C now) groundwork complete with isolated k8s/versions.
2. **Done (host, evidenced):** `/usr/local/bin` legacy generators/helpers archived to `.archived-spectre-security-20261107/`; no `/home/deon/scripts` refs remain in `/usr/local/bin`. Suite user timer for baseline metrics installed (3a); renamed/fixed 2026-11-08 to `spectre-baseline-metrics.{timer,service}` (uses `/usr/local/bin/spectre`, enabled/active, verified). Old `spectre-security-baseline-metrics` units retired to `~/.local/state/spectre-suite/retired-units/`; masked legacy system HTTP exporter left unchanged.
3. **Remaining (operator/org coordination):** disposition/ownership for SonarQube/ZAP/hosted services (evaluate separately); concrete Path C live-infra input generation parity; any further host repointing beyond 3a; update Phase 4 checklist evidence as external items are resolved. **No further destructive host or GitHub actions without explicit confirmation.**