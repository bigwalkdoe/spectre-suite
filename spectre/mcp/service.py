"""Service layer for the Spectre MCP server.

All tool bodies delegate here. This module owns serialization, redaction, and
truncation; it reuses the existing registry, dispatch, database, and workflow
engine rather than reimplementing them.
"""

from __future__ import annotations

import json
import os
import platform
from datetime import datetime
from typing import Any

from spectre.config import settings as _settings
from spectre.core.agent import AgentContext
from spectre.core.service_bus import ServiceBus
from spectre.dispatch import registry as _registry
from spectre.dispatch import verify as _verify
from spectre.dispatch.envelope import truncate_output
from spectre.dispatch.resolve import DispatchError, resolve as _resolve, actions_root as _actions_root
from spectre.dispatch.retention import record_growth as _record_growth
from spectre.memory import db as _db
from spectre.mcp.policy import evaluate as _evaluate_policy
from spectre.mcp.policy import allow_mutations, allow_sudo, is_root
from spectre.mcp.redact import redact as _redact_value
from spectre.workflow_engine import engine as _engine_mod

try:
    from importlib.metadata import PackageNotFoundError, version as _get_version
except Exception:  # pragma: no cover
    PackageNotFoundError = Exception  # type: ignore[misc, assignment]
    _get_version = None  # type: ignore[assignment]

from sqlmodel import Session

_SECRET_KEY_TOKENS = ("key", "token", "secret", "password")
_TRUNCATE_LIMIT = 16384


def _iso(value: Any) -> str | None:
    if value is None:
        return None
    if hasattr(value, "isoformat"):
        try:
            return value.isoformat()
        except Exception:
            return str(value)
    return str(value)


def _clamp_limit(limit: Any, default: int = 20, maximum: int | None = None) -> int:
    if maximum is None:
        try:
            maximum = int(os.environ.get("SPECTRE_MCP_MAX_ROWS", "200"))
        except (TypeError, ValueError):
            maximum = 200
    try:
        value = int(limit)
    except (TypeError, ValueError):
        value = default
    if value < 1:
        value = 1
    if value > maximum:
        value = maximum
    return value


def _make_agent(name: str) -> Any:
    _engine_mod._register_default_factories()
    cls = _engine_mod._AGENT_FACTORIES.get(name)
    if cls is None:
        raise KeyError(name)
    context = AgentContext(service_bus=ServiceBus())
    agent = cls(config={}, context=context)
    try:
        agent.initialize()
    except Exception:
        pass
    return agent


