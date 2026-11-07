"""Validation for Path C core contract groundwork (additive).

Ensures `spectre/policies/contract/mapping.v1.json` stays machine-checkable and
consistent with implemented adapter slices and suite policy inputs. Does NOT
change policy behavior or CI gates.
"""
from __future__ import annotations

import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / "spectre" / "policies" / "contract" / "mapping.v1.json"
POLICY_DIR = ROOT / "spectre" / "policies"
LINT_WORKFLOW = ROOT / ".github" / "workflows" / "lint.yml"


def load_mapping() -> dict:
    return json.loads(CONTRACT.read_text(encoding="utf-8"))


def policy_packages() -> dict[str, dict]:
    """Map package name -> {file, fields} from canonical spectre/policies/*.rego."""
    packages: dict[str, dict] = {}
    for p in POLICY_DIR.glob("*.rego"):
        text = p.read_text(encoding="utf-8")
        m = re.search(r"^package\s+([a-zA-Z0-9_.]+)", text, re.MULTILINE)
        if not m:
            continue
        fields: set[str] = set()
        fields.update(re.findall(r"input\.([a-zA-Z0-9_]+)", text))
        fields.update(re.findall(r'object\.get\(input,\s*["\']([a-zA-Z0-9_]+)["\']', text))
        packages[m.group(1)] = {"file": p.name, "fields": fields}
    return packages


def policy_input_fields() -> set[str]:
    fields: set[str] = set()
    for pkg in policy_packages().values():
        fields.update(pkg["fields"])
    return fields


def _opa_available() -> bool:
    return shutil.which("opa") is not None


