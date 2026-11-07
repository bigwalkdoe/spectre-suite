"""Validation for the isolated OPA CI gate workflow (Phase C groundwork).

Ensures `.github/workflows/opa-isolated-k8s.yml` contains the required isolated
k8s-admission job steps and does not run the core aggregation gate.
"""
from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "opa-isolated-k8s.yml"


def _workflow() -> dict:
    return yaml.safe_load(WORKFLOW.read_text(encoding="utf-8"))


def test_isolated_ci_gate_workflow_exists():
    assert WORKFLOW.exists(), f"missing isolated CI gate workflow: {WORKFLOW}"
    d = _workflow()
    assert str(d.get("name") or "").startswith("OPA Isolated")


def test_isolated_ci_gate_has_k8s_job_with_required_steps():
    d = _workflow()
    jobs = d.get("jobs") or {}
    assert "k8s-admission" in jobs, "isolated CI gate must define job 'k8s-admission'"
    steps = (jobs["k8s-admission"] or {}).get("steps") or []
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


def test_isolated_ci_gate_does_not_run_core_aggregation_gate():
    d = _workflow()
    jobs = d.get("jobs") or {}
    steps = (jobs["k8s-admission"] or {}).get("steps") or []
    runs = "\n".join(s.get("run") or "" for s in steps if s.get("name"))
    assert "data.security[k].deny" not in runs, "isolated gate must not run the core aggregation gate"
