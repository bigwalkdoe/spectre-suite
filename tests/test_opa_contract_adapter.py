import json
import subprocess
import sys
import tempfile
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


def run_adapter_with_report(src: dict) -> tuple[dict, dict]:
    with tempfile.NamedTemporaryFile(suffix=".json") as rf:
        p = subprocess.run(
            [sys.executable, str(ADAPTER), "-", "--report", rf.name],
            input=json.dumps(src),
            text=True,
            capture_output=True,
            check=True,
        )
        report = json.loads(Path(rf.name).read_text())
    return json.loads(p.stdout), report


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


# --- Option A adapter-tested slice: network domain (spectre-security overlap) ---
# Direct map: network.vpn_enabled -> suite vpn_enabled (1/5 controls).
# open_ports/remote_access/container_network are evidence-only in the adapter (no 1:1
# suite network controls); suite-only segmentation/DMZ/internal/DDoS remain fail-closed.
# No policy/gate changes; fail-closed count/baseline.json unchanged.


def suite_network_deny(adapted: dict) -> list[str]:
    p = subprocess.run(
        [str(OPA), "eval", "--format", "raw", "--data", str(POLICY_DIR),
         "--input", "/dev/stdin", "data.security.network.deny"],
        input=json.dumps(adapted),
        text=True,
        capture_output=True,
        check=True,
    )
    out = json.loads(p.stdout)
    return out if isinstance(out, list) else [str(out)]


def test_network_slice_vpn_maps_and_unmapped_suite_controls_fail_closed():
    """vpn_enabled maps directly; 4 suite-only network controls remain fail-closed."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {}, "network": {
        "remote_access": True, "vpn_enabled": True, "container_network": "bridge",
        "open_ports": [22, 80, 443, 3002, 9090, 9093, 8081, 3100],
    }, "backup": {}, "docker": []})
    assert adapted["vpn_enabled"] is True
    denials = suite_network_deny(adapted)
    assert not any("VPN" in d or "vpn" in d for d in denials)
    assert any("segmentation" in d for d in denials)
    assert any("DMZ" in d for d in denials)
    assert any("internal network" in d for d in denials)
    assert any("DDoS" in d for d in denials)
    assert len(denials) == 4


def test_network_slice_vpn_disabled_denied_by_suite():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    denials = suite_network_deny(run_adapter({"compliance": {}, "network": {
        "remote_access": True, "vpn_enabled": False, "container_network": "bridge",
        "open_ports": [22, 80, 443],
    }, "backup": {}, "docker": []}))
    assert any("no VPN is configured" in d for d in denials)


def test_network_slice_evidence_fields_not_invented_as_suite_controls():
    """remote_access/container_network/open_ports are evidence; adapter must not invent suite fields."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {}, "network": {
        "remote_access": True, "vpn_enabled": False, "container_network": "host",
        "open_ports": [22, 10001, 10002],
    }, "backup": {}, "docker": []})
    for k in ("remote_access", "container_network", "open_ports",
              "network_segmentation_enabled", "dmz_isolated",
              "internal_no_internet", "ddos_protection_enabled"):
        assert k not in adapted
    assert adapted["vpn_enabled"] is False
    denials = suite_network_deny(adapted)
    # vpn denied (mapped) + 4 suite-only fail-closed = 5
    assert len(denials) == 5
    assert any("no VPN is configured" in d for d in denials)


# --- Option A adapter-tested slice: docker domain (spectre-security overlap, evidence) ---
# Legacy docker.security is per-container (privileged/mounts/memory_limit/0.0.0.0 ports/healthcheck)
# vs suite security.docker global/flat (5 controls). Adapter derives docker_privileged_disabled and
# heuristically docker_resource_limits when ALL containers declare memory_limit>0. Sensitive mounts,
# 0.0.0.0 exposure, and missing healthcheck are evidence-only (report metadata) with NO suite control
# mapping/invention; docker_not_root/no_new_privileges/userland_proxy_disabled remain fail-closed.
# Report metadata is emitted only via --report (out of policy input). No policy/gate changes.


