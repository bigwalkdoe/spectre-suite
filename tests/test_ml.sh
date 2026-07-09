#!/bin/bash
# Test ML anomaly detection + fix engine logic
# Runs the Python unit tests in tests/test_ml.py

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ML_DIR="$PROJECT_ROOT/scripts/ml-anomaly"

echo "Running ML unit tests..."
echo "=========================================="

# Use a venv if present, else system python3
if [ -x "$ML_DIR/venv/bin/python" ]; then
    PY="$ML_DIR/venv/bin/python"
else
    PY="$(command -v python3)"
fi

# Ensure deps are available (don't fail hard if offline)
"$PY" - <<'PY' 2>/dev/null || true
import importlib
for m in ("numpy", "sklearn", "pandas", "requests"):
    try:
        importlib.import_module(m)
    except Exception:
        print(f"WARN: {m} not installed; install via scripts/ml-anomaly/setup_ml_anomaly.sh")
PY

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
