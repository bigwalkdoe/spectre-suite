import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "spectre/actions/security/opa/versions-index-report.py"
SEC_ROOT = Path("/home/deon/dev/github/spectre-security/security/opa/versions")


def test_versions_index_report_isolated_and_lists_policies():
    if not SEC_ROOT.exists():
        pytest.skip("spectre-security OPA versions root not available")
    p = subprocess.run([sys.executable, str(TOOL)], text=True, capture_output=True, check=True)
    d = json.loads(p.stdout)
    assert d["domain"] == "opa.versions"
    assert d["isolated"] is True
    assert "NOT part of suite data.security[k].deny" in d["aggregation"]
    assert "index" in d and "policies" in d["index"]
    assert "kubernetes-admission" in d["policies"]
    assert d["policies"]["kubernetes-admission"]["latest_metadata"]["has_metadata"] is True


def test_versions_index_report_compact_omits_full_index_body():
    if not SEC_ROOT.exists():
        pytest.skip("spectre-security OPA versions root not available")
    p = subprocess.run([sys.executable, str(TOOL), "--compact"], text=True, capture_output=True, check=True)
    d = json.loads(p.stdout)
    assert d["isolated"] is True
    assert "index" not in d
    s = d["index_summary"]
    assert s["present"] is True and "kubernetes-admission" in s["policies"]


def test_versions_index_report_policy_filter():
    if not SEC_ROOT.exists():
        pytest.skip("spectre-security OPA versions root not available")
    p = subprocess.run([sys.executable, str(TOOL), "--policy", "kubernetes-admission", "--compact"],
                       text=True, capture_output=True, check=True)
    d = json.loads(p.stdout)
    assert d["isolated"] is True and d["policy_filter"] == "kubernetes-admission"
    assert list(d["policies"].keys()) == ["kubernetes-admission"]
    assert d["index_summary"]["policies"] == ["kubernetes-admission"]
