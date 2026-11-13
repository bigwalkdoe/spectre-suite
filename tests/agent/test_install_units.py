"""Legacy contract tests (obsolete after consolidation).

The original tests pinned shipped `spectre-daemon.service`/`spectre-api.service` units
to a specific venv path and unit layout. Consolidation moved dispatch to
`spectre run` and host unit management is operator-specific; `install.sh` now
installs only `/usr/local/bin/spectre` and generates `spectre run`-based job
units (see `tests/test_install_units.sh`).
"""

import pytest

pytest.skip(
    "obsolete: consolidated installer/unit contract is covered by tests/test_install_units.sh",
    allow_module_level=True,
)
