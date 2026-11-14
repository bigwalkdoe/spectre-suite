#!/bin/bash
# Tests for dashboard CSV export functionality.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

# Test 1: index.html contains chart export CSV button
echo "Test 1: index.html contains chart export CSV button"
if grep -q 'id="chartExportCsv"' "$PROJECT_ROOT/web-dashboard/index.html"; then
    pass "index.html contains #chartExportCsv button"
else
    fail "index.html missing #chartExportCsv button"
fi

# Test 2: dashboard.js contains exportChartCSV function
echo "Test 2: dashboard.js contains exportChartCSV function"
JS_FILE="$PROJECT_ROOT/web-dashboard/dashboard.js"
if grep -q "function exportChartCSV" "$JS_FILE"; then
    pass "dashboard.js contains exportChartCSV()"
else
    fail "dashboard.js missing exportChartCSV()"
fi

echo "ALL CSV EXPORT TESTS PASSED"
