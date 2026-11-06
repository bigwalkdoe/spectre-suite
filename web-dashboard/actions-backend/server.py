#!/usr/bin/env python3
"""Minimal allowlisted dashboard action trigger service.

Security model:
- Allowlist only: action name -> fixed script path (no user args to shell).
- Token auth: requires X-Dashboard-Action-Token == DASHBOARD_ACTION_TOKEN when set.
- Trigger-file execution (async): writes JSON to /triggers; a host handler runs
  the allowlisted script. This avoids giving the container broad host privileges.

This service does NOT execute scripts itself.
"""
from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("PORT", "8090"))
TRIGGERS_DIR = Path(os.environ.get("TRIGGERS_DIR", "/triggers"))
REPO_ROOT = Path(os.environ.get("REPO_ROOT", "/repo"))
TOKEN = os.environ.get("DASHBOARD_ACTION_TOKEN", "")

# Allowlist: action name -> repo-relative script path
ALLOWLIST = {
    "backup": "scripts/backups/run-missed-backups.sh",
    "maintenance": "scripts/maintenance/run-maintenance.sh",
    "security-scan": "scripts/security/scan-docker-images.sh",
}


def json_response(handler: BaseHTTPRequestHandler, status: int, payload: dict) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


class Handler(BaseHTTPRequestHandler):
    server_version = "spectre-dashboard-actions/1.0"

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            json_response(self, 200, {"ok": True, "service": "dashboard-actions", "actions": sorted(ALLOWLIST)})
            return
        json_response(self, 404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        # Token auth (required when DASHBOARD_ACTION_TOKEN is set)
        if TOKEN:
            provided = self.headers.get("X-Dashboard-Action-Token", "")
            if provided != TOKEN:
                json_response(self, 401, {"ok": False, "error": "unauthorized", "message": "Missing or invalid X-Dashboard-Action-Token"})
                return
        else:
            # No token configured - reject by default for safety
            json_response(self, 503, {"ok": False, "error": "not_configured", "message": "DASHBOARD_ACTION_TOKEN is not set; actions are disabled"})
            return

        action = self.path.strip("/").split("/")[-1]
        if action not in ALLOWLIST:
            json_response(self, 400, {"ok": False, "error": "action_not_allowed", "allowed": sorted(ALLOWLIST)})
            return

        script_rel = ALLOWLIST[action]
        script_path = (REPO_ROOT / script_rel).resolve()
        # Ensure script is under repo root
        try:
            script_path.relative_to(REPO_ROOT.resolve())
        except Exception:
            json_response(self, 400, {"ok": False, "error": "invalid_script_path"})
            return

        trigger = {
            "id": str(uuid.uuid4()),
            "action": action,
            "script": script_rel,
            "requestedAt": datetime.now(timezone.utc).isoformat(),
            "remote": self.client_address[0] if self.client_address else None,
            "status": "queued",
        }

        try:
            TRIGGERS_DIR.mkdir(parents=True, exist_ok=True)
            target = TRIGGERS_DIR / f"{trigger['requestedAt'].replace(':','').replace('+00:00','Z')}-{trigger['id']}-{action}.json"
            tmp = target.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(trigger, indent=2) + "\n", encoding="utf-8")
            tmp.replace(target)
        except Exception as exc:
            json_response(self, 500, {"ok": False, "error": "trigger_write_failed", "message": str(exc)})
            return

        json_response(self, 202, {
            "ok": True,
            "queued": True,
            "action": action,
            "script": script_rel,
            "triggerId": trigger["id"],
            "message": "Action queued. A host trigger handler must be installed to execute it (see scripts/dashboard-actions/process-triggers.sh and systemd/dashboard-actions/).",
        })


def main() -> None:
    TRIGGERS_DIR.mkdir(parents=True, exist_ok=True)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"dashboard-actions listening on :{PORT}, triggers={TRIGGERS_DIR}, allowlist={sorted(ALLOWLIST)}", file=sys.stderr)
    if not TOKEN:
        print("WARNING: DASHBOARD_ACTION_TOKEN is unset; all action requests will be rejected (503).", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