class SpectreService:
    """Data access and dispatch orchestration for the MCP server."""

    # ------------------------------------------------------------------ read
    def status(self, agent: str | None = None) -> dict[str, Any]:
        _engine_mod._register_default_factories()
        if agent is not None and agent not in _engine_mod._AGENT_FACTORIES:
            return {"ok": False, "status": "unknown_agent", "agent": agent}
        names = [agent] if agent is not None else list(_engine_mod._AGENT_FACTORIES)
        agents: dict[str, Any] = {}
        for name in names:
            try:
                inst = _make_agent(name)
                agents[name] = inst.observe()
            except Exception as exc:  # pragma: no cover - defensive
                agents[name] = {"error": str(exc)}
        return {"ok": True, "agents": agents}

    def health(self) -> dict[str, Any]:
        try:
            inst = _make_agent("monitoring")
        except KeyError:
            return {"ok": False, "status": "unknown_agent", "agent": "monitoring"}
        try:
            results = inst.execute(["collect-metrics", "check-thresholds"])
        except Exception as exc:
            return {"ok": False, "status": "error", "reason": str(exc)}
        return {
            "ok": True,
            "metrics": results.get("collect-metrics"),
            "thresholds": results.get("check-thresholds"),
        }

    def actions_list(self, group: str | None = None, include_runs: bool = True) -> dict[str, Any]:
        jobs = list(_registry.JOBS)
        if group:
            jobs = [j for j in jobs if j.group == group]
        jobs = sorted(jobs, key=lambda j: j.name)
        growth = None
        if include_runs:
            try:
                growth = _record_growth()
            except Exception:
                growth = None
        serialized = [self._serialize_job(j, growth) for j in jobs]
        return {"ok": True, "count": len(serialized), "jobs": serialized}

    def _serialize_job(self, job: Any, growth: Any) -> dict[str, Any]:
        rows = None
        if growth is not None:
            rows = growth.get(job.name, "0")
        return {
            "name": job.name,
            "group": job.group,
            "summary": job.summary,
            "action": job.action,
            "sudo": job.sudo,
            "mutates": job.mutates,
            "timeout": job.timeout,
            "concurrency": job.concurrency,
            "schedule_hint": job.schedule_hint,
            "replaces": list(job.replaces),
            "runs": rows,
        }

    def action_show(self, job: str) -> dict[str, Any]:
        try:
            j = _registry.get_job(job)
        except KeyError:
            return {"ok": False, "status": "unknown_job", "job": job}
        try:
            resolved = _resolve(j)
        except DispatchError as exc:
            return {"ok": False, "status": "error", "reason": str(exc)}
        return {
            "ok": True,
            "job": j.name,
            "summary": j.summary,
            "group": j.group,
            "action": j.action,
            "sudo": j.sudo,
            "mutates": j.mutates,
            "timeout": j.timeout,
            "concurrency": j.concurrency,
            "schedule_hint": j.schedule_hint,
            "replaces": list(j.replaces),
            "resolved": str(resolved.path),
            "commit": resolved.git_commit,
            "dirty": resolved.git_dirty,
        }

    def actions_verify(self) -> dict[str, Any]:
        inventory = _verify.read_host_inventory()
        findings = _verify.verify(inventory)
        counts = {code: 0 for code in _verify.ALL_CODES}
        for finding in findings:
            counts[finding.code] += 1
        blocking = [f for f in findings if f.code in _verify.BLOCKING_CODES]
        return {
            "ok": True,
            "actions_root": str(_actions_root()),
            "registry_jobs": len(_registry.JOBS),
            "unreadable": list(inventory.unreadable),
            "counts": counts,
            "blocking_count": len(blocking),
            "findings": [{"code": f.code, "detail": f.detail} for f in findings],
            "verdict": "no blocking findings" if not blocking else f"{len(blocking)} blocking finding(s)",
        }

    def runs(self, limit: int = 20, job: str | None = None) -> dict[str, Any]:
        limit = _clamp_limit(limit)
        records = _db.recent_runs(limit=limit, job=job)
        return {
            "ok": True,
            "count": len(records),
            "runs": [self._serialize_run(r) for r in records],
        }

    def _serialize_run(self, record: Any) -> dict[str, Any]:
        payload = None
        if record.payload:
            try:
                payload = json.loads(record.payload)
            except (ValueError, TypeError):
                payload = None
        return {
            "id": record.id,
            "timestamp": _iso(record.timestamp),
            "agent": record.agent,
            "action": record.action,
            "status": record.status,
            "log_output": truncate_output(record.log_output or "", _TRUNCATE_LIMIT),
            "stderr_tail": (truncate_output(record.stderr_tail, _TRUNCATE_LIMIT) if record.stderr_tail else None),
            "duration_ms": record.duration_ms,
            "trigger": record.trigger,
            "exit_code": record.exit_code,
            "resolved_path": record.resolved_path,
            "git_commit": record.git_commit,
            "git_dirty": record.git_dirty,
            "payload": payload,
        }

    def workflows_list(self) -> dict[str, Any]:
        engine = _engine_mod.WorkflowEngine()
        definitions = engine.get_workflow_definitions()
        workflows = []
        for wf in definitions.values():
            workflows.append(
                {
                    "name": wf.name,
                    "description": wf.description,
                    "steps": [{"agent": s.agent, "action": s.action} for s in wf.steps],
                    "continue_on_failure": wf.continue_on_failure,
                }
            )
        return {"ok": True, "count": len(workflows), "workflows": workflows}

    def workflow_history(self, limit: int = 20, workflow: str | None = None) -> dict[str, Any]:
        limit = _clamp_limit(limit)
        runs = _db.get_workflow_runs(workflow=workflow, limit=limit)
        return {
            "ok": True,
            "count": len(runs),
            "runs": [self._serialize_workflow_run(r) for r in runs],
        }

    def _serialize_workflow_run(self, run: Any) -> dict[str, Any]:
        details: Any = run.details
        try:
            parsed = json.loads(run.details)
            details = parsed
        except (ValueError, TypeError):
            details = run.details
        if isinstance(details, (dict, list)):
            serialized_details: Any = details
            if len(json.dumps(details, default=str)) > _TRUNCATE_LIMIT:
                serialized_details = truncate_output(json.dumps(details, default=str), _TRUNCATE_LIMIT)
        else:
            serialized_details = truncate_output(str(details), _TRUNCATE_LIMIT)
        return {
            "id": run.id,
            "timestamp": _iso(run.timestamp),
            "workflow": run.workflow,
            "status": run.status,
            "duration_ms": run.duration_ms,
            "details": serialized_details,
        }

    def events(self, event_type: str | None = None, limit: int = 20) -> dict[str, Any]:
        limit = _clamp_limit(limit)
        records = _db.get_events(event_type=event_type, limit=limit)
        return {
            "ok": True,
            "count": len(records),
            "events": [self._serialize_event(r) for r in records],
        }

    def _serialize_event(self, record: Any) -> dict[str, Any]:
        data: Any
        try:
            data = json.loads(record.data_json)
        except (ValueError, TypeError):
            data = record.data_json
        return {
            "timestamp": _iso(record.timestamp),
            "event_type": record.event_type,
            "source": record.source,
            "severity": record.severity,
            "data": data,
        }

    def reports_list(self, report_type: str | None = None, limit: int = 20) -> dict[str, Any]:
        limit = _clamp_limit(limit)
        reports = _db.get_reports(report_type=report_type, limit=limit)
        return {
            "ok": True,
            "count": len(reports),
            "reports": [self._serialize_report(r, include_content=False) for r in reports],
        }

    def report_get(self, report_id: int) -> dict[str, Any]:
        from sqlmodel import select

        from spectre.memory.db import Report, engine as db_engine

        with Session(db_engine) as session:
            report = session.get(Report, report_id)
        if report is None:
            return {"ok": False, "status": "not_found", "report_id": report_id}
        return {"ok": True, "report": self._serialize_report(report, include_content=True)}

    def _serialize_report(self, report: Any, include_content: bool) -> dict[str, Any]:
        out: dict[str, Any] = {
            "id": report.id,
            "timestamp": _iso(report.timestamp),
            "type": report.report_type,
            "format": report.format,
        }
        if include_content:
            out["content"] = truncate_output(report.content or "", _TRUNCATE_LIMIT)
        return out

    def security_summary(self) -> dict[str, Any]:
        return {"ok": True, "summary": _db.get_security_summary()}

    def config_show(self) -> dict[str, Any]:
        settings = _settings.load_settings()
        data, key_changed = self._redact_keys(settings.model_dump())
        result: dict[str, Any] = {"ok": True, "settings": data}
        result = self._finalize(result)
        if key_changed:
            result["redacted"] = True
        return result

    def _redact_keys(self, value: Any) -> tuple[Any, bool]:
        if isinstance(value, dict):
            out: dict[str, Any] = {}
            changed = False
            for key, item in value.items():
                if any(tok in str(key).lower() for tok in _SECRET_KEY_TOKENS):
                    out[key] = "[REDACTED]"
                    changed = True
                else:
                    new_item, item_changed = self._redact_keys(item)
                    if item_changed:
                        changed = True
                    out[key] = new_item
            return out, changed
        if isinstance(value, (list, tuple)):
            out_list: list[Any] = []
            changed = False
            for item in value:
                new_item, item_changed = self._redact_keys(item)
                if item_changed:
                    changed = True
                out_list.append(new_item)
            return (tuple(out_list) if isinstance(value, tuple) else out_list), changed
        return value, False

    def config_get(self, key: str, profile: str = "default") -> dict[str, Any]:
        value = _db.get_configuration(key, profile=profile)
        if value is None:
            return {"ok": False, "status": "not_found", "key": key, "profile": profile}
        return self._finalize({"ok": True, "key": key, "value": value, "profile": profile})

    def schedule_list(self) -> dict[str, Any]:
        db_tasks: list[dict[str, Any]] = []
        try:
            from sqlmodel import select

            with Session(_db.engine) as session:
                config = session.exec(
                    select(_db.Configuration).where(_db.Configuration.key == "scheduled_tasks")
                ).first()
                if config is not None:
                    tasks = json.loads(config.value)
                    for name, task in tasks.items():
                        db_tasks.append(
                            {
                                "name": name,
                                "schedule": task["schedule"],
                                "workflow": task["workflow"],
                                "enabled": task.get("enabled", True),
                                "source": "database",
                            }
                        )
        except Exception:
            db_tasks = []
        settings = _settings.load_settings()
        settings_tasks: list[dict[str, Any]] = []
        for sched in settings.schedules:
            settings_tasks.append(
                {
                    "name": sched.name,
                    "schedule": sched.schedule,
                    "enabled": sched.enabled,
                    "source": "settings",
                }
            )
        combined = db_tasks + settings_tasks
        return self._finalize(
            {"ok": True, "count": len(combined), "tasks": combined}
        )

    def version(self) -> dict[str, Any]:
        try:
            v = _get_version("spectre")
        except Exception:
            v = "0.2.0-dev"
        return self._finalize(
            {
                "ok": True,
                "version": v,
                "python": platform.python_version(),
                "platform": f"{platform.system()} {platform.release()}",
            }
        )

    # ------------------------------------------------------------------- act
    def _preview(self, job: Any, resolved: Any, decision: Any) -> dict[str, Any]:
        return {
            "ok": False,
            "status": "confirmation_required",
            "job": job.name,
            "summary": job.summary,
            "group": job.group,
            "sudo": job.sudo,
            "mutates": job.mutates,
            "timeout": job.timeout,
            "concurrency": job.concurrency,
            "schedule_hint": job.schedule_hint,
            "resolved": str(resolved.path) if resolved is not None else None,
            "commit": resolved.git_commit if resolved is not None else None,
            "dirty": resolved.git_dirty if resolved is not None else None,
            "gates": {
                "mutations_enabled": allow_mutations(),
                "sudo_enabled": allow_sudo(),
                "root": is_root(),
            },
            "reason": decision.reason,
        }

    def action_run(
        self,
        job: str,
        args: list[str] | None = None,
        confirm: bool = False,
        timeout_seconds: int | None = None,
    ) -> dict[str, Any]:
        args = list(args or [])
        try:
            j = _registry.get_job(job)
        except KeyError:
            return {"ok": False, "status": "unknown_job", "job": job}
        try:
            resolved = _resolve(j)
        except DispatchError as exc:
            return {"ok": False, "status": "error", "reason": str(exc)}

        decision = _evaluate_policy(
            confirm=confirm,
            mutates=j.mutates,
            sudo=j.sudo,
            mutations_enabled=allow_mutations(),
            sudo_enabled=allow_sudo(),
            root=is_root(),
        )
        if decision.status == "confirmation_required":
            return self._finalize(self._preview(j, resolved, decision))
        if decision.status == "refused":
            if j.sudo and not is_root():
                reason = f"{j.name} needs root, and this process is not root; run: sudo spectre run {j.name}"
            else:
                reason = decision.reason or "refused"
            return {"ok": False, "status": "refused", "reason": reason, "job": j.name}

        timeout = j.timeout
        if timeout_seconds is not None:
            try:
                timeout = min(int(timeout_seconds), j.timeout)
            except (TypeError, ValueError):
                timeout = j.timeout
            if timeout < 1:
                timeout = j.timeout

        import threading

        # Lazy import to avoid heavy import at module load.
        from spectre.dispatch.lock import JobLock, LockUnavailable
        from spectre.dispatch.runner import run_action
        from spectre.memory.db import init_db, save_run

        _act_lock = getattr(SpectreService, "_act_lock", None)
        if _act_lock is None:
            SpectreService._act_lock = threading.Lock()
            _act_lock = SpectreService._act_lock

        try:
            with _act_lock:
                try:
                    with JobLock(j):
                        outcome = run_action(resolved, args, trigger="mcp", timeout=timeout)
                except LockUnavailable as exc:
                    return {"ok": False, "status": "locked", "reason": str(exc), "job": j.name}
                init_db()
                save_run(outcome.envelope, agent="mcp")
        except Exception as exc:  # pragma: no cover - defensive
            return {"ok": False, "status": "error", "reason": str(exc), "job": j.name}

        env = outcome.envelope
        result = {
            "ok": env.status.value == "success",
            "job": env.job,
            "status": env.status.value,
            "exit_code": env.exit_code,
            "duration_ms": env.duration_ms,
            "resolved_path": env.resolved_path,
            "git_commit": env.git_commit,
            "git_dirty": env.git_dirty,
            "stdout_tail": truncate_output(env.stdout_tail, _TRUNCATE_LIMIT),
            "stderr_tail": truncate_output(env.stderr_tail, _TRUNCATE_LIMIT),
            "payload": env.payload,
        }
        return self._finalize(result)

    def workflow_run(self, name: str, confirm: bool = False) -> dict[str, Any]:
        engine = _engine_mod.WorkflowEngine()
        definitions = engine.get_workflow_definitions()
        if name not in definitions:
            return {"ok": False, "status": "unknown_workflow", "workflow": name}
        wf = definitions[name]
        preview = {
            "name": wf.name,
            "description": wf.description,
            "steps": [{"agent": s.agent, "action": s.action} for s in wf.steps],
            "server_user": "current process user",
        }
        decision = _evaluate_policy(
            confirm=confirm,
            mutates=True,
            sudo=False,
            mutations_enabled=allow_mutations(),
            sudo_enabled=allow_sudo(),
            root=is_root(),
        )
        if decision.status == "confirmation_required":
            return self._finalize(
                {
                    "ok": False,
                    "status": "confirmation_required",
                    "workflow": name,
                    "preview": preview,
                    "reason": decision.reason,
                    "gates": {"mutations_enabled": allow_mutations()},
                }
            )
        if decision.status == "refused":
            return {"ok": False, "status": "refused", "reason": decision.reason, "workflow": name}
        try:
            result = engine.run_workflow(name)
        except Exception as exc:
            return {"ok": False, "status": "error", "reason": str(exc), "workflow": name}
        return self._finalize(
            {
                "ok": result.get("status") == "success",
                "workflow": result.get("workflow", name),
                "status": result.get("status"),
                "duration_ms": result.get("duration_ms"),
                "failed_steps": result.get("failed_steps", []),
                "details": result.get("details", {}),
            }
        )

    def config_set(self, key: str, value: str, profile: str = "default", confirm: bool = False) -> dict[str, Any]:
        preview = {
            "key": key,
            "profile": profile,
            "value": value,
            "key_exists": _db.get_configuration(key, profile=profile) is not None,
        }
        decision = _evaluate_policy(
            confirm=confirm,
            mutates=True,
            sudo=False,
            mutations_enabled=allow_mutations(),
            sudo_enabled=allow_sudo(),
            root=is_root(),
        )
        if decision.status == "confirmation_required":
            return self._finalize(
                {
                    "ok": False,
                    "status": "confirmation_required",
                    "preview": preview,
                    "reason": decision.reason,
                    "gates": {"mutations_enabled": allow_mutations()},
                }
            )
        if decision.status == "refused":
            return {"ok": False, "status": "refused", "reason": decision.reason}
        from spectre.memory.db import Configuration, save_configuration

        save_configuration(Configuration(key=key, value=value, profile=profile))
        return self._finalize({"ok": True, "key": key, "value": value, "profile": profile})

    def schedule_add(self, name: str, schedule: str, workflow: str, confirm: bool = False) -> dict[str, Any]:
        engine = _engine_mod.WorkflowEngine()
        definitions = engine.get_workflow_definitions()
        workflow_exists = workflow in definitions
        preview = {
            "name": name,
            "schedule": schedule,
            "workflow": workflow,
            "workflow_exists": workflow_exists,
        }
        decision = _evaluate_policy(
            confirm=confirm,
            mutates=True,
            sudo=False,
            mutations_enabled=allow_mutations(),
            sudo_enabled=allow_sudo(),
            root=is_root(),
        )
        if decision.status == "confirmation_required":
            return self._finalize(
                {
                    "ok": False,
                    "status": "confirmation_required",
                    "preview": preview,
                    "reason": decision.reason,
                    "gates": {"mutations_enabled": allow_mutations()},
                }
            )
        if decision.status == "refused":
            return {"ok": False, "status": "refused", "reason": decision.reason}
        if not workflow_exists:
            return {"ok": False, "status": "unknown_workflow", "workflow": workflow}
        from sqlmodel import select

        from spectre.memory.db import Configuration, engine as db_engine

        with Session(db_engine) as session:
            config = session.exec(
                select(Configuration).where(Configuration.key == "scheduled_tasks")
            ).first()
            tasks = json.loads(config.value) if config else {}
            tasks[name] = {"schedule": schedule, "workflow": workflow, "enabled": True}
            if config:
                config.value = json.dumps(tasks)
                session.add(config)
            else:
                session.add(Configuration(key="scheduled_tasks", value=json.dumps(tasks), profile="default"))
            session.commit()
        return self._finalize(
            {
                "ok": True,
                "name": name,
                "schedule": schedule,
                "workflow": workflow,
                "scheduled": False,
                "note": "recorded in the configuration store; the daemon does not consume this key, so the task is recorded intent runnable via 'spectre schedule run', not a live timer",
            }
        )

    def schedule_remove(self, name: str, confirm: bool = False) -> dict[str, Any]:
        from sqlmodel import select

        from spectre.memory.db import Configuration, engine as db_engine

        with Session(db_engine) as session:
            config = session.exec(
                select(Configuration).where(Configuration.key == "scheduled_tasks")
            ).first()
            tasks = json.loads(config.value) if config else {}
            exists = name in tasks
            current = tasks.get(name)
        preview = {
            "name": name,
            "exists": exists,
            "schedule": current.get("schedule") if current else None,
            "workflow": current.get("workflow") if current else None,
        }
        decision = _evaluate_policy(
            confirm=confirm,
            mutates=True,
            sudo=False,
            mutations_enabled=allow_mutations(),
            sudo_enabled=allow_sudo(),
            root=is_root(),
        )
        if decision.status == "confirmation_required":
            return self._finalize(
                {
                    "ok": False,
                    "status": "confirmation_required",
                    "preview": preview,
                    "reason": decision.reason,
                    "gates": {"mutations_enabled": allow_mutations()},
                }
            )
        if decision.status == "refused":
            return {"ok": False, "status": "refused", "reason": decision.reason}
        with Session(db_engine) as session:
            config = session.exec(
                select(Configuration).where(Configuration.key == "scheduled_tasks")
            ).first()
            if not config:
                return {"ok": False, "status": "not_found", "name": name}
            tasks = json.loads(config.value)
            if name not in tasks:
                return {"ok": False, "status": "not_found", "name": name}
            del tasks[name]
            config.value = json.dumps(tasks)
            session.add(config)
            session.commit()
        return self._finalize({"ok": True, "name": name, "removed": True})

    def _finalize(self, result: dict[str, Any]) -> dict[str, Any]:
        redacted_result, changed = _redact_value(result)
        if changed:
            redacted_result["redacted"] = True
        return redacted_result
