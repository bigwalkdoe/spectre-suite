"""Control-plane aggregation endpoints for the Spectre dashboard.

Read-mostly endpoints that compose dispatch, run history, health, and external
component signals. They degrade gracefully when optional deps/services are
unavailable so the dashboard can still render partial truth.
"""

from __future__ import annotations

import json
import os
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends, HTTPException, Security
import typer

from spectre.dispatch import registry
from spectre.dispatch.lock import JobLock
from spectre.dispatch.resolve import DispatchError, resolve
from spectre.memory.db import init_db, save_run

router = APIRouter(prefix="/api/control-plane", tags=["control-plane"])


def _utc_now() -> str:
    return datetime.now(UTC).isoformat()


def _http_json(url: str, timeout: float = 2.5) -> dict[str, Any]:
    req = Request(url, headers={"Accept": "application/json"})
    with urlopen(req, timeout=timeout) as resp:  # noqa: S310 - operator-configured local URLs
        return json.loads(resp.read().decode("utf-8", "replace"))


def _component_http(name: str, url: str, kind: str, expect_json: bool = True) -> dict[str, Any]:
    started = time.time()
    try:
        req = Request(url, headers={"Accept": "application/json, text/plain, */*"})
        with urlopen(req, timeout=2.5) as resp:  # noqa: S310 - operator-configured local URLs
            body = resp.read().decode("utf-8", "replace")
        latency_ms = int((time.time() - started) * 1000)
        if expect_json:
            try:
                return {"name": name, "kind": kind, "url": url, "status": "ok", "latency_ms": latency_ms, "data": json.loads(body)}
            except (ValueError, json.JSONDecodeError):
                # Some endpoints return 200 text; treat reachability as degraded-info, not hard error.
                return {"name": name, "kind": kind, "url": url, "status": "ok", "latency_ms": latency_ms, "data": {"format": "text", "bytes": len(body)}}
        return {"name": name, "kind": kind, "url": url, "status": "ok", "latency_ms": latency_ms, "data": {"bytes": len(body)}}
    except (URLError, TimeoutError, OSError, ValueError) as exc:
        return {"name": name, "kind": kind, "url": url, "status": "error", "latency_ms": int((time.time() - started) * 1000), "error": str(exc)}


def _recent_runs(limit: int = 25) -> list[dict[str, Any]]:
    try:
        from spectre.memory.db import recent_runs

        rows = recent_runs(limit=limit)
        out = []
        for r in rows:
            out.append(
                {
                    "id": getattr(r, "id", None),
                    "action": getattr(r, "action", None),
                    "agent": getattr(r, "agent", None),
                    "status": getattr(r, "status", None),
                    "trigger": getattr(r, "trigger", None),
                    "duration_ms": getattr(r, "duration_ms", None),
                    "exit_code": getattr(r, "exit_code", None),
                    "git_commit": getattr(r, "git_commit", None),
                    "git_dirty": getattr(r, "git_dirty", None),
                    "started_at": getattr(r, "started_at", None).isoformat() if getattr(r, "started_at", None) else None,
                    "stderr_tail": (getattr(r, "stderr_tail", None) or "")[:400] or None,
                }
            )
        return out
    except Exception as exc:  # noqa: BLE001 - dashboard must degrade gracefully
        return [{"error": f"run history unavailable: {exc}"}]


def _backup_health() -> dict[str, Any]:
    # Prefer reading latest marker/state files if present; avoid mutating checks.
    candidates = [
        Path(os.environ.get("BACKUP_STATE_DIR", "/backups/backup-state")),
        Path.home() / ".local/state/spectre-suite/backups",
    ]
    markers = []
    for base in candidates:
        if base.exists():
            for p in sorted(base.glob("*"))[-20:]:
                try:
                    st = p.stat()
                    markers.append({"path": str(p), "mtime": datetime.fromtimestamp(st.st_mtime, UTC).isoformat(), "size": st.st_size})
                except OSError:
                    pass
    return {"markers": markers, "state_dirs_checked": [str(p) for p in candidates]}


def _dispatch_summary() -> dict[str, Any]:
    jobs = list(registry.JOBS)
    groups = {}
    for j in jobs:
        groups[j.group] = groups.get(j.group, 0) + 1
    findings = []
    try:
        findings = [f.__dict__ if hasattr(f, "__dict__") else {"code": getattr(f, "code", None), "detail": getattr(f, "detail", None)} for f in verify(read_host_inventory())]
    except Exception as exc:  # noqa: BLE001
        findings = [{"code": "verify-error", "detail": str(exc)}]
    blocking = [f for f in findings if f.get("code") in {"missing", "not-executable", "syntax", "unlocked-mutation", "duplicate"}]
    return {
        "job_count": len(jobs),
        "groups": groups,
        "verify": {"blocking": len(blocking), "advisory": len(findings) - len(blocking), "findings": findings[:50]},
    }


