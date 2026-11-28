"""Task 6: in-memory MCP client tests for the Spectre server."""

from __future__ import annotations

import anyio
import pytest

pytest.importorskip("mcp")

from mcp import Client

from spectre.mcp.server import mcp

EXPECTED_TOOLS = {
    "spectre_status",
    "spectre_health",
    "spectre_actions_list",
    "spectre_action_show",
    "spectre_actions_verify",
    "spectre_runs",
    "spectre_workflows_list",
    "spectre_workflow_history",
    "spectre_events",
    "spectre_reports_list",
    "spectre_report_get",
    "spectre_security_summary",
    "spectre_config_show",
    "spectre_config_get",
    "spectre_schedule_list",
    "spectre_version",
    "spectre_action_run",
    "spectre_workflow_run",
    "spectre_config_set",
    "spectre_schedule_add",
    "spectre_schedule_remove",
}


def _run(coro_func):
    async def main():
        async with Client(mcp) as c:
            await coro_func(c)

    anyio.run(main)


def test_all_expected_tools_registered() -> None:
    async def body(c: Client) -> None:
        result = await c.list_tools()
        names = {t.name for t in result.tools}
        assert EXPECTED_TOOLS.issubset(names)

    _run(body)


def test_health_tool_is_not_read_only() -> None:
    async def body(c: Client) -> None:
        result = await c.list_tools()
        by_name = {t.name: t for t in result.tools}
        assert by_name["spectre_health"].annotations is not None
        assert by_name["spectre_health"].annotations.read_only_hint is False

    _run(body)


def test_actions_list_returns_jobs() -> None:
    async def body(c: Client) -> None:
        result = await c.call_tool("spectre_actions_list", {"include_runs": False})
        assert result.is_error is False
        data = result.structured_content
        assert data is not None
        assert data["ok"] is True
        assert data["count"] >= 1
        assert isinstance(data["jobs"], list)

    _run(body)


def test_action_show_unknown_job() -> None:
    async def body(c: Client) -> None:
        result = await c.call_tool("spectre_action_show", {"job": "definitely-not-a-job"})
        data = result.structured_content
        assert data is not None
        assert data["ok"] is False
        assert data["status"] == "unknown_job"

    _run(body)


def test_action_run_preview_without_confirm() -> None:
    async def body(c: Client) -> None:
        result = await c.call_tool("spectre_action_run", {"job": "check-config-consistency", "confirm": False})
        data = result.structured_content
        assert data is not None
        assert data["status"] == "confirmation_required"
        assert data["job"] == "check-config-consistency"

    _run(body)


def test_version_tool() -> None:
    async def body(c: Client) -> None:
        result = await c.call_tool("spectre_version", {})
        data = result.structured_content
        assert data is not None
        assert data["ok"] is True
        assert "version" in data

    _run(body)
