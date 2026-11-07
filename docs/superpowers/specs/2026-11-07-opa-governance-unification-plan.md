# OPA Governance Unification Plan (spectre-security → spectre-suite)

**Date:** 2026-11-07  
**Status:** **Path C groundwork — COMPLETE** (2026-11-07; shared core + explicit adapters; k8s/versions isolated; isolated CI gate added via `.github/workflows/opa-isolated-k8s.yml`). Core gates green.
**Context:** Absorption program (suite-as-canonical). Keep suite CI/dispatch/provenance; preserve evidence quality and CI gates.

## 1. Current contracts (observed)

### Suite (canonical today, enforced by CI)
- **Tree:** `spectre/policies/*.rego` + `spectre/policies/baseline.json`
- **Style:** `import rego.v1`; packages under `security.*` (e.g. `security.docker`, `security.compliance`, `security.backups`, `security.network`, `security.firewall`, etc.)
- **Input/aggregation contract (CI):** `lint.yml` evaluates `count([m | data.security[k].deny[m]])` on empty input (`{}`) and expects **>= 38 denials** (fail-closed). It also evaluates against `spectre/policies/baseline.json` and expects **no denials** (`[]`). `opa check spectre/policies/` must pass.
- **Baseline input shape:** flat booleans/fields (e.g. `docker_privileged`, `security_baseline_compliant`, `cis_benchmarks_followed`, `pci_dss_compliant`, …) — see `spectre/policies/baseline.json`.

### spectre-security (mature, different contract)
- **Tree:** `security/opa/policies/*` with `*_test.rego`; `security/opa/versions/*` (`metadata.json`, `index.json`); `security/opa/kubernetes-admission/`; `evaluate-policies.sh`, `test-opa-policies.sh`.
- **Style/examples:** `package docker.security`, `package security.compliance` (name overlaps but semantics differ), `package backup.policy` style queries in tests.
- **Test contract:** `test-opa-policies.sh` pipes *nested* per-domain slices from `test-data/current-infrastructure.json` and queries specific paths (e.g. `data.backup.policy.deny`, `data.docker.security.deny`, `data.network.security.deny`, `data.security.compliance.deny`). Docker tests iterate containers.
- **Input generation:** `evaluate-policies.sh` builds live infra input (different shape/fields than suite’s flat baseline).
- **Strengths:** explicit `*_test.rego`, versioned policies/metadata, k8s admission coverage, richer baseline-runner integration.

## 2. Drift/risk
- **Breaking CI:** changing package/data paths or removing deny coverage can break the suite’s fail-closed 38-control gate and baseline evaluation.
- **False confidence:** merging tests without adapting input contracts can make policies “pass” vacuously or fail for the wrong reason.
- **Operational evidence:** baseline/alerting/exporters depend on stable phase semantics; OPA contract changes ripple into `test-opa-policies`, infra input generation, and compliance mapping.

## 3. Options

### A — Suite contract canonical; adapt security-repo assets (recommended pragmatic path)
- **Canonical:** keep suite’s `data.security[k].deny[m]` aggregation, rego v1 style, `spectre/policies/` tree, and CI fail-closed/baseline gates as the source of truth.
- **Adapt:** port spectre-security policies/tests by *translating* to suite packages/input fields where equivalent; add an **adapter layer** for security-repo nested test-data/contracts (separate test harness or generated inputs) rather than replacing suite CI contract.
- **Versioning/k8s:** import `versions/` metadata and k8s admission policies into a structured subpath (e.g. `spectre/policies/k8s/`, `spectre/policies/versions/`) with explicit evaluation entrypoints; keep them from breaking the existing `data.security[k].deny` gate unless intentionally integrated.
- **Pros:** preserves current suite CI/provenance; lowest immediate breakage; incremental.
- **Cons:** translation effort; two mental models until migration completes; requires careful mapping table.

### B — Security-repo contract canonical; migrate suite CI/consumers
- **Canonical:** adopt spectre-security’s nested packages/test-data contract and rich tests/versions as primary.
- **Migrate:** rewrite suite policies, `baseline.json`, `lint.yml` gates, exporters, and any consumers to the new contract.
- **Pros:** preserves spectre-security’s mature test/version structure.
- **Cons:** high regression risk to suite gates/consumers; larger coordinated cutover; may disrupt established suite semantics.

### C — Shared core + explicit adapters (evolve A→B selectively)
- **Canonical core:** define a small, versioned **Spectre security contract** (input schema + deny/result conventions + compliance mapping) owned by suite.
- **Adapters:** (1) suite flat-baseline adapter, (2) spectre-security nested infra/test-data adapter, (3) k8s admission adapter. Policies/tests target the core; CI runs core gates plus adapter-specific tests.
- **Pros:** resolves long-term drift; supports both evidence sources (A/D hybrid) cleanly.
- **Cons:** upfront design work; needs schema/versioning discipline.

## 4. Recommended execution (if A or C chosen)
1. **Freeze & inventory:** build a policy/control mapping table: spectre-security rule/test → suite control/deny → input fields → evidence/CI impact. No policy deletions until mapped.
2. **Preserve CI invariants:** keep `opa check spectre/policies`, empty-input fail-closed count (update count only when controls are intentionally added/removed with evidence), and `baseline.json` no-deny check green on every commit.
3. **Add adapters, not replacements:** introduce adapter scripts/tests (e.g. `spectre/actions/security/baseline/opa-contract-adapter*`, or `spectre/policies/tests/`) that can evaluate legacy nested inputs against ported/core policies.
4. **Port in slices:** start with overlapping domains (docker, compliance, backups/network) where suite already has rego; add `*_test.rego`/rego tests in suite-compatible form; then k8s admission/versions.
5. **Compliance mapping:** maintain a machine-checkable mapping (control IDs, policy files, tests, evidence sources) generated/checked in CI.
6. **Deprecate legacy contract:** once parity is proven, retire `test-opa-policies.sh`/security-repo-only contracts or keep them behind explicit compat.

