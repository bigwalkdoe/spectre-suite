"""Task 4: read-method tests for the Spectre MCP service."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import patch

import pytest

mcp = pytest.importorskip("mcp")

from spectre.mcp import service as svc_mod  # noqa: E402
from spectre.mcp.service import SpectreService  # noqa: E402


class FakeAgent:
    def __init__(self, observe_result=None, execute_result=None):
        self._observe = observe_result if observe_result is not None else {"ok": True}
        self._execute = execute_result if execute_result is not None else {}

    def initialize(self):
        return None

    def observe(self):
        return self._observe

    def execute(self, plan):
        return self._execute


def _job(name="demo-job", group="maintenance", sudo=False, mutates=False):
    return SimpleNamespace(
        name=name,
        group=group,
        summary=f"summary for {name}",
        action=f"{name}.sh",
        sudo=sudo,
        mutates=mutates,
        timeout=1800,
        concurrency="allow",
        schedule_hint=None,
        replaces=[],
    )


def test_actions_list_returns_jobs(monkeypatch):
    monkeypatch.setattr(svc_mod._registry, "JOBS", [_job("a-job"), _job("b-job")])
    monkeypatch.setattr(svc_mod, "_record_growth", lambda: {"a-job": "3"})
    service = SpectreService()
    result = service.actions_list()
    assert result["ok"] is True
    assert result["count"] == 2
    assert [j["name"] for j in result["jobs"]] == ["a-job", "b-job"]
    assert result["jobs"][0]["runs"] == "3"
    assert result["jobs"][1]["runs"] == "0"


def test_actions_list_group_filter(monkeypatch):
    monkeypatch.setattr(svc_mod._registry, "JOBS", [_job("a-job", group="g1"), _job("b-job", group="g2")])
    monkeypatch.setattr(svc_mod, "_record_growth", lambda: None)
    service = SpectreService()
    result = service.actions_list(group="g1")
    assert result["count"] == 1
    assert result["jobs"][0]["name"] == "a-job"


def test_action_show_unknown_job(monkeypatch):
    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: (_ for _ in ()).throw(KeyError(name)))
    service = SpectreService()
    result = service.action_show("nope")
    assert result["ok"] is False
    assert result["status"] == "unknown_job"


def test_action_show_known_job(monkeypatch):
    j = _job("demo-job")
    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: j)
    resolved = SimpleNamespace(path="/tmp/demo.sh", git_commit="abc1234", git_dirty=False)
    monkeypatch.setattr(svc_mod, "_resolve", lambda job: resolved)
    service = SpectreService()
    result = service.action_show("demo-job")
    assert result["ok"] is True
    assert result["job"] == "demo-job"
    assert result["resolved"] == "/tmp/demo.sh"
    assert result["commit"] == "abc1234"
    assert result["dirty"] is False


def test_status_unknown_agent_returns_error(monkeypatch):
    monkeypatch.setattr(svc_mod._engine_mod, "_AGENT_FACTORIES", {"linux": FakeAgent})
    monkeypatch.setattr(svc_mod, "_make_agent", lambda name: FakeAgent(observe_result={"hostname": "h"}))
    service = SpectreService()
    result = service.status(agent="nope")
    assert result["ok"] is False
    assert result["status"] == "unknown_agent"


def test_status_single_agent(monkeypatch):
    monkeypatch.setattr(svc_mod._engine_mod, "_AGENT_FACTORIES", {"linux": FakeAgent})
    monkeypatch.setattr(svc_mod, "_make_agent", lambda name: FakeAgent(observe_result={"hostname": "h"}))
    service = SpectreService()
    result = service.status(agent="linux")
    assert result["ok"] is True
    assert result["agents"]["linux"] == {"hostname": "h"}


def test_status_captures_agent_failure(monkeypatch):
    class BoomAgent(FakeAgent):
        def observe(self):
            raise RuntimeError("boom")

    monkeypatch.setattr(svc_mod._engine_mod, "_AGENT_FACTORIES", {"linux": BoomAgent})
    monkeypatch.setattr(svc_mod, "_make_agent", lambda name: BoomAgent())
    service = SpectreService()
    result = service.status(agent="linux")
    # _make_agent is bypassed? service calls _make_agent; but status uses _make_agent then observe.
    # Actually status calls _make_agent then observe; observe raises -> caught -> error dict.
    assert result["ok"] is True
    assert "error" in result["agents"]["linux"]


def test_health_returns_metrics_and_thresholds(monkeypatch):
    agent = FakeAgent(execute_result={"collect-metrics": {"status": "success", "log_output": "m"}, "check-thresholds": {"status": "success", "log_output": "t"}})
    monkeypatch.setattr(svc_mod, "_make_agent", lambda name: agent)
    service = SpectreService()
    result = service.health()
    assert result["ok"] is True
    assert result["metrics"]["status"] == "success"
    assert result["thresholds"]["status"] == "success"


def test_runs_serializes_records(monkeypatch):
    rec = SimpleNamespace(
        id=1,
        timestamp=datetime(2026, 1, 1, tzinfo=timezone.utc),
        agent="linux",
        action="system-health-check",
        status="success",
        log_output="ok",
        duration_ms=10,
        trigger="cli",
        exit_code=0,
        resolved_path="/p",
        git_commit="abc",
        git_dirty=False,
        payload='{"x": 1}',
        stderr_tail="",
    )
    monkeypatch.setattr(svc_mod._db, "recent_runs", lambda limit, job=None: [rec])
    service = SpectreService()
    result = service.runs(limit=5, job="system-health-check")
    assert result["ok"] is True
    assert result["count"] == 1
    r = result["runs"][0]
    assert r["id"] == 1
    assert r["action"] == "system-health-check"
    assert r["payload"] == {"x": 1}
    assert r["log_output"] == "ok"


def test_reports_list_and_get(monkeypatch):
    rep = SimpleNamespace(id=7, timestamp=datetime(2026, 1, 1, tzinfo=timezone.utc), report_type="daily", content="hello", format="markdown")
    monkeypatch.setattr(svc_mod._db, "get_reports", lambda report_type=None, limit=50: [rep])
    # report_get uses session.get; monkeypatch _db.Report and _db.engine indirectly is hard.
    # Patch SpectreService.report_get by monkeypatching the module-level Report/engine.
    import spectre.memory.db as db_mod

    class FakeSession:
        def __init__(self, engine):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return None

        def get(self, model, rid):
            return rep if rid == 7 else None

    monkeypatch.setattr(db_mod, "Report", object)
    monkeypatch.setattr("spectre.mcp.service.Session", lambda engine: FakeSession(engine))
    service = SpectreService()
    listed = service.reports_list()
    assert listed["ok"] is True
    assert listed["count"] == 1
    assert listed["reports"][0]["id"] == 7
    got = service.report_get(7)
    assert got["ok"] is True
    assert got["report"]["content"] == "hello"
    missing = service.report_get(999)
    assert missing["ok"] is False
    assert missing["status"] == "not_found"


def test_events_serializes(monkeypatch):
    ev = SimpleNamespace(id=1, timestamp=datetime(2026, 1, 1, tzinfo=timezone.utc), event_type="x", source="s", severity="info", data_json='{"a": 1}')
    monkeypatch.setattr(svc_mod._db, "get_events", lambda event_type=None, limit=100: [ev])
    service = SpectreService()
    result = service.events(event_type="x", limit=5)
    assert result["ok"] is True
    assert result["events"][0]["data"] == {"a": 1}
    assert result["events"][0]["event_type"] == "x"


def test_security_summary(monkeypatch):
    monkeypatch.setattr(svc_mod._db, "get_security_summary", lambda: {"unresolved_total": 0})
    service = SpectreService()
    result = service.security_summary()
    assert result["ok"] is True
    assert result["summary"]["unresolved_total"] == 0


def test_config_show_and_get(monkeypatch):
    from spectre.config import settings as settings_mod

    class S:
        def model_dump(self):
            return {"profile": "laptop", "secret_key": "hunter2hunter2hunter2"}

    monkeypatch.setattr(settings_mod, "load_settings", lambda: S())
    monkeypatch.setattr(svc_mod._db, "get_configuration", lambda key, profile="default": "val" if key == "k" else None)
    service = SpectreService()
    shown = service.config_show()
    assert shown["ok"] is True
    assert shown["settings"]["profile"] == "laptop"
    # secret-looking key redacted
    assert shown["settings"]["secret_key"] == "[REDACTED]"
    assert shown.get("redacted") is True
    got = service.config_get("k")
    assert got["ok"] is True
    assert got["value"] == "val"
    missing = service.config_get("nope")
    assert missing["ok"] is False
    assert missing["status"] == "not_found"


def test_schedule_list_combines_sources(monkeypatch):
    from spectre.config import settings as settings_mod
    from spectre.config.settings import WorkflowSchedule

    class S:
        schedules = [WorkflowSchedule(name="s1", schedule="every 5m", enabled=True)]

    monkeypatch.setattr(settings_mod, "load_settings", lambda: S())
    import spectre.memory.db as db_mod

    class FakeSession:
        def __init__(self, engine):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return None

        def exec(self, stmt):
            return self

        def first(self):
            return SimpleNamespace(value=json.dumps({"t1": {"schedule": "0 * * * *", "workflow": "w", "enabled": True}}))

    monkeypatch.setattr(db_mod, "engine", object())
    monkeypatch.setattr("spectre.mcp.service.Session", lambda engine: FakeSession(engine))
    service = SpectreService()
    result = service.schedule_list()
    assert result["ok"] is True
    sources = {t["source"] for t in result["tasks"]}
    assert "database" in sources
    assert "settings" in sources
    names = {t["name"] for t in result["tasks"]}
    assert "t1" in names
    assert "s1" in names


def test_version_returns_version(monkeypatch):
    service = SpectreService()
    result = service.version()
    assert result["ok"] is True
    assert "version" in result
    assert "python" in result
    assert "platform" in result


def test_actions_verify_returns_counts(monkeypatch):
    inv = SimpleNamespace(unreadable=())
    monkeypatch.setattr(svc_mod._verify, "read_host_inventory", lambda: inv)
    monkeypatch.setattr(svc_mod._verify, "verify", lambda inventory: [])
    monkeypatch.setattr(svc_mod._verify, "ALL_CODES", ("MISSING",))
    monkeypatch.setattr(svc_mod._verify, "BLOCKING_CODES", frozenset())
    monkeypatch.setattr(svc_mod, "_actions_root", lambda: "/tmp/actions")
    monkeypatch.setattr(svc_mod._registry, "JOBS", [])
    service = SpectreService()
    result = service.actions_verify()
    assert result["ok"] is True
    assert result["blocking_count"] == 0
    assert result["counts"] == {"MISSING": 0}
    assert result["verdict"] == "no blocking findings"


def test_workflows_list(monkeypatch):
    from spectre.workflow_engine.engine import WorkflowDefinition, Step

    wf = WorkflowDefinition(name="w1", description="d", steps=[Step(agent="linux", action="system-health-check")], continue_on_failure=False)
    engine = SimpleNamespace(get_workflow_definitions=lambda: {"w1": wf})
    monkeypatch.setattr(svc_mod._engine_mod, "WorkflowEngine", lambda *a, **k: engine)
    service = SpectreService()
    result = service.workflows_list()
    assert result["ok"] is True
    assert result["workflows"][0]["name"] == "w1"
    assert result["workflows"][0]["steps"] == [{"agent": "linux", "action": "system-health-check"}]


def test_workflow_history_serializes(monkeypatch):
    run = SimpleNamespace(id=1, timestamp=datetime(2026, 1, 1, tzinfo=timezone.utc), workflow="w1", status="success", duration_ms=5, details='{"a": 1}')
    monkeypatch.setattr(svc_mod._db, "get_workflow_runs", lambda workflow=None, limit=50: [run])
    service = SpectreService()
    result = service.workflow_history(limit=5)
    assert result["ok"] is True
    assert result["runs"][0]["details"] == {"a": 1}


# ---------------- Task 5: act method tests ----------------


def _fake_job(name="demo-job", mutates=False, sudo=False):
    from types import SimpleNamespace

    return SimpleNamespace(
        name=name,
        group="maintenance",
        summary=f"summary for {name}",
        action=f"{name}.sh",
        sudo=sudo,
        mutates=mutates,
        timeout=1800,
        concurrency="allow",
        schedule_hint=None,
        replaces=[],
    )


def _fake_resolved(name="demo-job"):
    from types import SimpleNamespace

    return SimpleNamespace(job=_fake_job(name), path="/tmp/demo.sh", git_commit="abc1234", git_dirty=False)


def _fake_envelope(name="demo-job", status="success"):
    from types import SimpleNamespace

    return SimpleNamespace(
        job=name,
        status=SimpleNamespace(value=status),
        exit_code=0,
        duration_ms=10,
        resolved_path="/tmp/demo.sh",
        git_commit="abc1234",
        git_dirty=False,
        stdout_tail="out",
        stderr_tail="err",
        payload={"x": 1},
    )


def test_action_run_unknown_job(monkeypatch):
    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: (_ for _ in ()).throw(KeyError(name)))
    service = SpectreService()
    result = service.action_run("nope", confirm=True)
    assert result["ok"] is False
    assert result["status"] == "unknown_job"


def test_action_run_preview_without_confirm(monkeypatch):
    job = _fake_job("demo-job")
    resolved = _fake_resolved("demo-job")
    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: job)
    monkeypatch.setattr(svc_mod, "_resolve", lambda j: resolved)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: False)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    result = service.action_run("demo-job", confirm=False)
    assert result["status"] == "confirmation_required"
    assert result["job"] == "demo-job"
    assert result["resolved"] == "/tmp/demo.sh"


def test_action_run_mutating_refused_when_disabled(monkeypatch):
    job = _fake_job("demo-job", mutates=True)
    resolved = _fake_resolved("demo-job")
    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: job)
    monkeypatch.setattr(svc_mod, "_resolve", lambda j: resolved)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: False)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    result = service.action_run("demo-job", confirm=True)
    assert result["ok"] is False
    assert result["status"] == "refused"
    assert "SPECTRE_MCP_ALLOW_MUTATIONS" in result["reason"]


def test_action_run_sudo_refused_when_not_root(monkeypatch):
    job = _fake_job("demo-job", sudo=True)
    resolved = _fake_resolved("demo-job")
    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: job)
    monkeypatch.setattr(svc_mod, "_resolve", lambda j: resolved)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: True)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: True)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    result = service.action_run("demo-job", confirm=True)
    assert result["ok"] is False
    assert result["status"] == "refused"
    assert "needs root" in result["reason"]


def test_action_run_runs_via_dispatch(monkeypatch):
    import spectre.dispatch.lock as lock_mod
    import spectre.dispatch.runner as runner_mod
    import spectre.memory.db as db_mod

    job = _fake_job("demo-job")
    resolved = _fake_resolved("demo-job")
    env = _fake_envelope("demo-job")
    outcome = SimpleNamespace(envelope=env) if False else None
    from types import SimpleNamespace as SN

    outcome = SN(envelope=env)

    class FakeLock:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return None

    monkeypatch.setattr(svc_mod._registry, "get_job", lambda name: job)
    monkeypatch.setattr(svc_mod, "_resolve", lambda j: resolved)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: True)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: True)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    monkeypatch.setattr(lock_mod, "JobLock", lambda j: FakeLock())
    monkeypatch.setattr(lock_mod, "LockUnavailable", Exception)
    monkeypatch.setattr(runner_mod, "run_action", lambda resolved, args, trigger, timeout: outcome)
    monkeypatch.setattr(db_mod, "init_db", lambda: None)
    monkeypatch.setattr(db_mod, "save_run", lambda env, agent="dispatch": 1)
    service = SpectreService()
    result = service.action_run("demo-job", args=["--flag"], confirm=True)
    assert result["ok"] is True
    assert result["status"] == "success"
    assert result["job"] == "demo-job"
    assert result["stdout_tail"] == "out"
    assert result["payload"] == {"x": 1}


def test_action_run_config_set_preview_no_old_value(monkeypatch):
    monkeypatch.setattr(svc_mod._db, "get_configuration", lambda key, profile="default": "old-secret-value")
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: False)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    result = service.config_set("k", "new", confirm=False)
    assert result["status"] == "confirmation_required"
    assert "preview" in result
    assert result["preview"]["key"] == "k"
    assert result["preview"]["value"] == "new"
    assert "old" not in str(result["preview"]).lower() or "old-secret-value" not in str(result)
    assert "old-secret-value" not in str(result)


def test_config_set_refused_when_disabled(monkeypatch):
    monkeypatch.setattr(svc_mod._db, "get_configuration", lambda key, profile="default": None)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: False)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    result = service.config_set("k", "v", confirm=True)
    assert result["ok"] is False
    assert result["status"] == "refused"


def test_workflow_run_unknown(monkeypatch):
    engine = SimpleNamespace(get_workflow_definitions=lambda: {})
    monkeypatch.setattr(svc_mod._engine_mod, "WorkflowEngine", lambda *a, **k: engine)
    service = SpectreService()
    result = service.workflow_run("nope", confirm=True)
    assert result["ok"] is False
    assert result["status"] == "unknown_workflow"


def test_workflow_run_refused_when_disabled(monkeypatch):
    from spectre.workflow_engine.engine import WorkflowDefinition, Step

    wf = WorkflowDefinition(name="w1", description="d", steps=[Step(agent="linux", action="system-health-check")], continue_on_failure=False)
    engine = SimpleNamespace(get_workflow_definitions=lambda: {"w1": wf}, run_workflow=lambda name: {"workflow": name, "status": "success", "duration_ms": 1, "failed_steps": [], "details": {}})
    monkeypatch.setattr(svc_mod._engine_mod, "WorkflowEngine", lambda *a, **k: engine)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: False)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    result = service.workflow_run("w1", confirm=True)
    assert result["ok"] is False
    assert result["status"] == "refused"


def test_schedule_add_returns_not_scheduled(monkeypatch):
    from spectre.workflow_engine.engine import WorkflowDefinition, Step

    wf = WorkflowDefinition(name="w1", description="d", steps=[], continue_on_failure=False)
    engine = SimpleNamespace(get_workflow_definitions=lambda: {"w1": wf})
    monkeypatch.setattr(svc_mod._engine_mod, "WorkflowEngine", lambda *a, **k: engine)
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: True)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    import spectre.memory.db as db_mod
    from sqlmodel import Session as RealSession

    class FakeSession:
        def __init__(self, engine):
            self._config = None

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return None

        def exec(self, stmt):
            return self

        def first(self):
            return None

        def add(self, obj):
            pass

        def commit(self):
            pass

    monkeypatch.setattr("spectre.mcp.service.Session", lambda engine: FakeSession(engine))
    monkeypatch.setattr(db_mod, "engine", object())
    service = SpectreService()
    result = service.schedule_add("t1", "0 * * * *", "w1", confirm=True)
    assert result["ok"] is True
    assert result["scheduled"] is False
    assert "daemon" in result["note"]


def test_schedule_remove_not_found(monkeypatch):
    import spectre.memory.db as db_mod

    class FakeSession:
        def __init__(self, engine):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return None

        def exec(self, stmt):
            return self

        def first(self):
            return None

    monkeypatch.setattr("spectre.mcp.service.Session", lambda engine: FakeSession(engine))
    monkeypatch.setattr(db_mod, "engine", object())
    monkeypatch.setattr(svc_mod, "allow_mutations", lambda: True)
    monkeypatch.setattr(svc_mod, "allow_sudo", lambda: False)
    monkeypatch.setattr(svc_mod, "is_root", lambda: False)
    service = SpectreService()
    # preview step: confirm=False returns confirmation_required without touching db
    result = service.schedule_remove("nope", confirm=False)
    assert result["status"] == "confirmation_required"
