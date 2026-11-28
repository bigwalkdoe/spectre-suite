"""Task 2: policy tests for the Spectre MCP act gates."""

from __future__ import annotations

from spectre.mcp.policy import evaluate


def _decision(*, confirm: bool, mutates: bool, sudo: bool, mutations_enabled: bool, sudo_enabled: bool, root: bool):
    return evaluate(
        confirm=confirm,
        mutates=mutates,
        sudo=sudo,
        mutations_enabled=mutations_enabled,
        sudo_enabled=sudo_enabled,
        root=root,
    )


def test_requires_confirmation_before_anything_runs() -> None:
    decision = _decision(
        confirm=False,
        mutates=False,
        sudo=False,
        mutations_enabled=False,
        sudo_enabled=False,
        root=False,
    )
    assert decision.allowed is False
    assert decision.status == "confirmation_required"
    assert decision.reason is not None


def test_mutating_job_refused_when_mutations_disabled() -> None:
    decision = _decision(
        confirm=True,
        mutates=True,
        sudo=False,
        mutations_enabled=False,
        sudo_enabled=False,
        root=True,
    )
    assert decision.allowed is False
    assert decision.status == "refused"
    assert "SPECTRE_MCP_ALLOW_MUTATIONS" in str(decision.reason)


def test_sudo_job_refused_when_not_root() -> None:
    decision = _decision(
        confirm=True,
        mutates=False,
        sudo=True,
        mutations_enabled=True,
        sudo_enabled=True,
        root=False,
    )
    assert decision.allowed is False
    assert decision.status == "refused"
    assert decision.reason is not None


def test_sudo_job_refused_when_root_not_enabled() -> None:
    decision = _decision(
        confirm=True,
        mutates=False,
        sudo=True,
        mutations_enabled=True,
        sudo_enabled=False,
        root=True,
    )
    assert decision.allowed is False
    assert decision.status == "refused"
    assert "SPECTRE_MCP_ALLOW_SUDO" in str(decision.reason)


def test_full_access_allowed_when_gates_open() -> None:
    decision = _decision(
        confirm=True,
        mutates=True,
        sudo=True,
        mutations_enabled=True,
        sudo_enabled=True,
        root=True,
    )
    assert decision.allowed is True
    assert decision.status == "ok"


def test_read_only_job_allowed_with_confirmation() -> None:
    decision = _decision(
        confirm=True,
        mutates=False,
        sudo=False,
        mutations_enabled=False,
        sudo_enabled=False,
        root=False,
    )
    assert decision.allowed is True
    assert decision.status == "ok"
