# Spectre Security Core Contract (Path C groundwork)

Additive contract assets for the Path C decision: **suite `data.security[k].deny`
aggregation is canonical**, with explicit adapters for legacy/nested inputs.
These files do **not** change policy behavior or CI gates.

See `docs/superpowers/specs/2026-11-07-opa-path-c-core-contract.md` and
`docs/superpowers/specs/2026-11-07-opa-governance-unification-plan.md`.

## Files

- `mapping.v1.json` — machine-checkable mapping for implemented adapter slices
  (source shape → suite flat field/package, evidence-only fields, isolated domains).
- `check_isolation.sh` — opt-in check that core gates stay green and k8s/versions
  domains are not aggregated into `data.security[k].deny` (no workflow change).

## Core invariants (must remain green)

```bash
opa check spectre/policies/
echo '{}' | ... # empty input must yield >= 38 denials (fail-closed)
opa eval ... --input spectre/policies/baseline.json # must yield 0 denials
```

`tests/test_opa_path_c_contract.py` validates the mapping against the real
policy packages/fields and verifies the recorded invariants.

## Adapter rule

Do **not** invent suite control values. Add mappings only with explicit,
unambiguous evidence/contract justification; unmapped suite controls remain
absent (`undefined`) so the canonical rego stays fail-closed.

## Isolated domains

`kubernetes.admission` and OPA versions metadata/index are report-only slices.
Vendored assets live under `spectre/policies/k8s/` (policy, tests, versions
index/metadata) and are intentionally **not** part of `data.security[k].deny`;
a separate gate requires an explicit, reviewed decision. The report tool defaults
to the vendored slice (`SPECTRE_SECURITY_ROOT` remains a fallback).

Run:

```bash
python3 -m pytest tests/test_opa_path_c_contract.py -q
opa test spectre/policies/
./spectre/policies/contract/check_isolation.sh
```

The isolated k8s/versions domain has a dedicated CI gate:
`.github/workflows/opa-isolated-k8s.yml` (isolated `opa check`/`opa test` +
isolation guard + opt-in check + report tests). It does not run the core OPA
aggregation gate.
