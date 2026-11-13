# Spectre Security Baseline Metrics — Missing Alert Rules

**Date:** 2026-11-14
**Repo:** spectre-suite
**Parent spec:** `docs/superpowers/specs/2026-11-07-spectre-observability-metrics-contract.md`
**Phase:** 4 (Metrics/exporters reconciliation backlog item 5)

## Intent and why

The observability metrics contract spec's reconciliation backlog lists 5 remaining items, including item 5: "Document migration for any renamed metrics/labels." During implementation of Approach A (adding missing alert rules), it became clear that the gap is larger than documentation — **6 of 18 `spectre_security_baseline_*` metrics published by `security-baseline-metrics-exporter.sh` have no corresponding Prometheus alert rule**. Without alerts, operators have no signal when these checks fail.

## Goals

Add Prometheus alert rules for the 6 metrics currently missing alert coverage:

| Metric | Missing alert? |
|--------|---------------|
| `spectre_security_baseline_exporter_up` | ✅ covered |
| `spectre_security_baseline_last_run_timestamp_seconds` | N/A (gauge, no alert needed) |
| `spectre_security_baseline_never_run` | ✅ covered |
| `spectre_security_baseline_unknown` | ❌ missing |
| `spectre_security_baseline_evidence_age_seconds` | ❌ missing |
| `spectre_security_baseline_stale` | ✅ covered |
| `spectre_security_baseline_opa_check_ok` | ✅ covered |
| `spectre_security_baseline_opa_tests_ok` | ✅ covered |
| `spectre_security_baseline_opa_compat_report_ok` | ✅ covered |
| `spectre_security_baseline_hardening_ok` | ✅ covered |
| `spectre_security_baseline_drift_detected` | ✅ covered |
| `spectre_security_baseline_sbom_ok` | ✅ covered |
| `spectre_security_baseline_trivy_fs_ok` | ❌ missing |
| `spectre_security_baseline_gitleaks_ok` | ✅ covered |
| `spectre_security_baseline_aide_ok` | ❌ missing |
| `spectre_security_baseline_wazuh_ok` | ❌ missing |
| `spectre_security_baseline_trivy_image_ok` | ❌ missing |

## Non-goals

- No new metrics; only alert rules for existing metrics.
- No changes to the exporter itself.
- No changes to Grafana dashboards (dashboard already references all metrics).
- No changes to `spectre_security_*` runtime agent metrics (separate contract).
- No changes to alert rules for non-baseline metrics.

## Anti-goals

- An alert rule that fires on `-1` (unknown/skipped) — the contract explicitly says unknown/skipped does NOT trigger alerts.
- An alert rule that fires on evidence age alone without considering staleness — age is informational; staleness (already alerted) is the actionable signal.
- Changing severity levels of existing alert rules.

## Constraints

- All alert rules live in `prometheus/alert_rules.yml` under the `security_baseline_alerts` group.
- Follow the existing pattern exactly: `expr: <metric> == 0`, `for:` duration, `labels: { severity: <level> }`, annotation block with `summary` and `description` using `{{ $labels.source }}`.
- `evidence_age_seconds` alert fires when age exceeds the configured staleness threshold but before `stale == 1` (i.e., evidence is getting old but not yet stale). Since `stale_seconds` is a Prometheus variable not available in alert rules, use a reasonable default (e.g., evidence older than 48h / 172800 seconds).
- Alert names follow the `SecurityBaseline<Thing>Failed|Detected|Missing` naming convention.

## Approaches considered

**Approach A** (selected): Add all 6 missing alert rules following the existing pattern exactly. Complete coverage, consistent severity levels, minimal churn.

**Approach B**: Add only the most critical missing alerts (aide_ok, trivy_fs_ok, wazuh_ok — security-critical) and skip trivy_image_ok, evidence_age_seconds, unknown. Partial completion leaves gaps.

**Approach C**: Add missing alert rules AND refactor the alert rules file for better organization. Higher risk, more churn, no functional benefit.

Approach A selected: complete, follows existing patterns exactly, eliminates the gap where 1/3 of baseline metrics have no alerting.

## How it gets built

Add 6 new alert rules to the `security_baseline_alerts` group in `prometheus/alert_rules.yml`, between the existing `SecurityBaselineSBOMFailed` rule and the closing of the group (before the `monitoring_stack_alerts` group):

1. **SecurityBaselineTrivyFsFailed** — `spectre_security_baseline_trivy_fs_ok == 0`, for: 15m, severity: warning
2. **SecurityBaselineGitleaksFindings** — already exists (skip)
3. **SecurityBaselineAideCheckFailed** — `spectre_security_baseline_aide_ok == 0`, for: 15m, severity: warning
4. **SecurityBaselineWazuhDown** — `spectre_security_baseline_wazuh_ok == 0`, for: 30m, severity: warning
5. **SecurityBaselineTrivyImageFailed** — `spectre_security_baseline_trivy_image_ok == 0`, for: 30m, severity: warning
6. **SecurityBaselineEvidenceAging** — `spectre_security_baseline_evidence_age_seconds > 172800`, for: 1h, severity: warning
7. **SecurityBaselineUnknownState** — `spectre_security_baseline_unknown == 1`, for: 1h, severity: warning

Order: insert alphabetically within the existing group to maintain consistency.

## What's left to the builder

- Exact severity level and `for` duration for each new alert rule (chosen above based on criticality; adjustable).
- Exact alert name and description text for each new rule.
- Whether `evidence_age_seconds` threshold of 172800 (48h) matches `STALE_SECONDS` default (it does — both 48h).

## Approval needed

Sign off on this short design (reply yes/no). If approved, I'll write the implementation plan and proceed.