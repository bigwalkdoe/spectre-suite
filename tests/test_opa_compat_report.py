"""Validation for the SECURITY_OPA_COMPAT report runner (Path C groundwork, additive).

The compat report adapts legacy nested spectre-security infrastructure data to
the suite's canonical flat contract, evaluates it against `spectre/policies`, and
emits a report (mapped/unmapped/denials). It is report-only: exit code 0 means a
report was produced; denials are informational under the Option A adapter flow.
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "spectre/actions/security/baseline/opa-compat-report.py"
POLICY_DIR = ROOT / "spectre" / "policies"


def run_report(src: dict, *args: str) -> tuple[int, dict | None]:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump(src, tf)
        tf.flush()
        path = tf.name
    try:
        p = subprocess.run(
            [sys.executable, str(TOOL), path, *args],
            text=True,
            capture_output=True,
        )
        report = None
        if p.stdout.strip():
            try:
                report = json.loads(p.stdout)
            except Exception:
                report = None
        return p.returncode, report
    finally:
        Path(path).unlink(missing_ok=True)


def test_compat_report_produces_report_for_mapped_nested_input():
    rc, d = run_report({
        "compliance": {
            "firewall_enabled": True,
            "ssh_password_auth": False,
            "audit_logging_enabled": True,
            "intrusion_detection_active": True,
            "file_integrity_monitoring": True,
            "security_scanning_enabled": True,  # unmapped -> fail-closed
        },
        "network": {"vpn_enabled": True},
        "backup": {"encrypted": True, "retention_days": 30, "offsite_replication": True},
        "docker": [{"name": "a", "privileged": False, "memory_limit": 1024}],
    }, "--policy-dir", str(POLICY_DIR))
    assert rc == 0
    assert d is not None
    assert d["policy_dir"] == str(POLICY_DIR)
    assert d["mapped_count"] >= 1
    assert d["mapped_fields"]
    assert isinstance(d["denial_count"], int)
    assert isinstance(d["denials"], list)
    assert "unmapped_suite_controls_note" in d


def test_compat_report_is_report_only_even_when_denials_present():
    # Violating a mapped control (firewall disabled) -> denial; must still exit 0 (report-only).
    rc, d = run_report({
        "compliance": {"firewall_enabled": False, "ssh_password_auth": False},
        "network": {}, "backup": {}, "docker": [],
    }, "--policy-dir", str(POLICY_DIR))
    assert rc == 0
    assert d is not None
    assert d["denial_count"] >= 1
    assert any("firewall" in str(m).lower() for m in d["denials"])


def test_compat_report_unmapped_controls_fail_closed_and_reported():
    rc, d = run_report(
        {"compliance": {}, "network": {}, "backup": {}, "docker": []},
        "--policy-dir", str(POLICY_DIR),
        "--verbose",
    )
    assert rc == 0
    assert d is not None
    # No mappings -> fail-closed suite denials; mapped_count == 0; unmapped note present.
    assert d["mapped_count"] == 0
    assert d["denial_count"] > 0
    assert d["unmapped_suite_controls_note"]