def _monitoring_components() -> list[dict[str, Any]]:
    prom = os.environ.get("SPECTRE_PROMETHEUS_URL", "http://127.0.0.1:9090")
    alert = os.environ.get("SPECTRE_ALERTMANAGER_URL", "http://127.0.0.1:9093")
    grafana = os.environ.get("SPECTRE_GRAFANA_URL", "http://127.0.0.1:3002")
    blackbox = os.environ.get("SPECTRE_BLACKBOX_URL", "http://127.0.0.1:9115")
    checks = [
        _component_http("Prometheus", f"{prom.rstrip('/')}/api/v1/status/buildinfo", "metrics"),
        _component_http("Alertmanager", f"{alert.rstrip('/')}/api/v2/status", "alerts"),
        _component_http("Grafana", f"{grafana.rstrip('/')}/api/health", "dashboards"),
        _component_http("Blackbox", f"{blackbox.rstrip('/')}/metrics", "probes", expect_json=False),
    ]
    # Avoid leaking full Alertmanager config payloads into the control plane.
    for c in checks:
        if c["name"] == "Alertmanager" and isinstance(c.get("data"), dict):
            cfg = c["data"].get("config")
            if isinstance(cfg, dict):
                cfg.pop("original", None)
                c["data"]["config"] = {"redacted": True, "keys": sorted(cfg.keys())[:20]}
    return checks


def build_overview() -> dict[str, Any]:
    dispatch = _dispatch_summary()
    monitoring = _monitoring_components()
    up = sum(1 for c in monitoring if c["status"] == "ok")
    return {
        "generated_at": _utc_now(),
        "health": {
            "status": "ok" if dispatch["verify"]["blocking"] == 0 else "degraded",
            "blocking_findings": dispatch["verify"]["blocking"],
            "monitoring_up": up,
            "monitoring_total": len(monitoring),
        },
        "dispatch": dispatch,
        "recent_runs": _recent_runs(),
        "backup": _backup_health(),
        "monitoring": monitoring,
    }


def register(app, verify_api_key):
    dep = Depends(verify_api_key)

    @router.get("/overview")
    async def overview(_: bool = dep) -> dict[str, Any]:
        return build_overview()

    @router.get("/actions")
    async def actions(_: bool = dep) -> dict[str, Any]:
        items = []
        for j in registry.JOBS:
            items.append({
                "name": j.name,
                "group": j.group,
                "summary": j.summary,
                "action": j.action,
                "sudo": j.sudo,
                "mutates": j.mutates,
                "timeout": j.timeout,
                "concurrency": j.concurrency,
                "schedule_hint": j.schedule_hint,
                "replaces": list(j.replaces),
            })
        return {"count": len(items), "actions": items}

    @app.post("/api/control-plane/actions/{job}/run")
    async def run_job(job: str, _: bool = Depends(verify_api_key)):
        """Run one registered job and record the run."""
        if job == "__any_job__":
            raise HTTPException(status_code=404, detail="Not found")
        job_obj = registry.get_job(job)
        if job_obj.sudo and os.geteuid() != 0:
            raise HTTPException(status_code=3, detail=f"{job_obj.name} needs root, and this process is not root.")
        try:
            resolved = resolve(job_obj)
        except DispatchError as e:
            raise HTTPException(status_code=e.exit_code, detail=str(e)) from None
        with JobLock(job_obj):
            outcome = run_action(resolved, [], "cli", timeout=job_obj.timeout)
        init_db()
        save_run(outcome.envelope)
        return {
            "job": job_obj.name,
            "status": outcome.status.value,
            "exit_code": outcome.exit_code,
            "duration_ms": outcome.duration_ms,
            "stdout_tail": outcome.stdout_tail,
            "stderr_tail": outcome.stderr_tail,
        }


    @app.post("/api/control-plane/actions/{job}")
    async def run_job_no_run(job: str, _: bool = Depends(verify_api_key)):
        """Alias — records the run via the canonical /run path."""
        return await run_job(job)


    @app.get("/api/control-plane/actions/{job}/envelope")
    async def get_envelope(job: str, _: bool = Depends(verify_api_key)):
        """Return the most recent recorded envelope for the given job (read-only)."""
        # Placeholder read-back; execution is done through POST.
        return {"job": job, "status": "unknown"}


app.include_router(router)
