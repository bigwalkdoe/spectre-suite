"""Task 3: redaction tests for the Spectre MCP tool-output redactor."""

from __future__ import annotations

from typing import Any

from spectre.mcp.redact import REDACTED, redact, redact_text


def test_redact_text_replaces_private_key_block() -> None:
    text = "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----"
    new, changed = redact_text(text)
    assert changed is True
    assert REDACTED in new


def test_redact_text_replaces_bearer_token() -> None:
    text = "Authorization: Bearer abcdefghijklmnopqrstuvwx"
    new, changed = redact_text(text)
    assert changed is True
    assert "abcdefghijklmnopqrstuvwx" not in new
    assert REDACTED in new


def test_redact_text_replaces_assignment_value() -> None:
    text = 'PASSWORD = "supersecretvalue123"'
    new, changed = redact_text(text)
    assert changed is True
    assert REDACTED in new
    assert "supersecretvalue123" not in new


def test_redact_text_leaves_short_and_ordinary_values() -> None:
    new, changed = redact_text("db_host = localhost is fine")
    assert changed is False
    assert new == "db_host = localhost is fine"


def test_redact_text_replaces_known_token_prefix() -> None:
    token = "ghp_" + "a" * 36
    new, changed = redact_text(f"token: {token}")
    assert changed is True
    assert token not in new
    assert REDACTED in new


def test_redact_text_leaves_ordinary_text_alone() -> None:
    new, changed = redact_text("No findings in the scan today. System nominal.")
    assert changed is False
    assert new == "No findings in the scan today. System nominal."


def test_redact_recurses_into_nested_structures() -> None:
    value: dict[str, Any] = {"job": "x", "log_output": "Bearer abcdefghijklmnopqrstuvwx"}
    redacted, changed = redact(value)
    assert changed is True
    assert redacted["job"] == "x"
    assert "abcdefghijklmnopqrstuvwx" not in str(redacted["log_output"])
    assert REDACTED in str(redacted["log_output"])


def test_redact_leaves_scalars_untouched() -> None:
    assert redact(42) == (42, False)
    assert redact(True) == (True, False)
    assert redact(None) == (None, False)
