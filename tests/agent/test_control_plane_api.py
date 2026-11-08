"""Tests for the Spectre enterprise control-plane API/UI."""

from __future__ import annotations

from collections.abc import AsyncIterator
from unittest.mock import patch

import httpx
import pytest

from spectre.api.main import app

TEST_API_KEY = "test-api-key-not-a-real-secret"


@pytest.fixture(autouse=True)
def _api_key(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SPECTRE_API_KEY", TEST_API_KEY)


@pytest.fixture
async def client() -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(
        transport=transport, base_url="http://test", headers={"X-API-Key": TEST_API_KEY}
    ) as ac:
        yield ac


@pytest.fixture
async def anon_client() -> AsyncIterator[httpx.AsyncClient]:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


def _fake_overview() -> dict:
    return {
        "generated_at": "2026-11-08T00:00:00+00:00",
        "health": {"status": "ok", "blocking_findings": 0, "monitoring_up": 1, "monitoring_total": 1},
        "dispatch": {"job_count": 1, "groups": {"ops": 1}, "verify": {"blocking": 0, "advisory": 0, "findings": []}},
        "recent_runs": [],
        "backup": {"markers": [], "state_dirs_checked": []},
        "monitoring": [{"name": "Prometheus", "kind": "metrics", "url": "http://x", "status": "ok", "latency_ms": 1, "data": {}}],
    }


async def test_control_plane_dashboard_requires_auth(anon_client: httpx.AsyncClient) -> None:
    resp = await anon_client.get("/control-plane")
    assert resp.status_code == 401


async def test_control_plane_dashboard_html(client: httpx.AsyncClient) -> None:
    resp = await client.get("/control-plane")
    assert resp.status_code == 200
    assert "SPECTRE CONTROL PLANE" in resp.text
    assert "/api/control-plane/overview" in resp.text
    assert "noqa" not in resp.text


@pytest.mark.parametrize("path", ["/api/control-plane/overview", "/api/control-plane/actions"])
async def test_control_plane_endpoints_require_auth(anon_client: httpx.AsyncClient, path: str) -> None:
    resp = await anon_client.get(path)
    assert resp.status_code == 401


async def test_overview_shape(client: httpx.AsyncClient) -> None:
    with patch("spectre.api.control_plane.build_overview", return_value=_fake_overview()):
        resp = await client.get("/api/control-plane/overview")
    assert resp.status_code == 200
    data = resp.json()
    assert data["health"]["status"] == "ok"
    assert "dispatch" in data and "monitoring" in data and "recent_runs" in data


async def test_actions_lists_registry(client: httpx.AsyncClient) -> None:
    resp = await client.get("/api/control-plane/actions")
    assert resp.status_code == 200
    data = resp.json()
    assert "count" in data and "actions" in data
    assert isinstance(data["actions"], list)
    assert data["count"] == len(data["actions"])
    if data["actions"]:
        item = data["actions"][0]
        for key in ("name", "group", "summary", "action", "sudo", "mutates"):
            assert key in item


async def test_action_run_not_exposed(client: httpx.AsyncClient) -> None:
    """Control plane is observability-only; executions must happen in terminal."""
    resp = await client.post("/api/control-plane/actions/__any_job__/run")
    assert resp.status_code in {404, 405}
