#!/usr/bin/env python3
"""Adapt spectre-security nested infrastructure JSON to spectre-suite's flat OPA
input contract (Option A: suite canonical).

Reads spectre-security current-infrastructure.json shape (docker[], network{},
compliance{}, backup{}) and emits a JSON object containing only mappable
suite baseline fields. Unmapped suite controls are omitted (undefined) so
suite rego rules remain fail-closed.

Usage:
  opa-contract-adapter.py <nested.json> [-o out.json] [--report report.json]
  cat nested.json | opa-contract-adapter.py -
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load(path: str) -> dict[str, Any]:
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def map_nested_to_suite(src: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    out: dict[str, Any] = {}
    report: dict[str, Any] = {"mapped": [], "unmapped_suite_controls": [], "notes": []}

    def set_if(field: str, value: Any, note: str = "") -> None:
        if value is None:
            return
        out[field] = value
        report["mapped"].append({"suite_field": field, "value": value, "note": note})

    compliance = src.get("compliance") or {}
    network = src.get("network") or {}
    backup = src.get("backup") or {}
    docker = src.get("docker") or []

    # Direct/near-direct mappings from compliance.
    if "firewall_enabled" in compliance:
        set_if("firewall_enabled", bool(compliance["firewall_enabled"]), "from compliance.firewall_enabled")
    if "ssh_password_auth" in compliance:
        set_if("ssh_password_auth", bool(compliance["ssh_password_auth"]), "from compliance.ssh_password_auth")
    if "audit_logging_enabled" in compliance:
        set_if("audit_logging_enabled", bool(compliance["audit_logging_enabled"]), "from compliance.audit_logging_enabled")
    if "intrusion_detection_active" in compliance:
        v = bool(compliance["intrusion_detection_active"])
        set_if("intrusion_detection_active", v, "from compliance.intrusion_detection_active")
        report["notes"].append("fail2ban_active/fail2ban_configured not asserted from intrusion_detection_active alone (suite controls are distinct)")
    if "file_integrity_monitoring" in compliance:
        set_if("file_integrity_monitoring", bool(compliance["file_integrity_monitoring"]), "from compliance.file_integrity_monitoring")

    # Network.
    if "vpn_enabled" in network:
        set_if("vpn_enabled", bool(network["vpn_enabled"]), "from network.vpn_enabled")
    report["notes"].append("network.open_ports/remote_access/container_network retained as evidence in source; not mapped to suite network segmentation controls")

    # Backup.
    if "encrypted" in backup:
        set_if("backup_encryption_enabled", bool(backup["encrypted"]), "from backup.encrypted")
    if "retention_days" in backup:
        try:
            set_if("backup_retention_days", int(backup["retention_days"]), "from backup.retention_days")
        except Exception:
            report["notes"].append("backup.retention_days not an integer; skipped")
    if "offsite_replication" in backup:
        set_if("backup_offsite_enabled", bool(backup["offsite_replication"]), "from backup.offsite_replication")

    # Docker-derived global assertions (heuristic, explicit).
    if isinstance(docker, list) and docker:
        any_priv = any(bool(c.get("privileged")) for c in docker if isinstance(c, dict))
        set_if("docker_privileged_disabled", not any_priv, "derived: no container privileged=true")
        all_mem = all(isinstance(c, dict) and int(c.get("memory_limit") or 0) > 0 for c in docker)
        if all_mem:
            set_if("docker_resource_limits", True, "derived heuristic: all containers have memory_limit > 0")
        else:
            report["notes"].append("docker_resource_limits not asserted (not all containers declare memory_limit > 0)")
        report["notes"].append("docker_not_root/docker_no_new_privileges/docker_userland_proxy_disabled not derived from nested container schema; remain fail-closed unless asserted")

    report["unmapped_suite_controls_note"] = (
        "Suite controls without confident mappings remain absent from output so canonical rego stays fail-closed. "
        "Use spectre/policies/baseline.json for declared control state, or extend this adapter with reviewed mappings."
    )
    return out, report


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="nested current-infrastructure.json or - for stdin")
    ap.add_argument("-o", "--output", help="write adapted JSON here (default stdout)")
    ap.add_argument("--report", help="write mapping report JSON here")
    args = ap.parse_args()
    src = load(args.input)
    out, report = map_nested_to_suite(src)
    text = json.dumps(out, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
