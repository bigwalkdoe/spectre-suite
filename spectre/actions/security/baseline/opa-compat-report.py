#!/usr/bin/env python3
"""SECURITY_OPA_COMPAT report: adapt nested spectre-security infra JSON to suite
flat contract and evaluate against canonical spectre/policies (Option A).

Reports mapped/unmapped controls and denials. Does NOT modify policies/gates.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SUITE_ROOT = SCRIPT_DIR.parents[3]  # .../spectre-suite repo root
ADAPTER = SCRIPT_DIR / "opa-contract-adapter.py"
POLICY_DIR = SUITE_ROOT / "spectre" / "policies"


def run(cmd, **kw):
    return subprocess.run(cmd, text=True, capture_output=True, **kw)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?", default="", help="nested current-infrastructure.json (or set SECURITY_BASELINE_FILE)")
    ap.add_argument("--policy-dir", default=str(POLICY_DIR))
    ap.add_argument("--verbose", action="store_true", help="include report-only detail (e.g. docker_evidence per-container lists)")
    args = ap.parse_args()
    verbose = args.verbose or os.environ.get("SECURITY_OPA_COMPAT_VERBOSE", "") == "1"
    src = args.input or str(Path.home() / ".local/state/spectre/security-baseline/current-infrastructure.json")
    if not Path(src).exists():
        # compat fallback (spectre-security repo is archived; SPECTRE_SECURITY_ROOT may be set explicitly)
        sec_root = Path(os.environ.get("SPECTRE_SECURITY_ROOT", "/home/deon/dev/github/spectre-security"))
        cand = sec_root / "security/test-data/current-infrastructure.json"
        if cand.exists():
            src = str(cand)
        else:
            print(
                f"input not found: {src} (compat fallback also missing: {cand}; "
                "provide an explicit input path or set SECURITY_BASELINE_FILE/SPECTRE_SECURITY_ROOT as appropriate)",
                file=sys.stderr,
            )
            return 2
    with tempfile.TemporaryDirectory() as td:
        adapted = Path(td) / "adapted.json"
        report = Path(td) / "report.json"
        r = run([sys.executable, str(ADAPTER), src, "-o", str(adapted), "--report", str(report)])
        if r.returncode != 0:
            sys.stderr.write(r.stderr or r.stdout)
            return r.returncode
        mapping = json.loads(report.read_text())
        eval_r = run(["opa", "eval", "--format", "raw", "--data", args.policy_dir, "--input", str(adapted), "[m | data.security[k].deny[m]]"])
        denials = []
        if eval_r.returncode == 0:
            try:
                denials = json.loads(eval_r.stdout)
                if not isinstance(denials, list):
                    denials = [str(denials)]
            except Exception:
                denials = [f"(parse error: {eval_r.stdout[:200]})"]
        else:
            denials = [f"(opa eval failed rc={eval_r.returncode}: {(eval_r.stderr or eval_r.stdout)[:300]})"]
    summary = {
        "input": src,
        "policy_dir": args.policy_dir,
        "mapped_count": len(mapping.get("mapped", [])),
        "mapped_fields": [m["suite_field"] for m in mapping.get("mapped", [])],
        "denial_count": len(denials),
        "denials": denials,
        "adapter_notes": mapping.get("notes", []),
        "unmapped_suite_controls_note": mapping.get("unmapped_suite_controls_note", ""),
    }
    if "docker_evidence" in mapping:
        ev = mapping["docker_evidence"] or {}
        summary["docker_evidence"] = {
            "report_only": bool(ev.get("report_only", True)),
            "container_count": ev.get("container_count", 0),
            "privileged_count": len(ev.get("privileged_containers") or []),
            "no_memory_limit_count": len(ev.get("no_memory_limit") or []),
            "sensitive_bind_mount_count": len(ev.get("sensitive_bind_mounts") or []),
            "exposed_all_interfaces_count": len(ev.get("exposed_all_interfaces") or []),
            "missing_healthcheck_count": len(ev.get("missing_healthcheck") or []),
        }
        if verbose:
            summary["docker_evidence"].update({
                "privileged_containers": ev.get("privileged_containers") or [],
                "no_memory_limit": ev.get("no_memory_limit") or [],
                "sensitive_bind_mounts": ev.get("sensitive_bind_mounts") or [],
                "exposed_all_interfaces": ev.get("exposed_all_interfaces") or [],
                "missing_healthcheck": ev.get("missing_healthcheck") or [],
                "note": ev.get("note", ""),
            })
    print(json.dumps(summary, indent=2))
    # exit 0 = report produced (compat mode); denials are informational under Option A adapter.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
