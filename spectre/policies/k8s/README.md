# Kubernetes admission policies (isolated)

Vendored isolated slice of the former `spectre-security` Kubernetes admission
policy so the report tool and tests run without the retired external repo.

- **Policy package:** `kubernetes.admission` (rego v1)
- **Query:** `data.kubernetes.admission.deny`
- **Aggregation:** **not** part of `data.security[k].deny`; no core CI gate change
- **Report:** `spectre/actions/security/opa/kubernetes-admission-report.py`
  (defaults to this vendored policy; `SPECTRE_SECURITY_ROOT` remains a fallback)
- **Versions:** `versions/index.json`, `versions/kubernetes-admission/v0.1.0/metadata.json`
  (report via `versions-index-report.py`). The index retains the original full
  retired-policy index for provenance; only k8s metadata is vendored here.

Provenance: vendored from the spectre-security archive
(`security/opa/policies/kubernetes-admission.rego` and
`security/opa/versions/kubernetes-admission/v0.1.0/`), version `0.1.0`,
commit `f160f6dea9a2d29e020bb9b6ecb40dce3f76cdbd`.

Run the isolated checks:

```bash
opa check spectre/policies/
opa test spectre/policies/
./spectre/policies/contract/check_isolation.sh
python3 -m pytest tests/test_k8s_admission_report.py -q
```
