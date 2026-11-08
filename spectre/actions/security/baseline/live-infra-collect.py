#!/usr/bin/env python3
"""Path C step 4 Slice A: suite-native live-infra collector (fixture-driven).

Produces `live_infra_snapshot/v0`-compatible nested snapshots for selected
domains from injected evidence. No host dependencies in Slice A. Read-only by
design; absent/unknown evidence must not be invented as compliant.

Preserves invariants: no data.security[k].deny/aggregation changes, k8s
isolated, unmapped suite controls remain absent/fail-closed.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

CONTRACT_VERSION = "live_infra_snapshot/v0"
SUPPORTED_DOMAINS = ("compliance", "backup", "network", "docker")


def _now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _domain_container(name: str) -> Any:
    return [] if name == "docker" else {}


def collect_snapshot(
    evidence: dict[str, Any] | None,
    *,
    domains: list[str] | None = None,
    source: str = "spectre-suite/live-infra-collect",
    generated_at: str | None = None,
    contract_version: str = CONTRACT_VERSION,
) -> dict[str, Any]:
    """Build a v0 snapshot from injected evidence (pure, fixture-friendly).

    - Emits all schema-required top-level domains; uncollected domains are safe
      empty containers.
    - Copies provided domain evidence as-is (does not invent control values).
      Downstream adapter/normalizer enforce mapping and fail-closed semantics.
    """
    evidence = evidence or {}
    selected = domains or ["compliance", "backup"]
    unknown = [d for d in selected if d not in SUPPORTED_DOMAINS]
    if unknown:
        raise ValueError(f"unsupported domains: {unknown}; supported={list(SUPPORTED_DOMAINS)}")
    snap: dict[str, Any] = {
        "contract_version": contract_version,
        "source": source,
        "generated_at": generated_at or _now_iso(),
        "docker": _domain_container("docker"),
        "network": _domain_container("network"),
        "compliance": _domain_container("compliance"),
        "backup": _domain_container("backup"),
    }
    for domain in selected:
        payload = evidence.get(domain)
        if payload is None:
            continue
        if domain == "docker" and not isinstance(payload, list):
            raise ValueError("docker evidence must be a list")
        if domain != "docker" and not isinstance(payload, dict):
            raise ValueError(f"{domain} evidence must be an object")
        snap[domain] = payload
    return snap


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--from-evidence", help="JSON file containing injected evidence (e.g. {compliance:{...}, backup:{...}})")
    ap.add_argument("--domains", default="compliance,backup", help="comma-separated domains to collect (default: compliance,backup)")
    ap.add_argument("--output", "-o", help="write snapshot JSON here (default: stdout)")
    ap.add_argument("--source", default="spectre-suite/live-infra-collect", help="snapshot provenance source")
    ap.add_argument("--generated-at", default="", help="override generated_at (ISO8601); default: now UTC")
    args = ap.parse_args()
    evidence: dict[str, Any] = {}
    if args.from_evidence:
        evidence = json.loads(Path(args.from_evidence).read_text(encoding="utf-8"))
    elif not sys.stdin.isatty():
        raw = sys.stdin.read()
        if raw.strip():
            evidence = json.loads(raw)
    domains = [d.strip() for d in args.domains.split(",") if d.strip()]
    snap = collect_snapshot(evidence, domains=domains, source=args.source, generated_at=args.generated_at or None)
    text = json.dumps(snap, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
