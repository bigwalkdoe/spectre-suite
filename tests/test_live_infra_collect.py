"""Path C step 4 Slice A: suite-native live-infra collector (compliance+backup).

Fixture-driven, no host deps. Proves v0 snapshot production + normalizer/adapter
parity without changing core policy/gate/aggregation semantics.
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
COLLECTOR = ROOT / "spectre/actions/security/baseline/live-infra-collect.py"
NORMALIZER = ROOT / "spectre/actions/security/baseline/live-infra-normalize.py"
ADAPTER = ROOT / "spectre/actions/security/baseline/opa-contract-adapter.py"
V0_SCHEMA = ROOT / "tests/fixtures/live_infra_snapshot/live_infra_snapshot.v0.schema.json"
POLICY_DIR = ROOT / "spectre/policies"

COMPLIANCE_BACKUP_EVIDENCE = {
    "compliance": {
        "firewall_enabled": True,
        "ssh_password_auth": False,
        "audit_logging_enabled": True,
        "intrusion_detection_active": True,
        "file_integrity_monitoring": True,
    },
    "backup": {
        "encrypted": True,
        "retention_days": 30,
        "offsite_replication": True,
    },
}


def _load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_collect_compliance_backup_produces_valid_v0_snapshot():
    try:
        import jsonschema  # type: ignore
    except Exception as exc:  # pragma: no cover
        pytest.skip(f"jsonschema unavailable: {exc}")
    collector = _load(COLLECTOR, "live_infra_collect_mod")
    snap = collector.collect_snapshot(COMPLIANCE_BACKUP_EVIDENCE, domains=["compliance", "backup"], source="test/slice-a")
    schema = json.loads(V0_SCHEMA.read_text(encoding="utf-8"))
    jsonschema.Draft202012Validator(schema).validate(snap)
    assert snap["contract_version"] == "live_infra_snapshot/v0"
    assert snap["source"] == "test/slice-a"
    assert set(snap["compliance"].keys()) == set(COMPLIANCE_BACKUP_EVIDENCE["compliance"].keys())
    assert snap["backup"]["retention_days"] == 30
    # Uncollected domains present as safe empty containers (schema-required).
    assert snap["docker"] == []
    assert snap["network"] == {}


def test_collect_does_not_invent_never_mapped_controls():
    collector = _load(COLLECTOR, "live_infra_collect_mod")
    evidence = {
        "compliance": {"firewall_enabled": False, "security_scanning_enabled": True},
        "backup": {"encrypted": False},
    }
    snap = collector.collect_snapshot(evidence, domains=["compliance", "backup"])
    # Collector passes through provided evidence fields; it must not inject never-invented suite truths.
    for never in ("security_baseline_compliant", "fail2ban_active", "patch_management_active", "docker_not_root"):
        assert never not in snap["compliance"]
        assert never not in snap["backup"]
        assert never not in snap
    # Evidence-only field may be present in snapshot evidence but adapter will not map it; collector must not convert it.
    assert snap["compliance"].get("security_scanning_enabled") is True


def test_collector_normalizer_adapter_parity():
    collector = _load(COLLECTOR, "live_infra_collect_mod")
    normalizer = _load(NORMALIZER, "live_infra_normalize_parity")
    snap = collector.collect_snapshot(COMPLIANCE_BACKUP_EVIDENCE, domains=["compliance", "backup"])
    env = normalizer.normalize(snap)
    flat = env["canonical_flat_input"]
    # Mapped compliance+backup fields present.
    for k in ("firewall_enabled", "ssh_password_auth", "audit_logging_enabled", "intrusion_detection_active",
              "file_integrity_monitoring", "backup_encryption_enabled", "backup_retention_days", "backup_offsite_enabled"):
        assert k in flat, k
    assert "fail2ban_active" not in flat
    assert "backup_verification_enabled" not in flat


def _opa_eval_denials(flat_input: dict) -> list | None:
    r = subprocess.run(
        ["opa", "eval", "--format", "raw", "--data", str(POLICY_DIR), "--input", "/dev/stdin", "[m | data.security[k].deny[m]]"],
        input=json.dumps(flat_input),
        text=True,
        capture_output=True,
    )
    if r.returncode != 0:
        return None
    try:
        out = json.loads(r.stdout)
        return out if isinstance(out, list) else None
    except Exception:
        return None


def test_collector_slice_parity_preserves_core_gate_invariants():
    """OPA eval on collected+normalized input behaves consistently; core 38/0 unchanged."""
    if subprocess.run(["opa", "version"], capture_output=True).returncode != 0:
        pytest.skip("opa not available")
    collector = _load(COLLECTOR, "live_infra_collect_mod")
    normalizer = _load(NORMALIZER, "live_infra_normalize_gate")
    snap = collector.collect_snapshot(COMPLIANCE_BACKUP_EVIDENCE, domains=["compliance", "backup"])
    flat = normalizer.normalize(snap)["canonical_flat_input"]
    denials = _opa_eval_denials(flat)
    assert denials is not None
    # Mapped domains satisfied, but docker/network/encryption/other suite controls remain absent/fail-closed.
    assert not any("backups:" in d and "encrypted" in d for d in denials)
    assert not any("firewall not enabled" in d for d in denials)
    assert len(denials) >= 1  # fail-closed for uncollected/unmapped controls
    # Core invariants unchanged.
    assert _opa_eval_denials({}) is not None and len(_opa_eval_denials({})) >= 38
    assert _opa_eval_denials(json.loads((POLICY_DIR / "baseline.json").read_text())) == []


def test_collector_cli_from_evidence(tmp_path):
    ev = tmp_path / "evidence.json"
    out = tmp_path / "snapshot.json"
    ev.write_text(json.dumps(COMPLIANCE_BACKUP_EVIDENCE), encoding="utf-8")
    r = subprocess.run(
        [sys.executable, str(COLLECTOR), "--from-evidence", str(ev), "--domains", "compliance,backup", "--output", str(out), "--source", "test/cli"],
        capture_output=True,
        text=True,
        check=True,
    )
    assert r.returncode == 0
    snap = json.loads(out.read_text(encoding="utf-8"))
    assert snap["contract_version"] == "live_infra_snapshot/v0"
    assert snap["backup"]["encrypted"] is True
    assert snap["docker"] == []


# --- Slice B: best-effort read-only probes (opt-in). Deterministic tests via mocking. ---


def test_probe_compliance_omits_uncertain_fields(monkeypatch):
    collector = _load(COLLECTOR, "live_infra_collect_probe1")
    monkeypatch.setattr(collector.shutil, "which", lambda x: None)
    ev = collector._probe_compliance()
    # No tools/evidence => absent (fail-closed), never invented.
    assert ev == {}


def test_probe_compliance_maps_definitive_systemctl_states(monkeypatch):
    collector = _load(COLLECTOR, "live_infra_collect_probe2")
    monkeypatch.setattr(collector.shutil, "which", lambda x: "/usr/bin/systemctl" if x == "systemctl" else None)

    def fake_run(cmd, capture_output=True, text=True, timeout=5):
        unit = cmd[-1]
        out = {"firewalld": "active", "auditd": "inactive", "wazuh-agent": "inactive", "suricata": "inactive", "snort": "inactive"}.get(unit, "unknown")
        return subprocess.CompletedProcess(cmd, 0, out, "")

    monkeypatch.setattr(collector.subprocess, "run", fake_run)
    ev = collector._probe_compliance()
    assert ev["firewall_enabled"] is True
    assert ev["audit_logging_enabled"] is False  # definitive inactive
    assert "ssh_password_auth" not in ev  # never guessed
    assert "intrusion_detection_active" not in ev
    assert "file_integrity_monitoring" not in ev


def test_probe_backup_uses_nonsecret_markers_only(tmp_path, monkeypatch):
    collector = _load(COLLECTOR, "live_infra_collect_probe3")
    state = tmp_path / ".local/state/spectre-suite/backups"
    state.mkdir(parents=True)
    (state / "last-success").write_text("123 5a8836ff\n", encoding="utf-8")
    (state / "last-offsite-success").write_text("124 1ff42d3a\n", encoding="utf-8")
    monkeypatch.setattr(collector.Path, "home", staticmethod(lambda: tmp_path))
    ev = collector._probe_backup()
    assert ev == {"encrypted": True, "offsite_replication": True}
    assert "retention_days" not in ev


def test_probe_evidence_explicit_overrides_probe(monkeypatch, tmp_path):
    collector = _load(COLLECTOR, "live_infra_collect_probe4")
    monkeypatch.setattr(collector.shutil, "which", lambda x: None)
    evfile = tmp_path / "ev.json"
    evfile.write_text(json.dumps({"compliance": {"firewall_enabled": False}, "backup": {"retention_days": 14}}), encoding="utf-8")
    r = subprocess.run(
        [sys.executable, str(COLLECTOR), "--probe", "--from-evidence", str(evfile), "--domains", "compliance,backup", "--source", "test/probe"],
        capture_output=True,
        text=True,
        check=True,
    )
    snap = json.loads(r.stdout)
    assert snap["compliance"]["firewall_enabled"] is False  # explicit override
    assert snap["backup"]["retention_days"] == 14
    assert snap["source"] == "test/probe"


def test_collect_network_and_docker_domains_parity_with_existing_mappings():
    """Item 4 (additive): fixture-driven network/docker evidence uses existing mappings only."""
    collector = _load(COLLECTOR, "live_infra_collect_netdock")
    normalizer = _load(NORMALIZER, "live_infra_normalize_netdock")
    evidence = {
        "network": {"vpn_enabled": True},
        "docker": [{"name": "app", "privileged": False, "memory_limit": 512}],
    }
    snap = collector.collect_snapshot(evidence, domains=["network", "docker", "compliance", "backup"])
    assert snap["network"]["vpn_enabled"] is True
    assert snap["docker"][0]["name"] == "app"
    flat = normalizer.normalize(snap)["canonical_flat_input"]
    assert flat["vpn_enabled"] is True
    assert flat["docker_privileged_disabled"] is True
    assert flat["docker_resource_limits"] is True
    # Never invented from docker/network evidence
    for never in ("docker_not_root", "docker_no_new_privileges", "network_segmentation_enabled", "dmz_isolated"):
        assert never not in flat