def suite_docker_deny(adapted: dict) -> list[str]:
    p = subprocess.run(
        [str(OPA), "eval", "--format", "raw", "--data", str(POLICY_DIR),
         "--input", "/dev/stdin", "data.security.docker.deny"],
        input=json.dumps(adapted),
        text=True,
        capture_output=True,
        check=True,
    )
    out = json.loads(p.stdout)
    return out if isinstance(out, list) else [str(out)]


def test_docker_slice_privileged_and_resource_limits_derived_to_suite():
    """Derived globals map to suite; unmapped global controls remain fail-closed."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    # No privileged, all have memory limits -> 2 derived controls satisfied, 3 fail-closed.
    denials = suite_docker_deny(run_adapter({"compliance": {}, "network": {}, "backup": {}, "docker": [
        {"name": "a", "privileged": False, "memory_limit": 2147483648},
        {"name": "b", "privileged": False, "memory_limit": 1073741824},
    ]}))
    assert not any("privileged containers" in d for d in denials)
    assert not any("resource limits" in d for d in denials)
    assert any("dockerd must not run as root" in d for d in denials)
    assert any("no-new-privileges" in d for d in denials)
    assert any("userland-proxy" in d for d in denials)
    assert len(denials) == 3


def test_docker_slice_privileged_container_denied_by_suite():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    denials = suite_docker_deny(run_adapter({"compliance": {}, "network": {}, "backup": {}, "docker": [
        {"name": "ok", "privileged": False, "memory_limit": 1024},
        {"name": "priv-app", "privileged": True, "memory_limit": 1024},
    ]}))
    assert any("privileged containers are enabled" in d for d in denials)


def test_docker_slice_resource_limits_not_asserted_when_any_missing_fail_closed():
    """Heuristic only asserts docker_resource_limits when ALL containers declare memory_limit>0."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {}, "network": {}, "backup": {}, "docker": [
        {"name": "ok", "privileged": False, "memory_limit": 1024},
        {"name": "nolimit", "privileged": False, "memory_limit": 0},
    ]})
    assert "docker_resource_limits" not in adapted  # not invented when heuristic not met
    denials = suite_docker_deny(adapted)
    assert any("containers have no resource limits" in d for d in denials)
    assert not any("privileged containers" in d for d in denials)


