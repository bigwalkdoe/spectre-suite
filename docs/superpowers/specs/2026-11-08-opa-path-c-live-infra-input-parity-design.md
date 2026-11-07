# OPA Path C — Live-Infra Input Generation Parity (design-first)

**Date:** 2026-11-08  
**Status:** proposal (design-first; no policy/gate/aggregation changes)  
**Tracks:** Path C core/contract evolution (task 5), informs slice porting (task 1)  
**Prereqs (done):** Path C groundwork complete; core `data.security[k].deny[m]` gates 38/≥fail-closed and `baseline.json` 0 preserved; k8s/versions isolated with separate CI in `lint.yml`; `SPECTRE_SECURITY_ROOT` compat paths graceful (spectre-security archived).

## 1. Gap (observed)
- **Retirement execution doc** records remaining decision/gap: “concrete path C contract/schema/versioning, k8s+versions final CI integration (if ever), **live infra input generation parity**.”
- Today, the suite has: (a) canonical flat `baseline.json`/core policy inputs, (b) nested→flat adapter for spectre-security-shaped `current-infrastructure.json` + `SECURITY_OPA_COMPAT` (report-only, non-gating), (c) vendored/isolated k8s admission + versions reports. 
- **Missing/partial:** a single, versioned, suite-owned **live infra evidence → core input** generation path with parity/evidence guarantees equivalent to the absorbed baseline/compat flows, without depending on the archived spectre-security repo.

## 2. Goals / non-goals
**Goals (additive, reviewed):**
- Define a versioned contract for “live infra snapshot” inputs and the adapter/normalizer that produces canonical core fields (or explicit `absent/fail-closed`).
- Preserve all core invariants: `opa check`, empty-input fail-closed ≥38, `baseline.json` 0 denials, no silent aggregation of isolated domains.
- Make mappings **machine-checkable** (extend `spectre/policies/contract/mapping.v1.*` / schema) and testable with fixtures.
- Keep compat (`SECURITY_OPA_COMPAT`) report-only/non-gating unless explicitly decided otherwise.

**Non-goals (now):**
- No changes to `data.security[k].deny` aggregation semantics or deny-count gates without reviewed evidence.
- No aggregation of `kubernetes.admission`/versions into core.
- No invented suite control values; unmapped controls remain fail-closed.

## 3. Options (design)
1. **Extend nested adapter contract (incremental):** formalize the nested snapshot schema version(s) the adapter accepts, add fixture-based parity tests, and generate a suite-native snapshot format only where evidence is unambiguous. *Lowest risk; builds on existing adapter.*
2. **Suite-native live collector + normalizer:** implement `spectre`-owned collectors that emit a versioned canonical snapshot, normalized to core flat fields. *Best long-term ownership; higher effort; needs host/evidence parity proof.*
3. **Dual-path with explicit provenance (recommended direction):** suite-native collector when available, else explicit compat adapter path; both produce versioned, machine-validated outputs with provenance metadata; CI/tests cover fixtures for each path and core gate invariants. *Balances parity and migration risk.*

## 4. Contract/versioning requirements
- Snapshot/adapter outputs carry: `contract_version`, `source`/provenance, `generated_at` (where applicable), emitted fields, and explicit notes for unmapped/fail-closed controls.
- Extend `mapping.v1.schema.json`/contract (v2 or additive v1 extensions) only with backward-compatible, validated changes.
- Every new mapping requires: unambiguous evidence, target suite field/package(s), tests, and a statement of expected gate impact (must keep 38/0 invariants unless intentionally reviewed).

## 5. Validation & CI (additive)
- Fixture tests for accepted snapshot schemas → adapter output → OPA eval invariants.
- Keep schema/contract validation in existing test/CI paths (already covered via `test_opa_path_c_contract.py` in `opa-isolated-k8s` job); add focused tests for any new collector/normalizer.
- Any CI workflow change must remain additive and preserve core aggregation gate semantics.

## 6. Risks
- **False confidence:** mapping ambiguous evidence to suite booleans. *Mitigation:* evidence-only/unmapped + fail-closed; reviewed diffs.
- **Gate breakage:** changing baseline/core inputs. *Mitigation:* run `opa check`, empty-input/baseline invariants, and full relevant tests per slice.
- **Drift:** multiple input shapes without provenance/versioning. *Mitigation:* explicit `contract_version`/provenance.

## 7. Recommended next execution steps (small, reviewed slices)
1. Inventory current live-infra evidence producers in suite (baseline runner/exporters/drift helpers) and document the snapshot shapes they emit/consume.
2. Define `live_infra_snapshot` contract v0 (schema + fixtures) for the **existing** nested shape, with provenance fields; validate via tests.
3. Add a suite-normalizer entrypoint that produces canonical flat fields + report (reuse adapter rules) with contract metadata.
4. Only after parity fixtures are green, consider suite-native collectors for missing evidence (option 2/3), one domain at a time.
