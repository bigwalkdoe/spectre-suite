#!/usr/bin/env python3
"""Kubernetes admission policy report (Option A compat slice, ISOLATED).

Evaluates AdmissionReview JSON against spectre-security's kubernetes.admission
policy (data.kubernetes.admission.deny). This is a SEPARATE domain from the
suite's infra baseline aggregation (data.security[k].deny) and MUST NOT be
merged into that aggregation or CI gates without an explicit decision.

Report-only by default (exit 0 when report produced). Use --fail-on-deny to
exit 1 when denials are present.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def _security_root() -> Path:
    return Path(os.environ.get("SPECTRE_SECURITY_ROOT", "~//dev/github/spectre-security"))


def find_policy(explicit: str) -> Path:
    if explicit:
        p = Path(explicit)
        if p.exists():
            return p
        print(f"policy not found: {p}", file=sys.stderr)
        raise SystemExit(2)
    root = _security_root()
    for cand in [
        root / "security/opa/policies/kubernetes-admission.rego",
        root / "security/opa/policies",
    ]:
        if cand.exists():
            return cand
    print(
        f"kubernetes admission policy not found; set --policy or SPECTRE_SECURITY_ROOT (tried {root}/security/opa/policies)",
        file=sys.stderr,
    )
    raise SystemExit(2)


def load_version_metadata(explicit: str = "") -> dict | None:
    """Read-only: surface spectre-security OPA version metadata (isolated/report-only)."""
    if explicit:
        p = Path(explicit)
        if p.is_file():
            try:
                return json.loads(p.read_text(encoding="utf-8"))
            except Exception:
                return {"path": str(p), "error": "unreadable metadata"}
        if p.is_dir():
            base = p
        else:
            return {"path": str(p), "error": "not found"}
    else:
        base = _security_root() / "security/opa/versions/kubernetes-admission"
    if not base.exists():
        return None
    candidates = sorted([d for d in base.iterdir() if d.is_dir()], key=lambda x: x.name)
    for d in reversed(candidates):
        m = d / "metadata.json"
        if m.exists():
            try:
                data = json.loads(m.read_text(encoding="utf-8"))
                data["_metadata_path"] = str(m)
                return data
            except Exception:
                return {"path": str(m), "error": "unreadable metadata"}
    return {"path": str(base), "error": "no version metadata.json found"}


def load_input(path: str):
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="AdmissionReview JSON file, or - for stdin")
    ap.add_argument("--policy", default="", help="kubernetes-admission.rego file or policy dir (default: $SPECTRE_SECURITY_ROOT/security/opa/policies)")
    ap.add_argument("--version-metadata", default="", help="metadata.json path or versions/kubernetes-admission dir (default: auto under $SPECTRE_SECURITY_ROOT; read-only, report-only)")
    ap.add_argument("--fail-on-deny", action="store_true", help="exit 1 if denials are present (default: report-only, exit 0)")
    args = ap.parse_args()
    policy = find_policy(args.policy)
    # Ensure input is valid JSON (and allow opa to consume file/stdin path semantics)
    if args.input != "-":
        _ = load_input(args.input)
        input_arg = args.input
        input_desc = args.input
    else:
        data = json.load(sys.stdin)
        import tempfile
        tf = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump(data, tf)
        tf.close()
        input_arg = tf.name
        input_desc = "<stdin>"

    cmd = ["opa", "eval", "--format", "raw", "--data", str(policy), "--input", input_arg, "data.kubernetes.admission.deny"]
    r = subprocess.run(cmd, text=True, capture_output=True)
    if args.input == "-":
        try:
            os.unlink(input_arg)
        except OSError:
            pass
    denials = []
    error = None
    if r.returncode == 0:
        try:
            denials = json.loads(r.stdout)
            if not isinstance(denials, list):
                denials = [str(denials)]
        except Exception as e:
            error = f"parse error: {e}: {r.stdout[:200]}"
            denials = []
    else:
        error = f"opa eval failed rc={r.returncode}: {(r.stderr or r.stdout)[:400]}"

    report = {
        "domain": "kubernetes.admission",
        "isolated": True,
        "aggregation": "NOT part of suite data.security[k].deny aggregation; no CI gate change",
        "input": input_desc,
        "policy": str(policy),
        "denial_count": len(denials),
        "denials": denials,
    }
    meta = load_version_metadata(args.version_metadata)
    if meta is not None:
        report["policy_version_metadata"] = meta
    if error:
        report["error"] = error
    print(json.dumps(report, indent=2))
    if error:
        return 2
    if args.fail_on_deny and denials:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
