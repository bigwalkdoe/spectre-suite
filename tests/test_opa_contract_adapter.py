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


# --- Option A adapter-tested slice: backup domain (spectre-security overlap) ---
# Ports overlapping backup cases through the adapter to canonical suite rego.
# No policy/gate changes; fail-closed count/baseline.json unchanged.

POLICY_DIR = ROOT / "spectre" / "policies"
OPA = Path.home() / ".local/bin/opa"
if not OPA.exists():
    OPA = Path("opa")


def _opa_available() -> bool:
    return subprocess.run([str(OPA), "version"], capture_output=True).returncode == 0


def suite_backups_deny(adapted: dict) -> list[str]:
    p = subprocess.run(
        [str(OPA), "eval", "--format", "raw", "--data", str(POLICY_DIR),
         "--input", "/dev/stdin", "data.security.backups.deny"],
        input=json.dumps(adapted),
        text=True,
        capture_output=True,
        check=True,
    )
    out = json.loads(p.stdout)
    return out if isinstance(out, list) else [str(out)]


def test_backup_slice_maps_overlapping_controls_to_suite():
    """Mapped backup fields (encrypted/retention/offsite) drive canonical suite denials."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {}, "network": {}, "backup": {
        "encrypted": True, "retention_days": 30, "offsite_replication": True,
    }, "docker": []})
    assert adapted["backup_encryption_enabled"] is True
    assert adapted["backup_retention_days"] == 30
    assert adapted["backup_offsite_enabled"] is True
    denials = suite_backups_deny(adapted)
    # 3 mapped controls satisfied; 3 unmapped suite-only controls remain fail-closed.
    assert not any("encryption" in d for d in denials)
    assert not any("retention" in d for d in denials)
    assert not any("off-site" in d for d in denials)
    assert any("restore verification" in d for d in denials)
    assert any("databases" in d for d in denials)
    assert any("docker volumes" in d for d in denials)
    assert len(denials) == 3


def test_backup_slice_missing_encryption_denied_by_suite():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    denials = suite_backups_deny(run_adapter({"compliance": {}, "network": {}, "backup": {
        "encrypted": False, "retention_days": 30, "offsite_replication": True,
    }, "docker": []}))
    assert any("encryption at rest" in d for d in denials)


def test_backup_slice_short_retention_denied_by_suite():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    denials = suite_backups_deny(run_adapter({"compliance": {}, "network": {}, "backup": {
        "encrypted": True, "retention_days": 3, "offsite_replication": True,
    }, "docker": []}))
    assert any("retention is under 7 days" in d for d in denials)


def test_backup_slice_missing_offsite_denied_by_suite():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    denials = suite_backups_deny(run_adapter({"compliance": {}, "network": {}, "backup": {
        "encrypted": True, "retention_days": 30, "offsite_replication": False,
    }, "docker": []}))
    assert any("off-site replication" in d for d in denials)


def test_backup_slice_multiple_mapped_violations_and_unmapped_fail_closed():
    """All mapped backup controls bad -> 3 mapped denials + 3 unmapped fail-closed = 6."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    denials = suite_backups_deny(run_adapter({"compliance": {}, "network": {}, "backup": {
        "encrypted": False, "retention_days": 3, "offsite_replication": False,
    }, "docker": []}))
    assert len(denials) == 6
    assert any("encryption" in d for d in denials)
    assert any("retention" in d for d in denials)
    assert any("off-site" in d for d in denials)


def test_backup_slice_last_success_age_is_evidence_only():
    """spectre-security last_success_age has no suite policy field; adapter must not invent one."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {}, "network": {}, "backup": {
        "encrypted": True, "retention_days": 30, "offsite_replication": True,
        "last_success_age": 90000,
    }, "docker": []})
    assert "last_success_age" not in adapted
    assert "backup_last_success_age" not in adapted
    # Staleness is not a suite backups control; mapped controls still satisfied.
    denials = suite_backups_deny(adapted)
    assert not any("encryption" in d for d in denials)
    assert not any("retention" in d for d in denials)
    assert not any("off-site" in d for d in denials)
