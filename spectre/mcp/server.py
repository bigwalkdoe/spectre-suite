"""Spectre MCP server — exposes Spectre's operator surfaces as MCP tools.

The server itself carries no logic: it owns the `MCPServer` instance and the
`main()` entry point. Tool definitions and their handlers live in modules under
this package and are registered onto this instance.
"""

from mcp.server import MCPServer

mcp = MCPServer("spectre")


def main() -> None:
    """Run the Spectre MCP server over its transport (stdio for v1)."""
    mcp.run()
