# Spectre Observability Metrics Contract (draft)

**Date:** 2026-11-07  
**Status:** draft, implementation in progress (observability-first, additive)  
**Scope:** Canonical metric families for integrating Spectre agent runtime signals and spectre-security/suite security-baseline pipeline evidence.

## 1. Data sources — never conflated
| Source | Meaning | Canonical family (target) |
|---|---|---|
| **Spectre agent runtime** | API/exporter reachability, agent identity, runtime security findings/scan state exposed by the agent | `spectre_agent_*` (+ existing compatibility metrics) |
| **Security baseline pipeline** | OPA check/tests, drift, SBOM, Trivy/Gitleaks/AIDE/Wazuh/image-scan/alerting/hardening phase results and evidence produced by the baseline pipeline (spectre-security and/or suite `security/baseline/run`) | `spectre_security_baseline_*` |

**Rules:**
- `agent down` is **not** `clean scan` and **not** `drift detected`.
- `no scan recorded` / `never run` is **not** zero findings and **not** a timestamp of “now”.
- `unknown` means the exporter/pipeline cannot determine the state (missing evidence, parse error, tool unavailable for a required reading) — emit explicit unknown state; do not fabricate success/failure.
- `stale` means evidence exists but is older than the configured freshness window — emit stale state alongside the last-known values/timestamp; do not treat as current pass/fail unless policy states otherwise.
- `clean scan` / `no drift` / `pass` requires positive evidence from the relevant run.

## 2. Compatibility with existing suite metrics
Existing suite agent-runtime exporter (`spectre/monitoring/exporters/security-metrics-exporter.sh`) already emits:
- `spectre_agent_up`, `spectre_agent_up_reason`, `spectre_agent_identifies_as` (availability/identity)
- `spectre_security_ever_scanned`, `security_last_scan_timestamp`, `security_findings_*` etc. (agent runtime scan/findings)

These remain supported for existing alerts/dashboards/tests. Migration may add aliases, but **must not break** current semantics. `spectre_security_baseline_*` is reserved for **baseline pipeline evidence**, not agent runtime findings.

## 3. `spectre_security_baseline_*` (v1, additive)
Emitted by `spectre/monitoring/exporters/security-baseline-metrics-exporter.sh` (textfile `.prom`).

### Exporter/evidence freshness
- `spectre_security_baseline_exporter_up{source="suite|spectre_security|mixed|none"}` = 1 when exporter produced metrics; 0 on fatal error.
- `spectre_security_baseline_last_run_timestamp_seconds{source="..."}` = unix seconds of last known baseline evidence; **0 when never run/unknown**.
- `spectre_security_baseline_never_run{source="..."}` = 1 if no baseline evidence found, else 0.
- `spectre_security_baseline_evidence_age_seconds{source="..."}` = now - last_run (0 when never run/unknown).
- `spectre_security_baseline_stale{source="..."}` = 1 if evidence age > `SPECTRE_SECURITY_BASELINE_STALE_SECONDS` (default 172800 / 48h) and evidence exists; 0 otherwise.
- `spectre_security_baseline_unknown{source="..."}` = 1 when exporter cannot determine state (no parsable evidence / read error), else 0.

### Phase/result gauges (v1)
Values use explicit status codes where helpful: `1=pass/clean/ok`, `0=fail/findings/drift/issue`, `-1=unknown/skipped/not applicable` (or use `*_unknown`/`*_skipped` companion gauges). v1 keeps it simple:
- `spectre_security_baseline_opa_check_ok{source}` = 1 pass, 0 fail/issues, -1 unknown/skipped (suite-native OPA check).
- `spectre_security_baseline_opa_tests_ok{source}` = 1 pass, 0 fail, -1 unknown/skipped (legacy compat policy tests).
- `spectre_security_baseline_opa_compat_report_ok{source}` = 1 **Option A compat report produced/ran** when `SECURITY_OPA_COMPAT=1` (**report-only; denials do not make this 0**), 0 helper/exec issues, -1 off/unknown/skipped. Distinct from `opa_tests_ok` and from policy denials.
- `spectre_security_baseline_hardening_ok{source}` = 1 ok, 0 fail, -1 unknown/skipped.
- `spectre_security_baseline_drift_detected{source}` = 1 drift detected, 0 no drift (positive evidence), -1 unknown/skipped.
- `spectre_security_baseline_sbom_ok{source}` = 1 ok, 0 fail/issues, -1 unknown/skipped.
- `spectre_security_baseline_trivy_fs_ok{source}` = 1 ok, 0 issues/fail, -1 unknown/skipped.
- `spectre_security_baseline_gitleaks_ok{source}` = 1 clean/no findings reported, 0 findings/issues, -1 unknown/skipped.
- `spectre_security_baseline_aide_ok{source}` = 1 ok, 0 fail, -1 unknown/skipped.
- `spectre_security_baseline_wazuh_ok{source}` = 1 ok/active as reported, 0 not ok, -1 unknown/skipped.
- `spectre_security_baseline_trivy_image_ok{source}` = 1 ok, 0 fail, -1 unknown/not configured.
- `spectre_security_baseline_phase_run_total{source,phase,result}` (optional/counter-like gauge v1) — may be added when structured evidence exists.

**Labels:** keep low cardinality. `source` indicates evidence origin (`suite`, `spectre_security`, `mixed`). Do not use hostnames, paths, image names, or finding IDs as labels.

### Metrics & alert semantics: `opa_compat_report_ok` (Option A)
`spectre_security_baseline_opa_compat_report_ok` uses **report-ran semantics, NOT “no denials”**: `1` = `SECURITY_OPA_COMPAT` Option A report produced/ran (policy denials do **not** make this 0), `0` = helper/exec issues, `-1` = off/unknown/skipped. `SecurityBaselineOPACompatReportIssues` alerts only on `== 0`. Dashboard panels/legend label it accordingly.

## 4. Wiring
- Exporters write to Prometheus textfile directory (`prometheus/business-metrics` / `/textfile` in compose) for the existing `business-metrics`/node_exporter textfile scrape path.
- A/D hybrid: exporter may read suite logs (`SECURITY_BASELINE_LOG_DIR`) and, if configured, `SPECTRE_SECURITY_ROOT`/spectre-security baseline logs/reports.
- Alerts/dashboards should distinguish `spectre_agent_*` (runtime) from `spectre_security_baseline_*` (pipeline evidence). Reconcile/rename spectre-security-named assets only with compatibility/transition plan.

## 5. Reconciliation backlog (suite repo)
- [ ] Add baseline exporter registry job + scheduling (additive).
- [ ] Add/adjust Prometheus alert rules for `spectre_security_baseline_*` with unknown/stale/never-run handling (do not conflate with agent alerts).
- [ ] Import/reconcile spectre-security Grafana dashboard to suite observability assets with canonical metric names and clear data-source semantics.
- [ ] Update/add tests for exporter output semantics (never-run/unknown/stale/clean/fail).
- [ ] Document migration for any renamed metrics/labels.