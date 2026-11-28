"""Task 1 scaffold tests for the spectre.mcp package."""

import pytest

pytest.importorskip("mcp")


def test_mcp_package_exports_main() -> None:
    import spectre.mcp.server as server_module

    assert callable(server_module.main)
