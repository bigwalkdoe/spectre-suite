# OPA Governance Unification Plan (spectre-security → spectre-suite)

**Date:** 2026-11-07  
**Status:** draft — **decision required** (highest drift risk)  
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
- [ ] Produce control-mapping matrix (CSV/MD) for suite `security.*` vs spectre-security packages/tests.
- [ ] Implement a **nested→suite input adapter** for `current-infrastructure.json`-style data (enables `SECURITY_OPA_COMPAT` to run meaningfully against suite policies or a bridged ruleset).
- [ ] Decide k8s admission/versions location and CI treatment.
- [ ] Only after mapping+tests: merge/rename packages with CI count/baseline updates in the same, verified change.

## 6. Decision needed
Please choose **A**, **B**, or **C** (or constraints). Default recommendation: **A now, evolve to C** (shared core + adapters) once the control-mapping matrix and adapter tests are green. I will not change OPA packages/gates in a breaking way without this decision and passing CI checks.