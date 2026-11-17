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
import pwd
import sys
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("PORT", "8090"))
TRIGGERS_DIR = Path(os.environ.get("TRIGGERS_DIR", "/triggers"))
RUNS_DIR = TRIGGERS_DIR / "runs"
REPO_ROOT = Path(os.environ.get("REPO_ROOT", "/repo"))
TOKEN = os.environ.get("DASHBOARD_ACTION_TOKEN", "")

# Allowlist: action name -> repo-relative canonical action path (host handler
# dispatches by action name via `spectre run`; script is recorded for validation).
ALLOWLIST = {
    "backup": "spectre/actions/backups/run-missed-backups.sh",
    "maintenance": "spectre/actions/maintenance/run-maintenance.sh",
    "security-scan": "spectre/actions/security/scan-docker-images.sh",
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

    def _audit(self, event: str, **fields) -> None:
        # Never log tokens or request bodies. Keep stderr structured for operators.
        payload = {"ts": datetime.now(timezone.utc).isoformat(), "event": event, **fields}
        sys.stderr.write(json.dumps(payload, sort_keys=True) + "\n")

    def _remote(self) -> str | None:
        xff = self.headers.get("X-Forwarded-For", "")
        if xff:
            return xff.split(",")[0].strip() or None
        return self.client_address[0] if self.client_address else None

    def _require_auth(self) -> bool:
        remote = self._remote()
        if TOKEN:
            provided = self.headers.get("X-Dashboard-Action-Token", "")
            if provided != TOKEN:
                self._audit("auth_rejected", path=self.path, status=401, remote=remote)
                json_response(self, 401, {"ok": False, "error": "unauthorized", "message": "Missing or invalid X-Dashboard-Action-Token"})
                return False
            return True
        self._audit("not_configured", path=self.path, status=503, remote=remote)
        json_response(self, 503, {"ok": False, "error": "not_configured", "message": "DASHBOARD_ACTION_TOKEN is not set; actions are disabled"})
        return False

    def _safe_run_id(self, run_id: str) -> str | None:
        if not run_id:
            return None
        # Allow UUID-like and trigger-derived IDs (hex, dash, underscore, dot, colonless timestamps in names become safe chars here)
        import re
        if not re.fullmatch(r"[A-Za-z0-9._:-]{1,120}", run_id):
            return None
        if ".." in run_id or "/" in run_id or "\\" in run_id:
            return None
        return run_id

    def _read_run_file(self, run_id: str):
        safe_id = self._safe_run_id(run_id)
        if not safe_id:
            return None
        path = (RUNS_DIR / f"{safe_id}.json").resolve()
        try:
            path.relative_to(RUNS_DIR.resolve())
        except Exception:
            return None
        if not path.is_file():
            return None
        try:
            with path.open("r", encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else None
        except Exception:
            return None

    def _list_runs(self):
        runs = []
        try:
            RUNS_DIR.mkdir(parents=True, exist_ok=True)
            for p in RUNS_DIR.glob("*.json"):
                try:
                    with p.open("r", encoding="utf-8") as f:
                        data = json.load(f)
                    if isinstance(data, dict):
                        runs.append(data)
                except Exception:
                    continue
        except Exception:
            return []
        def sort_key(r):
            return str(r.get("requestedAt") or r.get("startedAt") or r.get("finishedAt") or "")
        runs.sort(key=sort_key, reverse=True)
        return runs

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            json_response(self, 200, {"ok": True, "service": "dashboard-actions", "actions": sorted(ALLOWLIST)})
            return

        # Read-only run status endpoints (authenticated same as actions)
        if self.path == "/runs" or self.path.startswith("/runs?") or self.path == "/runs/" or self.path.startswith("/runs/"):
            if not self._require_auth():
                return
            from urllib.parse import urlparse, parse_qs
            parsed = urlparse(self.path)
            parts = [p for p in parsed.path.split("/") if p]
            if len(parts) == 1:
                qs = parse_qs(parsed.query or "")
                try:
                    limit = int((qs.get("limit") or ["50"])[0])
                except Exception:
                    limit = 50
                limit = max(1, min(limit, 200))
                status_filter = (qs.get("status") or [""])[0].strip()
                runs = self._list_runs()
                if status_filter:
                    runs = [r for r in runs if str(r.get("status", "")) == status_filter]
                total = len(runs)
                json_response(self, 200, {"ok": True, "runs": runs[:limit], "count": total, "returned": len(runs[:limit])})
                return
            if len(parts) == 2:
                run = self._read_run_file(parts[1])
                if not run:
                    json_response(self, 404, {"ok": False, "error": "not_found"})
                    return
                json_response(self, 200, {"ok": True, "run": run})
                return
            json_response(self, 404, {"ok": False, "error": "not_found"})
            return

        self._audit("request_rejected", method="GET", path=self.path, status=404, remote=self._remote())
        json_response(self, 404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        remote = self._remote()
        if not self._require_auth():
            return

        # Basic hardening: require JSON content type for queue requests (best-effort).
        ctype = (self.headers.get("Content-Type") or "").split(";")[0].strip().lower()
        if ctype and ctype not in ("application/json", "text/json"):
            self._audit("action_rejected", reason="unsupported_content_type", path=self.path, status=415, remote=remote)
            json_response(self, 415, {"ok": False, "error": "unsupported_media_type", "message": "Use application/json"})
            return

        action = self.path.strip("/").split("/")[-1]
        if action not in ALLOWLIST:
            self._audit("action_rejected", action=action, path=self.path, status=400, remote=remote)
            json_response(self, 400, {"ok": False, "error": "action_not_allowed", "allowed": sorted(ALLOWLIST)})
            return

        script_rel = ALLOWLIST[action]
        script_path = (REPO_ROOT / script_rel).resolve()
        # Ensure script is under repo root
        try:
            script_path.relative_to(REPO_ROOT.resolve())
        except Exception:
            self._audit("action_rejected", action=action, reason="invalid_script_path", status=400, remote=remote)
            json_response(self, 400, {"ok": False, "error": "invalid_script_path"})
            return

        # Optional, bounded metadata from UI (never log body/token contents).
        reason = None
        actor = None
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except Exception:
            length = 0
        if length > 0:
            try:
                raw = self.rfile.read(min(length, 4096))
                payload = json.loads(raw.decode("utf-8") or "{}") if raw else {}
                if isinstance(payload, dict):
                    r = payload.get("reason")
                    a = payload.get("actor")
                    if isinstance(r, str) and r.strip():
                        reason = r.strip()[:200]
                    if isinstance(a, str) and a.strip():
                        actor = a.strip()[:120]
            except Exception:
                # Ignore malformed/oversized bodies; queue still proceeds.
                pass

        trigger = {
            "id": str(uuid.uuid4()),
            "action": action,
            "script": script_rel,
            "requestedAt": datetime.now(timezone.utc).isoformat(),
            "remote": remote,
            "status": "queued",
        }
        if reason:
            trigger["reason"] = reason
        if actor:
            trigger["actor"] = actor

        try:
            TRIGGERS_DIR.mkdir(parents=True, exist_ok=True)
            target = TRIGGERS_DIR / f"{trigger['requestedAt'].replace(':','').replace('+00:00','Z')}-{trigger['id']}-{action}.json"
            tmp = target.with_suffix(".json.tmp")
            tmp.write_text(json.dumps(trigger, indent=2) + "\n", encoding="utf-8")
            tmp.replace(target)
        except Exception as exc:
            self._audit("trigger_write_failed", action=action, trigger_id=trigger["id"], status=500, remote=remote)
            json_response(self, 500, {"ok": False, "error": "trigger_write_failed", "message": str(exc)})
            return

        self._audit("action_queued", action=action, trigger_id=trigger["id"], script=script_rel, status=202, remote=remote)
        json_response(self, 202, {
            "ok": True,
            "queued": True,
            "action": action,
            "script": script_rel,
            "triggerId": trigger["id"],
            "message": "Action queued. A host trigger handler must be installed to execute it (see spectre/actions/dashboard-actions/process-triggers.sh, `spectre run dashboard-actions/process-triggers`, and systemd/dashboard-actions/).",
        })


def main() -> None:
    TRIGGERS_DIR.mkdir(parents=True, exist_ok=True)
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    # /triggers is a bind mount owned by the host operator (e.g. uid 1000). The
    # HTTP server drops to the unprivileged 'nobody' user below, so make the
    # queue directory sticky world-writable when possible so 'nobody' can create
    # trigger files while the host handler can still move them to processed/ or
    # failed/. On some bind-mount/SELinux setups chmod may be disallowed; in
    # that case continue and rely on existing permissions.
    try:
        TRIGGERS_DIR.chmod(0o1777)
    except (PermissionError, OSError) as exc:
        print(f"WARNING: could not chmod {TRIGGERS_DIR} to 1777 ({exc}); continuing with existing permissions", file=sys.stderr)
    # Drop privileges to the unprivileged 'nobody' user before serving, keeping
    # the runtime hardened (no script execution in container, read-only repo
    # mount, only /triggers writable). Must run as root initially for the
    # chmod above, hence USER nobody is not set in the Dockerfile.
    nobody = pwd.getpwnam("nobody")
    os.setgid(nobody.pw_gid)
    os.setuid(nobody.pw_uid)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"dashboard-actions listening on :{PORT}, triggers={TRIGGERS_DIR}, allowlist={sorted(ALLOWLIST)}", file=sys.stderr)
    if not TOKEN:
        print("WARNING: DASHBOARD_ACTION_TOKEN is unset; all action requests will be rejected (503).", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    main()
