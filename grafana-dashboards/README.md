# Grafana dashboards

## `security-baseline-pipeline.json`
Visualizes **security baseline pipeline evidence** (`spectre_security_baseline_*`), distinct from agent runtime (`spectre_agent_*`).

### Key semantics
- `1` = pass/ok/clean (or drift detected for `drift_detected`), `0` = fail/findings/issues, `-1` = unknown/skipped/not configured.
- **`spectre_security_baseline_opa_compat_report_ok` is report-ran semantics (NOT “no denials”):** `1` = Option A compat report produced/ran when `SECURITY_OPA_COMPAT=1` (denials do **not** make this 0), `0` = helper/exec issues, `-1` = off/unknown/skipped. See `docs/superpowers/specs/2026-11-07-spectre-observability-metrics-contract.md` and the alert `SecurityBaselineOPACompatReportIssues` (fires only on `== 0`).
