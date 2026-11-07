# Live-Infra Evidence Inventory (Path C, additive)

**Date:** 2026-11-08  
**Purpose:** Design step 1 for live-infra input generation parity. No policy/gate changes.

## Current producers/consumers (suite)

| Component | Role | Shape / notes |
|---|---|---|
| `spectre/actions/security/baseline/opa-contract-adapter.py` | Normalizes nested snapshot → canonical flat suite fields | Consumes `{docker[], network{}, compliance{}, backup{}}` (extra metadata ignored). Emits only confidently mapped fields; unmapped absent/fail-closed. |
| `spectre/actions/security/baseline/opa-compat-report.py` / `SECURITY_OPA_COMPAT` | Report-only compat evaluation | Reads nested snapshot (default state path or explicit/SPECTRE_SECURITY_ROOT fallback), adapts, evals `data.security[k].deny[m]`; non-gating. |
| `spectre/actions/security/baseline/drift-detection.sh`, `update-baseline.sh` | Baseline/drift helpers (compat-oriented) | Reference `current-infrastructure.json` state/fallback paths; `SPECTRE_SECURITY_ROOT` compat fallback; graceful when archived repo absent. |
| `spectre/monitoring/exporters/security-baseline-metrics-exporter.sh` | Metrics export | Uses `SPECTRE_SECURITY_ROOT`/compat context; suite observability path canonical (`spectre_security_baseline_*`). |
| `spectre/policies/contract/mapping.v1.json` (+ schema) | Machine-checkable mapping contract | Records nested→flat mappings, evidence-only/unmapped, never-invented examples, k8s isolation. |
| `tests/fixtures/live_infra_snapshot/live_infra_snapshot.v0.schema.json` + fixtures | v0 snapshot envelope contract (additive) | Backward-compatible with adapter; adds optional `contract_version`/`source`/`generated_at`. Validated by `tests/test_live_infra_snapshot_contract.py`. Stored outside `spectre/policies/` to avoid OPA `--data` merge conflicts. |

## Canonical core contract (unchanged)
- Aggregation: `data.security[k].deny[m]` over `spectre/policies/*.rego` (rego v1). CI invariants: `opa check`, empty input ≥38 denials, `baseline.json` 0 denials.
- K8s admission/versions: vendored/isolated, separate CI; **not** aggregated.

## Gaps (tracked)
- Suite-owned, versioned live-infra snapshot generation with parity/provenance across collectors (see `2026-11-08-opa-path-c-live-infra-input-parity-design.md`).
