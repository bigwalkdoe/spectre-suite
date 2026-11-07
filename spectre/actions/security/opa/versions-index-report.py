#!/usr/bin/env python3
"""Read-only OPA versions index report (ISOLATED).

Reports the full spectre-security OPA versions/index.json and per-policy metadata
presence. Not part of suite data.security[k].deny aggregation; no CI gate change.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def _security_root() -> Path:
    return Path(os.environ.get("SPECTRE_SECURITY_ROOT", "/home/deon/dev/github/spectre-security"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--versions-root", default="", help="versions directory (default: $SPECTRE_SECURITY_ROOT/security/opa/versions)")
    ap.add_argument("--index", default="", help="index.json path (default: <versions-root>/index.json)")
    args = ap.parse_args()
    root = Path(args.versions_root) if args.versions_root else (_security_root() / "security/opa/versions")
    idx_path = Path(args.index) if args.index else (root / "index.json")
    report = {
        "domain": "opa.versions",
        "isolated": True,
        "aggregation": "NOT part of suite data.security[k].deny aggregation; no CI gate change",
        "versions_root": str(root),
        "index_path": str(idx_path),
    }
    if idx_path.exists():
        try:
            report["index"] = json.loads(idx_path.read_text(encoding="utf-8"))
        except Exception as e:
            report["index_error"] = f"unreadable: {e}"
    else:
        report["index_error"] = "index.json not found"
    presence = {}
    for p in sorted([x for x in root.iterdir() if x.is_dir()]):
        vdirs = sorted([d for d in p.iterdir() if d.is_dir() and d.name.startswith("v")])
        meta = None
        if vdirs:
            m = vdirs[-1] / "metadata.json"
            if m.exists():
                try:
                    meta = json.loads(m.read_text(encoding="utf-8"))
                    meta = {"has_metadata": True, "path": str(m), "policy": meta.get("policy"), "version": meta.get("version"), "approved": meta.get("approved")}
                except Exception:
                    meta = {"has_metadata": False, "error": "unreadable", "path": str(m)}
            else:
                meta = {"has_metadata": False}
        presence[p.name] = {"version_dirs": [d.name for d in vdirs], "latest_metadata": meta}
    report["policies"] = presence
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