def _opa_len(query: str, input_path: str) -> int | None:
    r = subprocess.run(
        ["opa", "eval", "--format", "raw", "--data", str(POLICY_DIR), "--input", input_path, query],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return None
    try:
        out = json.loads(r.stdout)
        return len(out) if isinstance(out, list) else None
    except Exception:
        return None


def test_contract_mapping_exists_and_is_valid_json():
    assert CONTRACT.exists(), f"missing {CONTRACT}"
    m = load_mapping()
    assert m["version"] == 1
    assert m["core"]["aggregation"] == "data.security[k].deny[m]"
    assert m["core"]["policy_dir"] == "spectre/policies"
    assert m["adapters"]["nested_infra_to_suite_flat"]["mappings"]
    assert m["adapters"]["k8s_admission"]["isolated"] is True


def test_core_ci_invariants_match_policy_contract():
    """Mapping records CI invariants; verify they reflect actual core contract (no gate changes)."""
    m = load_mapping()
    inv = m["core"]["ci_invariants"]
    assert inv["empty_input_min_denials"] == 38
    assert inv["baseline_denials"] == 0
    if not _opa_available():
        pytest.skip("opa not available")
    r = subprocess.run(["opa", "check", str(POLICY_DIR)], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        tf.write("{}")
        empty = tf.name
    try:
        empty_count = _opa_len("[m | data.security[k].deny[m]]", empty)
        baseline_count = _opa_len(
            "[m | data.security[k].deny[m]]", str(POLICY_DIR / "baseline.json")
        )
    finally:
        Path(empty).unlink(missing_ok=True)
    assert empty_count is not None and empty_count >= 38
    assert baseline_count == 0


def test_nested_adapter_mapping_fields_exist_in_suite_policies():
    fields = policy_input_fields()
    adapter = load_mapping()["adapters"]["nested_infra_to_suite_flat"]
    assert adapter["implemented"] == "spectre/actions/security/baseline/opa-contract-adapter.py"
    assert (ROOT / adapter["implemented"]).exists()
    for entry in adapter["mappings"]:
        sf = entry["suite_field"]
        assert sf in fields, f"mapped suite_field {sf!r} not found as input.* in {POLICY_DIR}/*.rego"
        assert entry.get("suite_packages"), f"{sf} must declare suite_packages"


def test_nested_adapter_suite_packages_are_real_and_use_mapped_field():
    """Each declared suite_package must exist and actually consume the mapped field."""
    packages = policy_packages()
    adapter = load_mapping()["adapters"]["nested_infra_to_suite_flat"]
    for entry in adapter["mappings"]:
        sf = entry["suite_field"]
        for pkg in entry["suite_packages"]:
            assert pkg in packages, f"suite_package {pkg!r} (for {sf}) is not a package in {POLICY_DIR}"
            assert sf in packages[pkg]["fields"], (
                f"{sf!r} mapped to {pkg!r}, but {packages[pkg]['file']} does not consume input.{sf}"
            )


def test_nested_adapter_never_invented_examples_absent_from_mapping():
    """The contract must not both map a field and warn about never inventing it."""
    adapter = load_mapping()["adapters"]["nested_infra_to_suite_flat"]
    mapped = {entry["suite_field"] for entry in adapter["mappings"]}
    examples = set(adapter["suite_controls_never_invented_examples"])
    assert not (mapped & examples), f"contradictory contract: mapped and never-invented: {mapped & examples}"
    fields = policy_input_fields()
    for ex in examples:
        assert ex in fields, f"never-invented example {ex!r} is not a known suite input field"


def test_k8s_admission_adapter_is_isolated():
    k8s = load_mapping()["adapters"]["k8s_admission"]
    assert k8s["isolated"] is True
    assert "NOT in data.security[k].deny" in k8s["aggregation"]
    for key in ("implemented", "policy", "test", "versions_index", "versions_metadata", "versions_report"):
        assert (ROOT / k8s[key]).exists(), f"missing k8s contract asset: {k8s[key]}"


def test_k8s_vendored_policy_is_not_a_security_core_package():
    """Vendored k8s policy must stay in kubernetes.* and out of data.security[k].deny."""
    k8s = load_mapping()["adapters"]["k8s_admission"]
    text = (ROOT / k8s["policy"]).read_text(encoding="utf-8")
    m = re.search(r"^package\s+([a-zA-Z0-9_.]+)", text, re.MULTILINE)
    assert m is not None
    assert m.group(1) == "kubernetes.admission"
    assert not m.group(1).startswith("security.")


def test_k8s_ci_gate_reflects_isolated_lint_job():
    """Contract must accurately describe isolated k8s CI enforcement (track 3, additive)."""
    m = load_mapping()
    k8s = m["adapters"]["k8s_admission"]
    assert "lint.yml" in k8s["ci_gate"]
    assert "NOT core aggregation" in k8s["ci_gate"] or "data.security[k].deny" in k8s["ci_gate"]
    assert LINT_WORKFLOW.exists()
    wf = LINT_WORKFLOW.read_text(encoding="utf-8")
    assert re.search(r"^\s*opa-isolated-k8s:\s*$", wf, re.MULTILINE), "lint.yml missing opa-isolated-k8s job"
    assert "opa check spectre/policies/k8s/" in wf
    assert "opa test spectre/policies/k8s/" in wf
    core_inv = m["core"].get("ci_invariants", {})
    assert "isolated_k8s_gate" in core_inv


def _load_nested_adapter_module():
    path = ROOT / "spectre/actions/security/baseline/opa-contract-adapter.py"
    spec = importlib.util.spec_from_file_location("opa_contract_adapter_mod", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_nested_adapter_emitted_fields_are_mapped_and_valid_suite_inputs():
    """Adapter may only emit confidently mappable suite fields (tracks 1/2 hardening)."""
    mod = _load_nested_adapter_module()
    mapping = load_mapping()["adapters"]["nested_infra_to_suite_flat"]
    mapped_fields = {e["suite_field"] for e in mapping["mappings"]}
    suite_fields = policy_input_fields()
    # Representative nested input exercising all implemented mapping slices.
    sample = {
        "compliance": {
            "firewall_enabled": True,
            "ssh_password_auth": False,
            "audit_logging_enabled": True,
            "intrusion_detection_active": True,
            "file_integrity_monitoring": True,
            "security_scanning_enabled": True,
        },
        "network": {"vpn_enabled": True, "open_ports": [22], "remote_access": True},
        "backup": {"encrypted": True, "retention_days": 30, "offsite_replication": True, "last_success_age": 1},
        "docker": [
            {
                "name": "app",
                "privileged": False,
                "memory_limit": 512,
                "healthcheck": "CMD true",
                "mounts": [],
                "ports": [{"host_ip": "127.0.0.1", "host_port": 80}],
            }
        ],
    }
    adapted, report = mod.map_nested_to_suite(sample)
    for field in adapted:
        assert field in mapped_fields, f"adapter emitted {field!r} but it is not in contract mapping"
        assert field in suite_fields, f"adapter emitted {field!r} but it is not consumed by suite policies"
    assert isinstance(report.get("mapped"), list)
    # Report must not claim mappings for fields absent from adapted output.
    for entry in report["mapped"]:
        assert entry["suite_field"] in adapted
    # Docker evidence is report-only metadata, never policy input.
    if "docker_evidence" in report:
        assert report["docker_evidence"].get("report_only") is True
        for k in ("sensitive_bind_mounts", "exposed_all_interfaces", "missing_healthcheck", "no_memory_limit"):
            assert k not in adapted


def test_contract_mapping_covers_core_package_input_surface():
    """Every canonical suite security.* control package remains represented by the core contract."""
    m = load_mapping()
    assert m["core"]["aggregation"] == "data.security[k].deny[m]"
    packages = policy_packages()
    # Exclude *_test rego packages; the aggregation contract targets canonical control packages.
    security_control_pkgs = {
        k for k in packages
        if k.startswith("security.") and not k.endswith("_test") and not k.startswith("security.test")
    }
    assert security_control_pkgs == {
        "security.audit",
        "security.backups",
        "security.compliance",
        "security.docker",
        "security.encryption",
        "security.firewall",
        "security.intrusion_detection",
        "security.network",
    }, f"unexpected canonical security control packages: {sorted(security_control_pkgs)}"
