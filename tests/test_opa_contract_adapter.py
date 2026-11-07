import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADAPTER = ROOT / "spectre/actions/security/baseline/opa-contract-adapter.py"
FIXTURE = ROOT.parent / "spectre-security/security/test-data/current-infrastructure.json" if False else None


def run_adapter(src: dict) -> dict:
    p = subprocess.run(
        [sys.executable, str(ADAPTER), "-"],
        input=json.dumps(src),
        text=True,
        capture_output=True,
        check=True,
    )
    return json.loads(p.stdout)


def test_maps_direct_compliance_fields():
    out = run_adapter({
        "compliance": {"firewall_enabled": True, "ssh_password_auth": False, "audit_logging_enabled": True},
        "network": {}, "backup": {}, "docker": [],
    })
    assert out["firewall_enabled"] is True
    assert out["ssh_password_auth"] is False
    assert out["audit_logging_enabled"] is True


def test_maps_backup_and_network():
    out = run_adapter({
        "compliance": {}, "network": {"vpn_enabled": True},
        "backup": {"encrypted": True, "retention_days": 14, "offsite_replication": True},
        "docker": [],
    })
    assert out["backup_encryption_enabled"] is True
    assert out["backup_retention_days"] == 14
    assert out["backup_offsite_enabled"] is True
    assert out["vpn_enabled"] is True


def test_docker_privileged_disabled_derived():
    out = run_adapter({"compliance": {}, "network": {}, "backup": {}, "docker": [{"name": "a", "privileged": False}]})
    assert out["docker_privileged_disabled"] is True
    out2 = run_adapter({"compliance": {}, "network": {}, "backup": {}, "docker": [{"name": "a", "privileged": True}]})
    assert out2["docker_privileged_disabled"] is False


def test_does_not_invent_unmapped_controls():
    out = run_adapter({"compliance": {"firewall_enabled": True}, "network": {}, "backup": {}, "docker": []})
    # unmapped suite controls must be absent (fail-closed)
    assert "security_assessments_scheduled" not in out
    assert "patch_management_active" not in out
    assert "docker_not_root" not in out
