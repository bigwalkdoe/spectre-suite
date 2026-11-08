"""Static audit: actions must resolve SPECTRE/PROJECT/REPO root at the correct depth.

Regression for the backup failure where `spectre/actions/<group>/*.sh` used
`$SCRIPT_DIR/../..`, resolving to the `spectre/` package dir instead of the
repository root (breaking compose project derivation and repo-relative paths).
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ACTIONS = ROOT / "spectre" / "actions"
PAT = re.compile(r'\$SCRIPT_DIR/((?:\.\./)+)\s*&&\s*pwd')


def test_script_dir_repo_root_depth_matches_action_location():
    issues = []
    for path in sorted(ACTIONS.rglob("*.sh")):
        rel = path.relative_to(ROOT)
        under = rel.parts[2:]  # after spectre/actions
        if not under:
            continue
        file_depth = max(len(under) - 1, 0)
        expected = "../" * (file_depth + 2)
        expected = expected.rstrip("/")
        text = path.read_text(errors="replace")
        for m in PAT.finditer(text):
            got = m.group(1).rstrip("/")
            if got != expected:
                issues.append(f"{rel}: got {got}, expected {expected}")
    assert issues == [], "SCRIPT_DIR repo-root depth inconsistencies:\n" + "\n".join(issues)
