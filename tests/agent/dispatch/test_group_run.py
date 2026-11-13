"""Tests for spectre run <group> sequential execution."""

from __future__ import annotations

import typer
import pytest

from spectre.cli import dispatch_cmds
from spectre.dispatch.registry import Job


def _job(name: str, group: str = "test-group") -> Job:
    return Job(
        name=name,
        action=f"{name}.sh",
        group=group,
        summary=f"test job {name}",
        sudo=False,
        mutates=False,
        timeout=1800,
        concurrency="allow",
        schedule_hint=None,
        replaces=[],
    )


def test_run_group_runs_all_jobs_in_order(monkeypatch: pytest.MonkeyPatch) -> None:
    """run_group calls run_action_job for every job in the group, in registry order."""
    called: list[str] = []

    def fake_run(job: Job, args: list[str]) -> None:
        called.append(job.name)

    monkeypatch.setattr(dispatch_cmds, "run_action_job", fake_run)
    monkeypatch.setattr(
        dispatch_cmds.registry, "JOBS", [_job("zz-last"), _job("aa-first"), _job("mm-mid")]
    )

    code = dispatch_cmds.run_group("test-group", [])

    assert code == 0
    assert called == ["aa-first", "mm-mid", "zz-last"]


def test_run_group_stops_on_first_failure(monkeypatch: pytest.MonkeyPatch) -> None:
    """run_group stops after the first failing job and returns its exit code."""
    calls: list[str] = []

    def fake_run(job: Job, args: list[str]) -> None:
        calls.append(job.name)
        if job.name == "aa-first":
            raise typer.Exit(5)

    monkeypatch.setattr(dispatch_cmds, "run_action_job", fake_run)
    monkeypatch.setattr(
        dispatch_cmds.registry, "JOBS", [_job("aa-first"), _job("mm-mid"), _job("zz-last")]
    )

    code = dispatch_cmds.run_group("test-group", [])

    assert code == 5
    assert calls == ["aa-first"]


def test_run_group_empty_group_returns_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    """An empty group reports nothing to run and exits 0."""
    monkeypatch.setattr(dispatch_cmds.registry, "JOBS", [])
    monkeypatch.setattr(dispatch_cmds.registry, "groups", lambda: [])

    code = dispatch_cmds.run_group("empty-group", [])

    assert code == 0
