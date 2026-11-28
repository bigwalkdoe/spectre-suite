"""Task 7: subprocess stdio smoke test for the Spectre MCP server."""

from __future__ import annotations

import sys

import anyio
import pytest

pytest.importorskip("mcp")

from mcp import Client
from mcp.client.stdio import StdioServerParameters

from spectre.mcp.server import mcp as _inproc_mcp  # noqa: F401  # ensures importability


def test_stdio_server_lists_tools() -> None:
    params = StdioServerParameters(command=sys.executable, args=["-m", "spectre.mcp"])

    async def main() -> None:
        async with Client(params) as client:
            result = await client.list_tools()
            assert len(result.tools) >= 21

    anyio.run(main)
