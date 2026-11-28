"""Spectre MCP server — tool registration and entry point.

This module owns the `MCPServer` instance and the tool surface. It contains no
business logic: every handler delegates to `SpectreService` (see `service.py`).
"""

from __future__ import annotations

from typing import Any

from mcp.server import MCPServer
from mcp.types import ToolAnnotations

from spectre.mcp.service import SpectreService

mcp = MCPServer("spectre")

_service: SpectreService | None = None


def _get_service() -> SpectreService:
    global _service
    if _service is None:
        _service = SpectreService()
    return _service


_READ_ONLY = ToolAnnotations(read_only_hint=True)
_NOT_READ_ONLY = ToolAnnotations(read_only_hint=False)
_DESTRUCTIVE = ToolAnnotations(destructive_hint=True)
_DESTRUCTIVE_IDEMPOTENT = ToolAnnotations(destructive_hint=True, idempotent_hint=True)


# ------------------------------- read tools -------------------------------


@mcp.tool(annotations=_READ_ONLY)
def spectre_status(agent: str | None = None) -> dict[str, Any]:
    """Overall Spectre status, optionally restricted to one agent."""
    return _get_service().status(agent=agent)


@mcp.tool(annotations=_NOT_READ_ONLY)
def spectre_health() -> dict[str, Any]:
    """Run the monitoring agent's collect-metrics and check-thresholds actions."""
    return _get_service().health()


@mcp.tool(annotations=_READ_ONLY)
def spectre_actions_list(group: str | None = None, include_runs: bool = True) -> dict[str, Any]:
    """List registered dispatch jobs with their metadata."""
    return _get_service().actions_list(group=group, include_runs=include_runs)


@mcp.tool(annotations=_READ_ONLY)
def spectre_action_show(job: str) -> dict[str, Any]:
    """Show one job's registry entry and resolved path/provenance."""
    return _get_service().action_show(job=job)


@mcp.tool(annotations=_READ_ONLY)
def spectre_actions_verify() -> dict[str, Any]:
    """Preflight the registry, actions on disk, and host schedulers."""
    return _get_service().actions_verify()


@mcp.tool(annotations=_READ_ONLY)
def spectre_runs(limit: int = 20, job: str | None = None) -> dict[str, Any]:
    """Recent dispatch run records."""
    return _get_service().runs(limit=limit, job=job)


@mcp.tool(annotations=_READ_ONLY)
def spectre_workflows_list() -> dict[str, Any]:
    """List available workflows and their definitions."""
    return _get_service().workflows_list()


@mcp.tool(annotations=_READ_ONLY)
def spectre_workflow_history(limit: int = 20, workflow: str | None = None) -> dict[str, Any]:
    """Recent workflow run records."""
    return _get_service().workflow_history(limit=limit, workflow=workflow)


@mcp.tool(annotations=_READ_ONLY)
def spectre_events(event_type: str | None = None, limit: int = 20) -> dict[str, Any]:
    """Recent system events from the EventBus."""
    return _get_service().events(event_type=event_type, limit=limit)


@mcp.tool(annotations=_READ_ONLY)
def spectre_reports_list(report_type: str | None = None, limit: int = 20) -> dict[str, Any]:
    """List generated reports."""
    return _get_service().reports_list(report_type=report_type, limit=limit)


@mcp.tool(annotations=_READ_ONLY)
def spectre_report_get(report_id: int) -> dict[str, Any]:
    """Get one report by id, including its content."""
    return _get_service().report_get(report_id=report_id)


@mcp.tool(annotations=_READ_ONLY)
def spectre_security_summary() -> dict[str, Any]:
    """Current security exposure summary."""
    return _get_service().security_summary()


@mcp.tool(annotations=_READ_ONLY)
def spectre_config_show() -> dict[str, Any]:
    """Show the current YAML settings (secret-looking keys redacted)."""
    return _get_service().config_show()


@mcp.tool(annotations=_READ_ONLY)
def spectre_config_get(key: str, profile: str = "default") -> dict[str, Any]:
    """Get one database configuration value."""
    return _get_service().config_get(key=key, profile=profile)


@mcp.tool(annotations=_READ_ONLY)
def spectre_schedule_list() -> dict[str, Any]:
    """List scheduled tasks from both stores."""
    return _get_service().schedule_list()


@mcp.tool(annotations=_READ_ONLY)
def spectre_version() -> dict[str, Any]:
    """Spectre version and host information."""
    return _get_service().version()


# -------------------------------- act tools -------------------------------


@mcp.tool(annotations=_DESTRUCTIVE)
def spectre_action_run(
    job: str,
    args: list[str] | None = None,
    confirm: bool = False,
    timeout_seconds: int | None = None,
) -> dict[str, Any]:
    """Run one registered dispatch job (gated)."""
    return _get_service().action_run(job=job, args=args, confirm=confirm, timeout_seconds=timeout_seconds)


@mcp.tool(annotations=_DESTRUCTIVE)
def spectre_workflow_run(name: str, confirm: bool = False) -> dict[str, Any]:
    """Run one workflow (gated)."""
    return _get_service().workflow_run(name=name, confirm=confirm)


@mcp.tool(annotations=_DESTRUCTIVE_IDEMPOTENT)
def spectre_config_set(key: str, value: str, profile: str = "default", confirm: bool = False) -> dict[str, Any]:
    """Write one database configuration value (gated)."""
    return _get_service().config_set(key=key, value=value, profile=profile, confirm=confirm)


@mcp.tool(annotations=_DESTRUCTIVE_IDEMPOTENT)
def spectre_schedule_add(name: str, schedule: str, workflow: str, confirm: bool = False) -> dict[str, Any]:
    """Add a scheduled task (gated; recorded intent, not a live timer)."""
    return _get_service().schedule_add(name=name, schedule=schedule, workflow=workflow, confirm=confirm)


@mcp.tool(annotations=_DESTRUCTIVE_IDEMPOTENT)
def spectre_schedule_remove(name: str, confirm: bool = False) -> dict[str, Any]:
    """Remove a scheduled task (gated)."""
    return _get_service().schedule_remove(name=name, confirm=confirm)


def main() -> None:
    """Run the Spectre MCP server over stdio."""
    mcp.run()
