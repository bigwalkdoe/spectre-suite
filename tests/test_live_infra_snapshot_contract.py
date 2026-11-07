"""Path C live-infra snapshot contract v0 (design step 1/2, additive).

Validates the versioned nested snapshot envelope/fixtures used with
`opa-contract-adapter.py`. Does not change policy behavior or core CI gates.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DIR = ROOT / "spectre" / "policies" / "contract"
FIXTURES_DIR = ROOT / "tests" / "fixtures" / "live_infra_snapshot"
SCHEMA = FIXTURES_DIR / "live_infra_snapshot.v0.schema.json"
FIXTURES = sorted(FIXTURES_DIR.glob("live-infra-snapshot.v0*.json"))
ADAPTER = ROOT / "spectre/actions/security/baseline/opa-contract-adapter.py"
MAPPING = CONTRACT_DIR / "mapping.v1.json"


def _load_adapter():
    spec = importlib.util.spec_from_file_location("opa_contract_adapter_live", ADAPTER)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_live_infra_snapshot_v0_schema_and_fixtures_exist():
    assert SCHEMA.exists(), f"missing {SCHEMA}"
    assert FIXTURES, f"no v0 fixtures found in {FIXTURES_DIR}"
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    assert schema.get("title")
    req = set(schema.get("required") or [])
    assert {"docker", "network", "compliance", "backup"}.issubset(req)


def test_live_infra_snapshot_v0_fixtures_validate_and_adapter_accepts():
    try:
        import jsonschema  # type: ignore
    except Exception as exc:  # pragma: no cover
        pytest.skip(f"jsonschema unavailable: {exc}")
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)
    mapping = json.loads(MAPPING.read_text(encoding="utf-8"))
    mapped_fields = {e["suite_field"] for e in mapping["adapters"]["nested_infra_to_suite_flat"]["mappings"]}
    mod = _load_adapter()
    for fx in FIXTURES:
        data = json.loads(fx.read_text(encoding="utf-8"))
        validator.validate(data)
        adapted, report = mod.map_nested_to_suite(data)
        assert isinstance(adapted, dict), fx
        assert isinstance(report, dict), fx
        # Backward-compatible: metadata fields must not become suite policy inputs.
        for meta in ("contract_version", "source", "generated_at"):
            assert meta not in adapted, f"{meta} leaked into adapted input ({fx.name})"
        for field in adapted:
            assert field in mapped_fields, f"adapter emitted unmapped field {field!r} for {fx.name}"
        # Report-only docker evidence must never appear as policy input.
        for k in ("sensitive_bind_mounts", "exposed_all_interfaces", "missing_healthcheck", "no_memory_limit"):
            assert k not in adapted


def test_live_infra_snapshot_v0_example_covers_representative_mappings():
    mod = _load_adapter()
    fx = FIXTURES_DIR / "live-infra-snapshot.v0.example.json"
    data = json.loads(fx.read_text(encoding="utf-8"))
    adapted, _ = mod.map_nested_to_suite(data)
    # Representative mapped fields from the example (unambiguous evidence only).
    for expected in (
        "firewall_enabled",
        "ssh_password_auth",
        "audit_logging_enabled",
        "intrusion_detection_active",
        "file_integrity_monitoring",
        "vpn_enabled",
        "backup_encryption_enabled",
        "backup_retention_days",
        "backup_offsite_enabled",
        "docker_privileged_disabled",
        "docker_resource_limits",
    ):
        assert expected in adapted, f"expected mapped field missing: {expected}"
    # Evidence-only source fields must not be invented as suite controls.
    for never in ("security_baseline_compliant", "fail2ban_active", "docker_not_root", "network_segmentation_enabled"):
        assert never not in adapted