## 5. Immediate next tasks (additive)
- [x] Produce control-mapping matrix (MD) for suite `security.*` vs spectre-security packages/tests — `docs/superpowers/specs/2026-11-07-opa-control-mapping-matrix.md` (2026-11-07).
- [x] Implement a **nested→suite input adapter** for `current-infrastructure.json`-style data — `spectre/actions/security/baseline/opa-contract-adapter.py` (+ `tests/test_opa_contract_adapter.py`). Adapts to suite canonical flat fields; unmapped controls remain absent (fail-closed). Verified: adapted security-repo example yields 27 denials vs 38 on empty input (11 mappable controls asserted); `actions verify`/OPA gates unaffected.
- [x] Decide k8s admission/versions location and CI treatment (separate from `data.security[k].deny` aggregation unless explicitly integrated). **Decision:** isolated under `spectre/policies/k8s/` (policy + tests + versions index/metadata vendored from the retired spectre-security slice); report defaults to vendored with `SPECTRE_SECURITY_ROOT` fallback. `kubernetes.admission` is **not** aggregated, no CI gate change; opt-in check `spectre/policies/contract/check_isolation.sh`. Report slice: `spectre/actions/security/opa/kubernetes-admission-report.py` (+ `--include-versions-index`), `versions-index-report.py`; `kubernetes-admission_test.rego` ported to rego v1 (16 tests); **separate CI gate added:** `.github/workflows/opa-isolated-k8s.yml` (isolated `opa check`/`opa test` on `spectre/policies/k8s/`, isolation guard, opt-in isolation check, report tests — not part of core OPA gate).
- [~] Port overlapping policies/tests in slices (docker/compliance/backup/network), keeping CI fail-closed count/baseline green per reviewed change. **Progress:** adapter-tested slices added (backup, network, docker evidence+report metadata, security-compliance overlap/fail-closed boundaries); suite-canonical `*_test.rego` added for **all 8** `security.*` packages (`opa test spectre/policies/` PASS 48/48, 2026-11-07); **no rego/gate changes**, CI green (empty-input fail-closed count 38, `baseline.json` 0 denials).
- [x] Add compat runner that evaluates adapted nested data against suite policies (and reports mapped/unmapped) for `SECURITY_OPA_COMPAT`. Implemented: `spectre/actions/security/baseline/opa-compat-report.{sh,py}` (registered `security/baseline/opa-compat-report`), opt-in `SECURITY_OPA_COMPAT=1` path in `security/baseline/run` (report-only, non-gating), report-only `docker_evidence` summary/`--verbose` detail; now validated by `tests/test_opa_compat_report.py` (report-only behavior).

### `SECURITY_OPA_COMPAT` usage / interpretation (Option A)
- **Purpose:** compare/observe legacy spectre-security nested infrastructure evidence (`docker[]`, `network{}`, `compliance{}`, `backup{}`) against **canonical** `spectre/policies` using `opa-contract-adapter.py`. Adapter output contains only confidently mappable suite flat fields; unmapped suite controls remain **absent/fail-closed**.
- **CLI:** `python3 spectre/actions/security/baseline/opa-compat-report.py [nested.json] [--policy-dir spectre/policies] [--verbose]` (or `security/baseline/opa-compat-report.sh`). Default input falls back to `~/.local/state/spectre/security-baseline/current-infrastructure.json`, then the spectre-security test-data fixture if present.
- **Baseline runner (opt-in):** `SECURITY_OPA_COMPAT=1 spectre run security/baseline/run` (or direct runner) runs the Option A compat report as **report-only** and logs to `opa-compat-report.log`; it records `opa_compat=<exit>,on|off` in baseline DETAILS. **Non-gating:** compat denials/report findings do **not** fail the suite baseline gate; suite-native `opa check`/CI gates remain canonical.
- **Verbose:** `--verbose` or `SECURITY_OPA_COMPAT_VERBOSE=1` adds report-only detail (e.g. `docker_evidence` per-container lists: privileged, no-memory-limit, sensitive bind mounts, 0.0.0.0 exposure, missing healthcheck). Evidence is **not** emitted in adapted policy input and **not** asserted as suite global controls.
- **Interpretation:** `mapped_*` = fields adapted into suite contract; `denial_count/denials` = canonical suite policy denials for the adapted input (expected to include fail-closed denials for unmapped suite controls). `docker_evidence` is evidence/report metadata only. A “legacy compliant” case may still deny suite controls that have no legacy mapping — that is correct under Option A.

## 6. Decision (recorded)
**Path C selected:** shared Spectre security core + explicit adapters. Suite `data.security[k].deny` aggregation and CI gates remain canonical; k8s admission/versions stay isolated (report-only) with a separate gate now implemented via `.github/workflows/opa-isolated-k8s.yml`. See `docs/superpowers/specs/2026-11-07-opa-path-c-core-contract.md`.

Groundwork status (additive): machine-checkable contract mapping (`spectre/policies/contract/mapping.v1.json`) + validation (`tests/test_opa_path_c_contract.py`), `*_test.rego` for all 8 `security.*` packages plus isolated vendored `kubernetes.admission` slice (`opa test spectre/policies/` **64/64** total, core gates green), nested→flat adapter + `SECURITY_OPA_COMPAT` compat report, and opt-in isolation check (`spectre/policies/contract/check_isolation.sh`). No breaking package/gate changes made without passing CI checks.