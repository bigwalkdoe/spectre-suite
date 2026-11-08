#!/usr/bin/env python3
"""Path C live-infra normalizer (design step 3, additive).

Normalizes a live infra snapshot (v0 envelope or legacy nested shape) into:
- canonical flat suite policy input (OPA contract: data.security[k].deny consumers)
- an adapter/report envelope with contract/provenance metadata

Reuses `opa-contract-adapter.py` mapping rules. Never invents suite controls;
unmapped controls remain absent/fail-closed. Does not change policy behavior or
core CI/gate aggregation semantics.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
ADAPTER_PATH = SCRIPT_DIR / "opa-contract-adapter.py"
CONTRACT_V0 = "live_infra_snapshot/v0"


def _load_adapter_module():
    spec = importlib.util.spec_from_file_location("opa_contract_adapter_rules", ADAPTER_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load adapter: {ADAPTER_PATH}")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def load_snapshot(path: str) -> dict[str, Any]:
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def normalize(src: dict[str, Any], *, source_label: str = "") -> dict[str, Any]:
    adapter = _load_adapter_module()
    canonical_flat, adapter_report = adapter.map_nested_to_suite(src)
    snapshot_contract = dict(adapter_report.get("snapshot_contract") or {"contract": f"{CONTRACT_V0}-compatible"})
    if source_label and "source" not in snapshot_contract:
        snapshot_contract["source"] = source_label
    # Never include snapshot/provenance metadata in canonical flat policy input.
    for meta in ("contract_version", "source", "generated_at"):
        canonical_flat.pop(meta, None)
    return {
        "normalizer": {
            "name": "spectre-suite/live-infra-normalize",
            "step": "path-c/design-step-3",
            "adapter": str(ADAPTER_PATH.name),
            "normalized_at": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        },
        "snapshot_contract": snapshot_contract,
        "canonical_flat_input": canonical_flat,
        "adapter_report": adapter_report,
        "notes": [
            "canonical_flat_input contains only confidently mapped suite fields; unmapped suite controls are absent/fail-closed",
            "snapshot/provenance metadata is never emitted into canonical_flat_input",
            "report-only; does not change data.security[k].deny aggregation or CI gates",
        ],
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input", help="live infra snapshot JSON (v0 envelope or legacy nested shape), or - for stdin")
    ap.add_argument("--flat-output", "-f", help="write canonical flat OPA input JSON here (policy-safe, no metadata)")
    ap.add_argument("--normalized-output", "-n", help="write full normalized envelope JSON here (default: stdout)")
    ap.add_argument("--source-label", default="", help="provenance label when snapshot lacks source metadata")
    args = ap.parse_args()
    src = load_snapshot(args.input)
    env = normalize(src, source_label=args.source_label)
    if args.flat_output:
        Path(args.flat_output).write_text(
            json.dumps(env["canonical_flat_input"], indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    text = json.dumps(env, indent=2, sort_keys=True) + "\n"
    if args.normalized_output:
        Path(args.normalized_output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
