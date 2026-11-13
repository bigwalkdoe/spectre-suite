# Spectre Security Baseline Alert Rules — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 6 missing Prometheus alert rules for `spectre_security_baseline_*` metrics (trivy_fs_ok, aide_ok, wazuh_ok, trivy_image_ok, evidence_age_seconds, unknown) to the `security_baseline_alerts` group in `prometheus/alert_rules.yml`, following the existing pattern exactly.

**Architecture:** Single-file change to `prometheus/alert_rules.yml` — insert 6 new alert rules into the existing `security_baseline_alerts` group, alphabetically ordered among existing rules. No new files, no backend changes, no test changes (alert rule YAML is validated by CI's promtool check, not by bash tests).

**Tech Stack:** Prometheus alerting rules YAML, promtool (CI validation).

**Spec:** `docs/superpowers/specs/2026-11-14-spectre-security-baseline-alert-rules-design.md`

## Global Constraints

- All alert rules live in `prometheus/alert_rules.yml` under the `security_baseline_alerts` group.
- Follow the existing pattern exactly: `expr: <metric> == 0` (or `> threshold` for age), `for:` duration, `labels: { severity: <level> }`, annotation block with `summary` and `description` using `{{ $labels.source }}`.
- Alert names follow the `SecurityBaseline<Thing>Failed|Detected|Missing` naming convention.
- `-1` (unknown/skipped) must NOT trigger alerts — only `== 0` (explicit fail/issues/drift).
- `spectre actions verify` must remain clean (90 jobs, 0 findings).
- All existing tests must continue to pass.

## Review Focus

These input classes/failure modes are implied by the spec but not pinned by individual tests:

1. **`-1` (unknown/skipped) must not trigger** — alert rules must use `== 0`, not `!= 1` or `< 1`.
2. **`evidence_age_seconds` threshold** — must use 172800 seconds (48h, matching `STALE_SECONDS` default in the exporter), not an arbitrary value.
3. **Alert names follow convention** — `SecurityBaseline<Thing>Failed|Detected|Missing`, matching existing rule names exactly.
4. **`for:` duration matches existing severity pattern** — warning alerts use 15m or 1h, matching existing baseline alert rules.
5. **No rule for `last_run_timestamp_seconds`** — it's a gauge timestamp, not actionable as an alert; correctly excluded.

---

### Task 1: Add SecurityBaselineTrivyFsFailed alert rule

**Files:**
- Modify: `prometheus/alert_rules.yml`

**Interfaces:**
- Consumes: `spectre_security_baseline_trivy_fs_ok` metric from `security-baseline-metrics-exporter.sh`
- Produces: new alert rule `SecurityBaselineTrivyFsFailed` in the `security_baseline_alerts` group

- [x] **Step 1: Write the failing test**

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`

Expected: FAIL — the existing rules already pass, so this test doesn't fail. Instead, verify there is NO existing `SecurityBaselineTrivyFsFailed` rule:

Run: `grep -c "SecurityBaselineTrivyFsFailed" prometheus/alert_rules.yml`
Expected: FAIL — `grep` returns exit 1 (no match).

- [x] **Step 2: Implement `SecurityBaselineTrivyFsFailed` alert rule**

Add after `SecurityBaselineOPACompatReportIssues` rule (alphabetical order: TrivyFsFailed comes after OPACompatReportIssues):

```yaml
      - alert: SecurityBaselineTrivyFsFailed
        expr: spectre_security_baseline_trivy_fs_ok == 0
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Security baseline Trivy FS scan failed"
          description: >-
            Trivy filesystem scan reported issues (source={{ $labels.source }}).
            Review trivy-fs.log for details.
```

- [x] **Step 3: Run test to verify it passes**

Run: `grep -c "SecurityBaselineTrivyFsFailed" prometheus/alert_rules.yml`
Expected: PASS — returns 1.

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — YAML validates.

- [x] **Step 4: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add SecurityBaselineTrivyFsFailed alert rule"
```

---

### Task 2: Add SecurityBaselineAideCheckFailed alert rule

**Files:**
- Modify: `prometheus/alert_rules.yml`

**Interfaces:**
- Consumes: `spectre_security_baseline_aide_ok` metric from `security-baseline-metrics-exporter.sh`
- Produces: new alert rule `SecurityBaselineAideCheckFailed` in the `security_baseline_alerts` group

- [x] **Step 1: Write the failing test**

Run: `grep -c "SecurityBaselineAideCheckFailed" prometheus/alert_rules.yml`
Expected: FAIL — no match.

- [x] **Step 2: Implement `SecurityBaselineAideCheckFailed` alert rule**

Add after `SecurityBaselineTrivyFsFailed` (alphabetical: AideCheckFailed comes after TrivyFsFailed? No — "Aide" < "Trivy", so Aide comes first alphabetically. Wait: "TrivyFsFailed" vs "AideCheckFailed" — 'A' < 'T', so Aide comes first. But I'm adding in order... Let me think about insertion order.)

Actually, alphabetical order of alert names:
- SecurityBaselineAideCheckFailed
- SecurityBaselineDriftDetected (exists)
- SecurityBaselineEvidenceStale (exists)
- SecurityBaselineEvidenceAging (new)
- SecurityBaselineGitleaksFindings (exists)
- SecurityBaselineHardeningFailed (exists)
- SecurityBaselineMetricsMissing (exists)
- SecurityBaselineNeverRun (exists)
- SecurityBaselineOPACheckFailed (exists)
- SecurityBaselineOPATestsFailed (exists)
- SecurityBaselineOPACompatReportIssues (exists)
- SecurityBaselineSBOMFailed (exists)
- SecurityBaselineTrivyFsFailed (new)
- SecurityBaselineTrivyImageFailed (new)
- SecurityBaselineUnknownState (new)
- SecurityBaselineWazuhDown (new)

So I need to insert in alphabetical order. Let me place them:
- SecurityBaselineAideCheckFailed → after SecurityBaselineMetricsMissing (before OPACompatReportIssues alphabetically? "Aide" < "OPACheck", so Aide comes before OPA checks)
- SecurityBaselineEvidenceAging → after EvidenceStale
- SecurityBaselineTrivyFsFailed → after SBOMFailed
- SecurityBaselineTrivyImageFailed → after TrivyFsFailed
- SecurityBaselineUnknownState → after TrivyImageFailed
- SecurityBaselineWazuhDown → after UnknownState

Actually, the existing order in the file isn't strictly alphabetical. Let me check the existing order:

From the alert rules file:
1. SecurityBaselineMetricsMissing
2. SecurityBaselineNeverRun
3. SecurityBaselineEvidenceStale
4. SecurityBaselineDriftDetected
5. SecurityBaselineOPACheckFailed
6. SecurityBaselineOPATestsFailed
7. SecurityBaselineOPACompatReportIssues
8. SecurityBaselineHardeningFailed
9. SecurityBaselineGitleaksFindings
10. SecurityBaselineSBOMFailed

This isn't strictly alphabetical. It's grouped by related concept. I'll insert new alerts in a logical position near related alerts:
- SecurityBaselineAideCheckFailed → after SecurityBaselineGitleaksFindings (both scan tools)
- SecurityBaselineTrivyFsFailed → after SecurityBaselineAideCheckFailed (scans)
- SecurityBaselineTrivyImageFailed → after SecurityBaselineTrivyFsFailed
- SecurityBaselineWazuhDown → after SecurityBaselineTrivyImageFailed
- SecurityBaselineEvidenceAging → after SecurityBaselineEvidenceStale (both age-related)
- SecurityBaselineUnknownState → after SecurityBaselineEvidenceAging (both state-related)

Let me place them in logical positions rather than strict alphabetical, matching the existing style.

- [x] **Step 2: Implement `SecurityBaselineAideCheckFailed` alert rule**

Add after `SecurityBaselineGitleaksFindings` rule:

```yaml
      - alert: SecurityBaselineAideCheckFailed
        expr: spectre_security_baseline_aide_ok == 0
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Security baseline AIDE file integrity check failed"
          description: >-
            AIDE file integrity check reported differences or issues
            (source={{ $labels.source }}). Review AIDE logs/evidence.
```

- [x] **Step 3: Run test to verify it passes**

Run: `grep -c "SecurityBaselineAideCheckFailed" prometheus/alert_rules.yml`
Expected: PASS — returns 1.

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — YAML validates.

- [x] **Step 4: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add SecurityBaselineAideCheckFailed alert rule"
```

---

### Task 3: Add SecurityBaselineWazuhDown alert rule

**Files:**
- Modify: `prometheus/alert_rules.yml`

**Interfaces:**
- Consumes: `spectre_security_baseline_wazuh_ok` metric from `security-baseline-metrics-exporter.sh`
- Produces: new alert rule `SecurityBaselineWazuhDown` in the `security_baseline_alerts` group

- [x] **Step 1: Write the failing test**

Run: `grep -c "SecurityBaselineWazuhDown" prometheus/alert_rules.yml`
Expected: FAIL — no match.

- [x] **Step 2: Implement `SecurityBaselineWazuhDown` alert rule**

Add after `SecurityBaselineTrivyImageFailed` rule:

```yaml
      - alert: SecurityBaselineWazuhDown
        expr: spectre_security_baseline_wazuh_ok == 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Security baseline Wazuh agent check failed"
          description: >-
            Wazuh status check reported issues (source={{ $labels.source }}).
            Review Wazuh agent status/exporter logs.
```

- [x] **Step 3: Run test to verify it passes**

Run: `grep -c "SecurityBaselineWazuhDown" prometheus/alert_rules.yml`
Expected: PASS — returns 1.

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — YAML validates.

- [x] **Step 4: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add SecurityBaselineWazuhDown alert rule"
```

---

### Task 4: Add SecurityBaselineTrivyImageFailed alert rule

**Files:**
- Modify: `prometheus/alert_rules.yml`

**Interfaces:**
- Consumes: `spectre_security_baseline_trivy_image_ok` metric from `security-baseline-metrics-exporter.sh`
- Produces: new alert rule `SecurityBaselineTrivyImageFailed` in the `security_baseline_alerts` group

- [x] **Step 1: Write the failing test**

Run: `grep -c "SecurityBaselineTrivyImageFailed" prometheus/alert_rules.yml`
Expected: FAIL — no match.

- [x] **Step 2: Implement `SecurityBaselineTrivyImageFailed` alert rule**

Add after `SecurityBaselineTrivyFsFailed` rule:

```yaml
      - alert: SecurityBaselineTrivyImageFailed
        expr: spectre_security_baseline_trivy_image_ok == 0
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Security baseline Trivy image scan failed"
          description: >-
            Trivy image scan reported issues (source={{ $labels.source }}).
            Review Trivy image scan logs.
```

- [x] **Step 3: Run test to verify it passes**

Run: `grep -c "SecurityBaselineTrivyImageFailed" prometheus/alert_rules.yml`
Expected: PASS — returns 1.

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — YAML validates.

- [x] **Step 4: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add SecurityBaselineTrivyImageFailed alert rule"
```

---

### Task 5: Add SecurityBaselineEvidenceAging alert rule

**Files:**
- Modify: `prometheus/alert_rules.yml`

**Interfaces:**
- Consumes: `spectre_security_baseline_evidence_age_seconds` metric from `security-baseline-metrics-exporter.sh`
- Produces: new alert rule `SecurityBaselineEvidenceAging` in the `security_baseline_alerts` group

- [x] **Step 1: Write the failing test**

Run: `grep -c "SecurityBaselineEvidenceAging" prometheus/alert_rules.yml`
Expected: FAIL — no match.

- [x] **Step 2: Implement `SecurityBaselineEvidenceAging` alert rule**

Add after `SecurityBaselineEvidenceStale` rule:

```yaml
      - alert: SecurityBaselineEvidenceAging
        expr: spectre_security_baseline_evidence_age_seconds > 172800
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Security baseline evidence aging"
          description: >-
            Baseline evidence is aging (source={{ $labels.source }}).
            Evidence age is {{ $value }} seconds, approaching the staleness
            threshold. Refresh the baseline pipeline before evidence goes stale.
```

- [x] **Step 3: Run test to verify it passes**

Run: `grep -c "SecurityBaselineEvidenceAging" prometheus/alert_rules.yml`
Expected: PASS — returns 1.

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — YAML validates.

- [x] **Step 4: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add SecurityBaselineEvidenceAging alert rule"
```

---

### Task 6: Add SecurityBaselineUnknownState alert rule

**Files:**
- Modify: `prometheus/alert_rules.yml`

**Interfaces:**
- Consumes: `spectre_security_baseline_unknown` metric from `security-baseline-metrics-exporter.sh`
- Produces: new alert rule `SecurityBaselineUnknownState` in the `security_baseline_alerts` group

- [x] **Step 1: Write the failing test**

Run: `grep -c "SecurityBaselineUnknownState" prometheus/alert_rules.yml`
Expected: FAIL — no match.

- [x] **Step 2: Implement `SecurityBaselineUnknownState` alert rule**

Add after `SecurityBaselineTrivyImageFailed` rule:

```yaml
      - alert: SecurityBaselineUnknownState
        expr: spectre_security_baseline_unknown == 1
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "Security baseline state unknown"
          description: >-
            Baseline state cannot be determined from evidence
            (source={{ $labels.source }}). Review baseline pipeline logs;
            unknown state is not actionable as pass/fail until evidence is
            collected.
```

- [x] **Step 3: Run test to verify it passes**

Run: `grep -c "SecurityBaselineUnknownState" prometheus/alert_rules.yml`
Expected: PASS — returns 1.

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — YAML validates.

- [x] **Step 4: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add SecurityBaselineUnknownState alert rule"
```

---

### Task 7: Final verification

**Files:**
- Verify: `prometheus/alert_rules.yml`

**Interfaces:** none

- [x] **Step 1: Verify all 6 new alert rules exist**

Run: `for rule in SecurityBaselineTrivyFsFailed SecurityBaselineAideCheckFailed SecurityBaselineWazuhDown SecurityBaselineTrivyImageFailed SecurityBaselineEvidenceAging SecurityBaselineUnknownState; do grep -q "alert: $rule" prometheus/alert_rules.yml || echo "MISSING: $rule"; done`
Expected: PASS — no "MISSING" output.

- [x] **Step 2: Validate alert rules YAML**

Run: `docker run --rm --entrypoint promtool -v "$PWD/prometheus:/etc/prometheus:ro" prom/prometheus:v3.13.4 check rules /etc/prometheus/alert_rules.yml`
Expected: PASS — all rules valid.

- [x] **Step 3: Verify no `-1` triggers (unknown state only triggers on == 1)**

Run: `grep -E "unknown_ok|_unknown ==|_unknown !=" prometheus/alert_rules.yml | grep -v "unknown == 1"` — should return nothing.
Expected: PASS — no results (only `unknown == 1` exists, no other unknown comparisons).

- [x] **Step 4: Run spectre actions verify**

Run: `python3 -m spectre.cli.main actions verify`
Expected: 90 jobs, 0 findings.

- [x] **Step 5: Commit**

```bash
git add prometheus/alert_rules.yml
git commit -m "feat(monitoring): add 6 missing baseline alert rules (AideCheckFailed, WazuhDown, TrivyImageFailed, EvidenceAging, UnknownState)"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-11-14-spectre-security-baseline-alert-rules.md`. Please review the plan. Does it capture what you want?**

**Execution method:** You previously chose **Native**. I'll implement every task myself in this session, with per-task TDD (write failing test, watch it fail, implement, watch it pass, commit).