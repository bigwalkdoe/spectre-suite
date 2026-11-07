import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "spectre/actions/security/opa/kubernetes-admission-report.py"
OPA = Path.home() / ".local/bin/opa"
if not OPA.exists():
    OPA = Path("opa")
POLICY = Path("/home/deon/dev/github/spectre-security/security/opa/policies/kubernetes-admission.rego")


def _have_deps():
    return subprocess.run([str(OPA), "version"], capture_output=True).returncode == 0 and POLICY.exists()


def run_report(obj: dict, *args: str):
    p = subprocess.run(
        [sys.executable, str(TOOL), *args, "-"],
        input=json.dumps(obj),
        text=True,
        capture_output=True,
        check=False,
    )
    return p.returncode, json.loads(p.stdout) if p.stdout.strip() else {}


COMPLIANT = {
    "request": {"object": {
        "metadata": {"labels": {"pod-security.kubernetes.io/enforce": "restricted"}},
        "spec": {"containers": [{
            "name": "test",
            "securityContext": {"privileged": False, "runAsNonRoot": True, "runAsUser": 1000,
                                "readOnlyRootFilesystem": True, "capabilities": {"drop": ["ALL"]}},
            "resources": {"limits": {"memory": "512Mi", "cpu": "500m"}, "requests": {"memory": "256Mi", "cpu": "250m"}},
            "livenessProbe": {"httpGet": {"path": "/health", "port": 8080}},
            "readinessProbe": {"httpGet": {"path": "/ready", "port": 8080}},
        }]},
    }}
}


def test_k8s_admission_report_isolated_and_compliant_passes():
    if not _have_deps():
        pytest.skip("opa or spectre-security k8s policy not available")
    rc, d = run_report(COMPLIANT)
    assert rc == 0
    assert d["domain"] == "kubernetes.admission"
    assert d["isolated"] is True
    assert "NOT part of suite data.security[k].deny" in d["aggregation"]
    assert d["denial_count"] == 0
    # read-only/report-only version metadata surfacing (isolated)
    meta = d.get("policy_version_metadata") or {}
    assert meta.get("policy") in (None, "kubernetes-admission") or "kubernetes-admission" in str(meta.get("_metadata_path", ""))


def test_k8s_admission_report_denies_privileged_and_fail_on_deny():
    if not _have_deps():
        pytest.skip("opa or spectre-security k8s policy not available")
    obj = {"request": {"object": {"spec": {"containers": [{"name": "test", "securityContext": {"privileged": True}}]}}}}
    rc, d = run_report(obj)
    assert rc == 0  # report-only default
    assert d["denial_count"] > 0
    assert any("Privileged containers are not allowed" in m for m in d["denials"])
    rc2, _ = run_report(obj, "--fail-on-deny")
    assert rc2 == 1
