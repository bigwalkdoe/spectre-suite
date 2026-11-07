# OPA Path C — Spectre Security Core Contract (v1, draft)

**Date:** 2026-11-07  
**Status:** draft (Path C groundwork, additive). **No CI/gate/aggregation changes.**  
**Decision:** Path C now (shared core + adapters), keep k8s admission/versions **isolated + separate CI for now** (not merged into `data.security[k].deny` aggregation).

## 1. Core (suite-canonical, enforced)
- **Aggregation/gate contract:** `data.security[k].deny[m]` over `spectre/policies/*.rego` (rego v1). CI invariants (must remain green unless explicitly reviewed): `opa check spectre/policies/`; empty input `{}` yields **>= 38 denials** (fail-closed); `spectre/policies/baseline.json` yields **0 denials**.
- **Core input (infra baseline):** flat fields/booleans consumed by `security.*` packages (see `baseline.json` and mapping). Missing fields remain **undefined → fail-closed**.

## 2. Adapters (explicit, additive)
1. **Suite flat-baseline adapter (identity/validation):** suite-native `baseline.json` / flat infra inputs evaluated directly against core.
2. **spectre-security nested/test-data adapter (implemented):** `spectre/actions/security/baseline/opa-contract-adapter.py` maps nested `current-infrastructure.json` (`docker[]`, `network{}`, `compliance{}`, `backup{}`) to core flat fields; **only confident mappings emitted**, unmapped suite controls **absent/fail-closed**. Report-only compat via `opa-compat-report` / `SECURITY_OPA_COMPAT` (non-gating).
3. **k8s admission adapter (isolated, implemented as report slice):** `spectre/actions/security/opa/kubernetes-admission-report.py` evaluates AdmissionReview input against `kubernetes.admission` (`data.kubernetes.admission.deny`) + versions metadata/index. Policy/tests/versions are vendored under `spectre/policies/k8s/` (report defaults to vendored; `SPECTRE_SECURITY_ROOT` remains a fallback). **ISOLATED:** not in `data.security[k].deny` aggregation, no core CI gate change.

## 3. Compliance/control mapping (machine-checkable)
- `spectre/policies/contract/mapping.v1.json` records implemented adapter slices: source paths, target suite fields/packages, evidence-only/unmapped/fail-closed notes, and isolated domains. **Informational/validation aid; does not change policy behavior.**
- Rule: **do not invent** suite control values. Add mappings only with explicit, unambiguous evidence/contract justification and reviewed diff + expected fail-closed/baseline/CI impact.

## 4. Isolated domains
- `kubernetes.admission`, `opa.versions` reporting/index are **isolated** from core `data.security[k].deny`. Vendored assets live under `spectre/policies/k8s/` (policy, tests, versions index/metadata) and remain report-only. Separate CI/gates may be added only by explicit decision; never silently aggregated. Opt-in check: `spectre/policies/contract/check_isolation.sh`.

## 5. Evolution
- Keep core gates green on every commit. Extend mapping + adapters in reviewed slices; promote isolated domains into separately-gated CI before any aggregation consideration.
