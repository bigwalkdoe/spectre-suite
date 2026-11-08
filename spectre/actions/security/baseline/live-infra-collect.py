#!/usr/bin/env python3
"""Path C step 4: suite-native live-infra collector (Slice A+B).

Produces `live_infra_snapshot/v0`-compatible nested snapshots for selected
domains from injected evidence (Slice A, fixture-driven) and/or best-effort
read-only host probes (Slice B, opt-in). Absent/unknown evidence must not be
invented as compliant (fail-closed).

Preserves invariants: no data.security[k].deny/aggregation changes, k8s
isolated, unmapped suite controls remain absent/fail-closed.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
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


def _run(cmd: list[str], timeout: float = 5) -> tuple[int, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout or "").strip()
    except Exception:
        return 127, ""


def _systemctl_active(unit: str) -> bool | None:
    """Return True/False when definitive, None when unknown (fail-closed: absent)."""
    if not shutil.which("systemctl"):
        return None
    rc, out = _run(["systemctl", "is-active", unit])
    if out == "active":
        return True
    if out in ("inactive", "failed", "deactivating"):
        return False
    return None


def _probe_compliance() -> dict[str, Any]:
    """Best-effort, read-only, non-privileged probes. Omit fields when uncertain."""
    ev: dict[str, Any] = {}
    fw = _systemctl_active("firewalld")
    if fw is None:
        # nftables may be active; only assert if definitive
        nft = _systemctl_active("nftables")
        if nft is not None:
            ev["firewall_enabled"] = nft
    else:
        ev["firewall_enabled"] = fw
    audit = _systemctl_active("auditd")
    if audit is not None:
        ev["audit_logging_enabled"] = audit
    # intrusion_detection_active: conservative - any clearly active IDS agent/service.
    for svc in ("wazuh-agent", "suricata", "snort"):
        st = _systemctl_active(svc)
        if st is True:
            ev["intrusion_detection_active"] = True
            break
    # file_integrity_monitoring: aide common paths (read-only checks)
    for p in (Path("/var/lib/aide/aide.db.gz"), Path("/var/lib/aide/aide.db"), Path.home() / ".local/state/aide/aide.db.gz"):
        try:
            if p.exists():
                ev["file_integrity_monitoring"] = True
                break
        except Exception:
            pass
    # ssh_password_auth: avoid privileged/ambiguous reads; leave absent (fail-closed).
    return ev


def _probe_backup() -> dict[str, Any]:
    """Best-effort probes from suite restic markers (non-secret). Omit when uncertain."""
    ev: dict[str, Any] = {}
    state = Path.home() / ".local/state/spectre-suite/backups"
    try:
        last_success = state / "last-success"
        last_offsite = state / "last-offsite-success"
        if last_success.exists() and last_success.read_text(encoding="utf-8").strip():
            # Restic repositories are encrypted; suite restic usage implies encryption.
            ev["encrypted"] = True
        if last_offsite.exists() and last_offsite.read_text(encoding="utf-8").strip():
            ev["offsite_replication"] = True
    except Exception:
        pass
    # retention_days: requires config parsing (env may be secret); omit (fail-closed).
    return ev


def probe_evidence(domains: list[str] | None = None) -> dict[str, Any]:
    selected = domains or ["compliance", "backup"]
    out: dict[str, Any] = {}
    if "compliance" in selected:
        out["compliance"] = _probe_compliance()
    if "backup" in selected:
        out["backup"] = _probe_backup()
    if "network" in selected:
        out["network"] = {}
    if "docker" in selected:
        out["docker"] = []
    return out


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


def _merge_evidence(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    out = {k: (v.copy() if isinstance(v, dict) else (list(v) if isinstance(v, list) else v)) for k, v in base.items()}
    for k, v in override.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            merged = dict(out[k])
            merged.update(v)
            out[k] = merged
        else:
            out[k] = v
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--from-evidence", help="JSON file containing injected evidence (e.g. {compliance:{...}, backup:{...}}); overrides probe values")
    ap.add_argument("--probe", action="store_true", help="best-effort read-only host probes (Slice B, opt-in, non-privileged); omitted/uncertain fields stay absent/fail-closed")
    ap.add_argument("--domains", default="compliance,backup", help="comma-separated domains to collect (default: compliance,backup)")
    ap.add_argument("--output", "-o", help="write snapshot JSON here (default: stdout)")
    ap.add_argument("--source", default="spectre-suite/live-infra-collect", help="snapshot provenance source")
    ap.add_argument("--generated-at", default="", help="override generated_at (ISO8601); default: now UTC")
    args = ap.parse_args()
    domains = [d.strip() for d in args.domains.split(",") if d.strip()]
    evidence: dict[str, Any] = {}
    if args.probe:
        evidence = probe_evidence(domains)
        if not args.source or args.source == "spectre-suite/live-infra-collect":
            args.source = "spectre-suite/live-infra-collect/probe"
    if args.from_evidence:
        explicit = json.loads(Path(args.from_evidence).read_text(encoding="utf-8"))
        evidence = _merge_evidence(evidence, explicit)
    elif not args.probe and not sys.stdin.isatty():
        raw = sys.stdin.read()
        if raw.strip():
            evidence = json.loads(raw)
    snap = collect_snapshot(evidence, domains=domains, source=args.source, generated_at=args.generated_at or None)
    text = json.dumps(snap, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
