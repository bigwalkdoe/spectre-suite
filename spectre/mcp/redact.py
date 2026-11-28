"""Shared best-effort secret redaction for MCP tool results.

Every tool result that can carry text passes through here before it is returned
to the client. The redactor is conservative and pattern-based; it is not a
guarantee. When a replacement happens the result is marked so callers and
consumers can tell.
"""

from __future__ import annotations

import re
from typing import Any

REDACTED = "[REDACTED]"

_PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----", re.DOTALL)
_BEARER = re.compile(r"(?i)(\bBearer\s+)([A-Za-z0-9._~+/=-]{16,})")
_ASSIGNMENT = re.compile(
    r"(?i)(\b(?:password|passwd|secret|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|token)\b)(\s*[:=]\s*)(['\"]?)[^\s'\"]{8,}['\"]?"
)
_KNOWN_PREFIX = re.compile(
    r"(?i)\b(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,})\b"
)


def _redact_assignment(match: re.Match[str]) -> str:
    return f"{match.group(1)}{match.group(2)}[REDACTED]{match.group(3) or ''}"


def redact_text(text: str) -> tuple[str, bool]:
    """Redact secrets from one string. Returns (new_text, changed)."""
    changed = False
    out = text
    subs: list[tuple[re.Pattern[str], Any]] = [
        (_PRIVATE_KEY, lambda m: REDACTED),
        (_BEARER, lambda m: f"{m.group(1)}[REDACTED]"),
        (_ASSIGNMENT, _redact_assignment),
        (_KNOWN_PREFIX, lambda m: REDACTED),
    ]
    for pattern, repl in subs:
        out, count = pattern.subn(repl, out)
        if count:
            changed = True
    return out, changed


def redact(value: Any) -> tuple[Any, bool]:
    """Recursively redact strings nested in dicts and lists."""
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        changed = False
        for key, item in value.items():
            new_item, item_changed = redact(item)
            if item_changed:
                changed = True
            redacted[key] = new_item
        return redacted, changed
    if isinstance(value, (list, tuple)):
        redacted_items: list[Any] = []
        changed = False
        for item in value:
            new_item, item_changed = redact(item)
            if item_changed:
                changed = True
            redacted_items.append(new_item)
        return tuple(redacted_items) if isinstance(value, tuple) else redacted_items, changed
    return value, False
