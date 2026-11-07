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


def load_versions_index() -> dict | None:
    """Read-only: surface spectre-security OPA versions index (isolated/report-only)."""
    p = _security_root() / "security/opa/versions/index.json"
    if not p.exists():
        return None
    try:
        data = json.loads(p.read_text(encoding="utf-8"))
        data["_index_path"] = str(p)
        return data
    except Exception:
        return {"path": str(p), "error": "unreadable index"}


def load_input(path: str):
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _eval_one(policy: Path, input_path: Path) -> tuple[list, str | None]:
    cmd = ["opa", "eval", "--format", "raw", "--data", str(policy), "--input", str(input_path), "data.kubernetes.admission.deny"]
    r = subprocess.run(cmd, text=True, capture_output=True)
    if r.returncode == 0:
        try:
            denials = json.loads(r.stdout)
            if not isinstance(denials, list):
                denials = [str(denials)]
            return denials, None
        except Exception as e:
            return [], f"parse error: {e}: {r.stdout[:200]}"
    return [], f"opa eval failed rc={r.returncode}: {(r.stderr or r.stdout)[:400]}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="AdmissionReview JSON file, directory of *.json fixtures (batch, report-only summary), or - for stdin")
    ap.add_argument("--policy", default="", help="kubernetes-admission.rego file or policy dir (default: $SPECTRE_SECURITY_ROOT/security/opa/policies)")
    ap.add_argument("--version-metadata", default="", help="metadata.json path or versions/kubernetes-admission dir (default: auto under $SPECTRE_SECURITY_ROOT; read-only, report-only)")
    ap.add_argument("--include-versions-index", action="store_true", help="include spectre-security OPA versions/index.json (read-only, isolated; not in data.security[k].deny)")
    ap.add_argument("--fail-on-deny", action="store_true", help="exit 1 if any denials are present (default: report-only, exit 0)")
    args = ap.parse_args()
    policy = find_policy(args.policy)
    meta = load_version_metadata(args.version_metadata)
    vindex = load_versions_index() if args.include_versions_index else None

    def _finalize(report: dict, had_errors: bool, had_denials: bool) -> int:
        if meta is not None:
            report["policy_version_metadata"] = meta
        if vindex is not None:
            report["policy_versions_index"] = vindex
        print(json.dumps(report, indent=2))
        if had_errors:
            return 2
        if args.fail_on_deny and had_denials:
            return 1
        return 0

    in_path = Path(args.input) if args.input != "-" else None
    if in_path is not None and in_path.is_dir():
        fixtures = sorted(p for p in in_path.glob("*.json") if p.is_file())
        results = []
        total_denials = 0
        had_errors = False
        for fp in fixtures:
            denials, error = _eval_one(policy, fp)
            item = {"input": str(fp), "denial_count": len(denials)}
            if error:
                item["error"] = error
                had_errors = True
            if denials:
                item["denials"] = denials
                total_denials += len(denials)
            results.append(item)
        report = {
            "domain": "kubernetes.admission",
            "isolated": True,
            "aggregation": "NOT part of suite data.security[k].deny aggregation; no CI gate change",
            "batch": True,
            "input_dir": str(in_path),
            "policy": str(policy),
            "fixtures_evaluated": len(results),
            "fixtures_with_denials": sum(1 for r in results if r.get("denial_count", 0) > 0),
            "total_denials": total_denials,
            "results": results,
        }
        return _finalize(report, had_errors, total_denials > 0)

    # single file or stdin
    if args.input == "-":
        data = json.load(sys.stdin)
        import tempfile
        tf = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump(data, tf)
        tf.close()
        eval_path = Path(tf.name)
        input_desc = "<stdin>"
    else:
        _ = load_input(args.input)  # validate
        eval_path = Path(args.input)
        input_desc = args.input
    try:
        denials, error = _eval_one(policy, eval_path)
    finally:
        if args.input == "-":
            try:
                eval_path.unlink()
            except OSError:
                pass
    report = {
        "domain": "kubernetes.admission",
        "isolated": True,
        "aggregation": "NOT part of suite data.security[k].deny aggregation; no CI gate change",
        "input": input_desc,
        "policy": str(policy),
        "denial_count": len(denials),
        "denials": denials,
    }
    if error:
        report["error"] = error
    return _finalize(report, error is not None, len(denials) > 0)


if __name__ == "__main__":
    raise SystemExit(main())