def test_docker_slice_evidence_only_findings_do_not_invent_suite_controls():
    """Sensitive mounts, 0.0.0.0 ports, missing healthcheck -> report evidence only, no suite mapping."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {}, "network": {}, "backup": {}, "docker": [
        {"name": "risky", "privileged": False, "memory_limit": 1024,
         "mounts": [{"source": "/etc/passwd"}],
         "ports": [{"host_ip": "0.0.0.0", "host_port": 8080}],
         "healthcheck": ""},
    ]})
    # Derived globals may be asserted (no privilege, has mem limit); never invent these:
    for k in ("docker_not_root", "docker_no_new_privileges", "docker_userland_proxy_disabled",
              "sensitive_bind_mounts", "exposed_all_interfaces", "missing_healthcheck",
              "mounts", "ports", "healthcheck", "docker_evidence"):
        assert k not in adapted
    denials = suite_docker_deny(adapted)
    # 2 derived satisfied + 3 unmapped global controls fail-closed = 3 (evidence issues not suite controls)
    assert len(denials) == 3
    assert not any("privileged containers" in d for d in denials)
    assert not any("resource limits" in d for d in denials)


def test_docker_slice_report_metadata_out_of_policy_input():
    """--report carries docker_evidence metadata; adapted policy input does not."""
    import pytest
    adapted, report = run_adapter_with_report({"compliance": {}, "network": {}, "backup": {}, "docker": [
        {"name": "bad-app", "privileged": True, "memory_limit": 0,
         "mounts": [{"source": "/etc/passwd"}, {"source": "/data/app"}],
         "ports": [{"host_ip": "0.0.0.0", "host_port": 8080}, {"host_ip": "127.0.0.1", "host_port": 9090}],
         "healthcheck": ""},
        {"name": "ok", "privileged": False, "memory_limit": 2048,
         "mounts": [{"source": "/data/ok"}], "ports": [{"host_ip": "127.0.0.1", "host_port": 3000}],
         "healthcheck": "curl -f http://localhost:3000/health"},
    ]})
    assert "docker_evidence" not in adapted
    ev = report["docker_evidence"]
    assert ev["report_only"] is True
    assert ev["container_count"] == 2
    assert ev["privileged_containers"] == ["bad-app"]
    assert "bad-app" in ev["no_memory_limit"]
    assert {"container": "bad-app", "source": "/etc/passwd"} in ev["sensitive_bind_mounts"]
    assert all(m["source"] != "/data/app" for m in ev["sensitive_bind_mounts"])
    assert {"container": "bad-app", "host_port": 8080} in ev["exposed_all_interfaces"]
    assert "bad-app" in ev["missing_healthcheck"]
    assert "ok" not in ev["missing_healthcheck"]


# --- Option A adapter-tested slice: security-compliance overlap (careful, not 1:1) ---
# Legacy security.compliance maps selected compliance.* fields into flat fields consumed by
# MULTIPLE suite packages (security.firewall/audit/intrusion_detection) — NOT into suite
# security.compliance (which has different controls: baseline/cis/pci/assessments/patch).
# security_scanning_enabled and fail2ban_active/fail2ban_configured (from IDS alone) are not
# asserted/invented. Unmapped suite controls in each package remain fail-closed.
# No policy/gate changes; fail-closed count/baseline.json unchanged.


def _suite_deny(pkg: str, adapted: dict) -> list[str]:
    p = subprocess.run(
        [str(OPA), "eval", "--format", "raw", "--data", str(POLICY_DIR),
         "--input", "/dev/stdin", f"data.security.{pkg}.deny"],
        input=json.dumps(adapted),
        text=True,
        capture_output=True,
        check=True,
    )
    out = json.loads(p.stdout)
    return out if isinstance(out, list) else [str(out)]


LEGACY_COMPLIANT = {
    "compliance": {
        "firewall_enabled": True,
        "ssh_password_auth": False,
        "audit_logging_enabled": True,
        "intrusion_detection_active": True,
        "file_integrity_monitoring": True,
        "security_scanning_enabled": True,  # unmapped in suite
    },
    "network": {}, "backup": {}, "docker": [],
}


def test_compliance_slice_maps_into_relevant_suite_packages_not_suite_compliance():
    """Mapped legacy compliance fields satisfy their suite package controls; suite compliance pkg stays fail-closed (not 1:1)."""
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter(LEGACY_COMPLIANT)
    # mapped flat fields present
    assert adapted["firewall_enabled"] is True
    assert adapted["ssh_password_auth"] is False
    assert adapted["audit_logging_enabled"] is True
    assert adapted["intrusion_detection_active"] is True
    assert adapted["file_integrity_monitoring"] is True
    assert "security_scanning_enabled" not in adapted  # no suite control

    fw = _suite_deny("firewall", adapted)
    assert not any("firewalld is not active" in d for d in fw)
    assert not any("SSH password authentication is enabled" in d for d in fw)
    # unmapped suite firewall controls remain fail-closed
    assert any("SSH root login is enabled" in d for d in fw)
    assert any("fail2ban is not active" in d for d in fw)
    assert len(fw) == 2

    audit = _suite_deny("audit", adapted)
    assert not any("auditd/audit logging is not enabled" in d for d in audit)
    assert any("retention is under 90 days" in d for d in audit)
    assert any("sudo logging is not enabled" in d for d in audit)
    assert len(audit) == 2

    ids = _suite_deny("intrusion_detection", adapted)
    assert not any("intrusion detection is not enabled" in d for d in ids)
    assert not any("file integrity monitoring is not enabled" in d for d in ids)
    # fail2ban_configured NOT asserted from intrusion_detection_active alone
    assert any("fail2ban is not configured" in d for d in ids)
    assert any("log monitoring is not enabled" in d for d in ids)
    assert any("alert thresholds are not configured" in d for d in ids)
    assert len(ids) == 3

    # suite security.compliance has DIFFERENT controls; legacy fields do not satisfy/invent them
    comp = _suite_deny("compliance", adapted)
    assert len(comp) == 5
    for k in ("security_baseline_compliant", "cis_benchmarks_followed", "pci_dss_compliant",
              "security_assessments_scheduled", "patch_management_active"):
        assert k not in adapted


def test_compliance_slice_disabled_firewall_and_ssh_password_map_to_suite_firewall():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {"firewall_enabled": False, "ssh_password_auth": True},
                           "network": {}, "backup": {}, "docker": []})
    fw = _suite_deny("firewall", adapted)
    assert any("firewalld is not active" in d for d in fw)
    assert any("SSH password authentication is enabled" in d for d in fw)


def test_compliance_slice_audit_and_ids_fields_map_to_suite_packages():
    import pytest
    if not _opa_available():
        pytest.skip("opa not available")
    adapted = run_adapter({"compliance": {"audit_logging_enabled": False, "intrusion_detection_active": False,
                                          "file_integrity_monitoring": False},
                           "network": {}, "backup": {}, "docker": []})
    assert any("auditd/audit logging is not enabled" in d for d in _suite_deny("audit", adapted))
    ids = _suite_deny("intrusion_detection", adapted)
    assert any("intrusion detection is not enabled" in d for d in ids)
    assert any("file integrity monitoring is not enabled" in d for d in ids)


def test_compliance_slice_unmapped_security_scanning_not_invented():
    adapted, report = run_adapter_with_report({"compliance": {"security_scanning_enabled": False},
                                               "network": {}, "backup": {}, "docker": []})
    assert "security_scanning_enabled" not in adapted
    # no suite field invented; mapping report doesn't claim a suite field for it
    assert all(m["suite_field"] != "security_scanning_enabled" for m in report.get("mapped", []))


def test_explicit_unambiguous_unmapped_controls_never_invented():
    """Cross-check: adapter must not invent suite controls with no confident mapping (fail-closed)."""
    adapted = run_adapter({
        "compliance": {
            "firewall_enabled": True, "ssh_password_auth": False, "audit_logging_enabled": True,
            "intrusion_detection_active": True, "file_integrity_monitoring": True,
            "security_scanning_enabled": True,
        },
        "network": {"vpn_enabled": True, "open_ports": [22, 10001], "remote_access": True, "container_network": "host"},
        "backup": {"encrypted": True, "retention_days": 30, "offsite_replication": True, "last_success_age": 1},
        "docker": [{"name": "a", "privileged": False, "memory_limit": 1024, "healthcheck": "", "mounts": [{"source": "/etc/x"}], "ports": [{"host_ip": "0.0.0.0", "host_port": 80}]}],
    })
    for k in (
        # not derived from intrusion_detection_active alone
        "fail2ban_active", "fail2ban_configured",
        # suite-only firewall/audit/ids controls with no legacy source
        "ssh_root_login", "audit_retention_days", "sudo_logging_enabled",
        "log_monitoring_enabled", "alert_thresholds_configured",
        # suite compliance package controls (not 1:1)
        "security_baseline_compliant", "cis_benchmarks_followed", "pci_dss_compliant",
        "security_assessments_scheduled", "patch_management_active",
        # unmapped network/backup/docker evidence or suite-only
        "network_segmentation_enabled", "dmz_isolated", "internal_no_internet", "ddos_protection_enabled",
        "backup_verification_enabled", "database_backups_enabled", "docker_volume_backups_enabled",
        "docker_not_root", "docker_no_new_privileges", "docker_userland_proxy_disabled",
        "security_scanning_enabled", "last_success_age", "open_ports", "remote_access", "container_network",
    ):
        assert k not in adapted, f"{k} must not be invented (fail-closed)"


def test_backup_retention_days_non_integer_not_mapped_fail_closed():
    """Locks existing adapter behavior (no new mapping): non-integer retention is skipped, not invented."""
    adapted, report = run_adapter_with_report({"compliance": {}, "network": {}, "backup": {
        "encrypted": True, "retention_days": "not-a-number", "offsite_replication": True,
    }, "docker": []})
    assert "backup_retention_days" not in adapted  # skipped -> fail-closed in suite policy
    assert any("retention_days" in n for n in report.get("notes", []))
