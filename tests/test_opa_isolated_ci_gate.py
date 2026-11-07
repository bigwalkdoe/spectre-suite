"""Validation for the merged isolated OPA CI gate in lint workflow (Phase 5 groundwork).

Ensures `.github/workflows/lint.yml` contains the required isolated k8s-admission
job steps and does not run the core aggregation gate.
"""
from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "lint.yml"


def _workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


def test_merged_lint_workflow_contains_isolated_k8s_job():
    assert WORKFLOW.exists(), f"missing lint workflow: {WORKFLOW}"
    d = _workflow()
    jobs = d.get("jobs") or {}
    assert "opa-isolated-k8s" in jobs, "merged lint workflow must define job 'opa-isolated-k8s'"
    steps = (jobs["opa-isolated-k8s"] or {}).get("steps") or []
    runs = [s.get("run") or "" for s in steps if s.get("name")]
    joined = "\n".join(runs)
    assert "opa check spectre/policies/k8s/" in joined
    assert "opa test spectre/policies/k8s/" in joined
    assert "check_isolation.sh" in joined
    assert "test_k8s_admission_report.py" in joined
    assert "test_opa_compat_report.py" in joined
    assert "test_opa_versions_index_report.py" in joined
    assert "test_opa_path_c_contract.py" in joined
    assert "test_opa_contract_adapter.py" in joined


def test_merged_lint_workflow_does_not_run_core_aggregation_gate():
    d = _workflow()
    jobs = d.get("jobs") or {}
    steps = (jobs["opa-isolated-k8s"] or {}).get("steps") or []
    runs = "\n".join(s.get("run") or "" for s in steps if s.get("name"))
    assert "data.security[k].deny" not in runs, "isolated job must not run the core aggregation gate"
