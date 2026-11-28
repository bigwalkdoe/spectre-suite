"""Act policy for the Spectre MCP server: confirmation and capability gates.

The authorization model is two-layered by design (see the design doc):

- The environment gate (`SPECTRE_MCP_ALLOW_MUTATIONS` / `SPECTRE_MCP_ALLOW_SUDO`)
  is the real authorization. An operator turns it on at server launch.
- The per-call `confirm` flag is the preview/run courtesy. Without it the service
  returns a preview and executes nothing; with it and with the gates open, the
  act is allowed.
"""

from __future__ import annotations

import os
from dataclasses import dataclass

MUTATIONS_ENV = "SPECTRE_MCP_ALLOW_MUTATIONS"
SUDO_ENV = "SPECTRE_MCP_ALLOW_SUDO"

_TRUE = frozenset({"1", "true", "yes", "on"})


@dataclass(frozen=True)
class Decision:
    """Outcome of one act-policy evaluation."""

    allowed: bool
    status: str
    reason: str | None = None


def allow_mutations() -> bool:
    """Whether the operator enabled mutating actions on this server."""
    return os.environ.get(MUTATIONS_ENV, "").strip().lower() in _TRUE


def allow_sudo() -> bool:
    """Whether the operator enabled root execution on this server."""
    return os.environ.get(SUDO_ENV, "").strip().lower() in _TRUE


def is_root() -> bool:
    """Whether this server process runs as root."""
    return os.geteuid() == 0


def evaluate(
    *,
    confirm: bool,
    mutates: bool,
    sudo: bool,
    mutations_enabled: bool,
    sudo_enabled: bool,
    root: bool,
) -> Decision:
    """Decide one act call.

    Order matters: the confirmation gate is checked first, then the mutation
    gate, then the sudo gate. A refused or previewed call never executes.
    """
    if not confirm:
        return Decision(
            allowed=False,
            status="confirmation_required",
            reason="confirm=true is required before this call may execute",
        )
    if mutates and not mutations_enabled:
        return Decision(
            allowed=False,
            status="refused",
            reason=f"mutating actions require {MUTATIONS_ENV}=1",
        )
    if sudo and not root:
        return Decision(
            allowed=False,
            status="refused",
            reason="this action requires root; run: sudo spectre run <job>",
        )
    if sudo and root and not sudo_enabled:
        return Decision(
            allowed=False,
            status="refused",
            reason=f"root access requires {SUDO_ENV}=1",
        )
    return Decision(allowed=True, status="ok")
