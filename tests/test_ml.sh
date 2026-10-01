#!/bin/bash
# Test ML anomaly detection + fix engine logic
# Runs the Python unit tests in tests/test_ml.py

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ML_DIR="$PROJECT_ROOT/scripts/ml-anomaly"

echo "Running ML unit tests..."
echo "=========================================="

# Interpreter selection.
#
# This looked for a venv at scripts/ml-anomaly/venv/bin/python, which nothing in
# this repository ever creates, so it always fell through to whatever python3 was
# on PATH. That only works by accident: CI pip-installs into the system
# interpreter first, so the fallback finds pandas. On this host system python3
# has no pandas, and the suite failed with a bare ModuleNotFoundError from deep
# inside a test that looked like a code regression rather than a missing dep.
#
# Order is now explicit: ML_PYTHON, then any venv that actually exists, then
# the system interpreter. And the chosen interpreter is checked for the
# dependencies before the tests run, so a gap is named with its fix instead of
# surfacing as a stack trace.
PY=""
for candidate in "${ML_PYTHON:-}" "$ML_DIR/venv/bin/python" "$PROJECT_ROOT/.venv/bin/python"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        PY="$candidate"
        break
    fi
done
[ -n "$PY" ] || PY="$(command -v python3)"

echo "Python interpreter: $PY"

# Named-PY heredoc, so the marker cannot be confused with one nested in a patch.
missing_deps=$("$PY" - <<'DEPS' 2>/dev/null
import importlib
missing = []
for m in ("numpy", "sklearn", "pandas", "requests"):
    try:
        importlib.import_module(m)
    except Exception:
        missing.append(m)
print(" ".join(missing))
DEPS
)
if [ -n "$missing_deps" ]; then
    echo "ML Unit Tests: FAILED"
    echo "  missing Python dependencies in $PY: $missing_deps"
    echo "  install with: $PY -m pip install -r $PROJECT_ROOT/scripts/ml-anomaly/requirements.txt"
    echo "  or select a prepared interpreter: ML_PYTHON=/path/to/python"
    echo "=========================================="
    exit 1
fi

if "$PY" -m pytest "$SCRIPT_DIR/test_ml.py" -q 2>/dev/null; then
    echo "ML tests passed via pytest"
    exit 0
fi

# Fallback to plain unittest
"$PY" -m unittest "$SCRIPT_DIR/test_ml.py" -v
rc=$?
echo "=========================================="
if [ "$rc" -eq 0 ]; then
    echo "ML Unit Tests: PASSED"
else
    echo "ML Unit Tests: FAILED"
fi
exit $rc
