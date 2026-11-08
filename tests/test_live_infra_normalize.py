"""Path C live-infra normalizer entrypoint (design step 3, additive).

Verifies the normalizer reuses adapter rules, preserves canonical flat policy
input safety (no provenance leakage), and attaches contract metadata. No policy
or CI gate changes.
"""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NORMALIZER = ROOT / "spectre/actions/security/baseline/live-infra-normalize.py"
FIXTURES = ROOT / "tests/fixtures/live_infra_snapshot"


def _load():
    spec = importlib.util.spec_from_file_location("live_infra_normalize_mod", NORMALIZER)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def test_normalize_v0_example_produces_flat_input_and_metadata():
    mod = _load()
    src = json.loads((FIXTURES / "live-infra-snapshot.v0.example.json").read_text(encoding="utf-8"))
    env = mod.normalize(src)
    flat = env["canonical_flat_input"]
    assert env["normalizer"]["step"] == "path-c/design-step-3"
    assert env["snapshot_contract"].get("contract_version") == "live_infra_snapshot/v0"
    assert env["snapshot_contract"].get("source") == "suite-fixture/example"
    # Provenance never leaks into canonical flat OPA input.
    for k in ("contract_version", "source", "generated_at", "snapshot_contract", "normalizer", "adapter_report"):
        assert k not in flat
    # Representative mapped fields present (adapter rules reused).
    assert flat["firewall_enabled"] is True
    assert flat["backup_encryption_enabled"] is True
    assert "security_baseline_compliant" not in flat


def test_normalize_legacy_shape_gets_contract_metadata_without_leaking():
    mod = _load()
    src = {"docker": [], "network": {}, "compliance": {"firewall_enabled": True}, "backup": {}}
    env = mod.normalize(src, source_label="test/legacy")
    assert env["snapshot_contract"].get("source") == "test/legacy"
    assert env["canonical_flat_input"] == {"firewall_enabled": True}


def test_normalizer_cli_writes_flat_and_envelope(tmp_path):
    src = FIXTURES / "live-infra-snapshot.v0.example.json"
    flat_out = tmp_path / "flat.json"
    norm_out = tmp_path / "norm.json"
    r = subprocess.run(
        [sys.executable, str(NORMALIZER), str(src), "--flat-output", str(flat_out), "--normalized-output", str(norm_out)],
        capture_output=True,
        text=True,
        check=True,
    )
    assert r.returncode == 0
    flat = json.loads(flat_out.read_text(encoding="utf-8"))
    env = json.loads(norm_out.read_text(encoding="utf-8"))
    assert "contract_version" not in flat
    assert "canonical_flat_input" in env
    assert env["canonical_flat_input"] == flat
