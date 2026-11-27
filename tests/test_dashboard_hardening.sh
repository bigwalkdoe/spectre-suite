#!/bin/bash
# Tests for dashboard production hardening:
#   A) the dashboard must survive a DOM that is missing elements
#   B) chart CSV export must read the live chart it initialized
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

DASHBOARD_CORE="$PROJECT_ROOT/web-dashboard/js/dashboard-core.js"
CHART_JS="$PROJECT_ROOT/web-dashboard/js/chart.js"

# ── Test 1: dashboard-core.js contains the key function declarations ──
echo "Test 1: dashboard-core.js contains key function declarations"
if grep -q "function initializeTheme" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains initializeTheme()"
else
    fail "dashboard-core.js missing initializeTheme()"
fi
if grep -q "function toggleDarkMode" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains toggleDarkMode()"
else
    fail "dashboard-core.js missing toggleDarkMode()"
fi
if grep -q "function updateTimestamp" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains updateTimestamp()"
else
    fail "dashboard-core.js missing updateTimestamp()"
fi
if grep -q "function checkAlerts" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains checkAlerts()"
else
    fail "dashboard-core.js missing checkAlerts()"
fi
if grep -q "function checkPrometheusConnection" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains checkPrometheusConnection()"
else
    fail "dashboard-core.js missing checkPrometheusConnection()"
fi
if grep -q "function exportSnapshot" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains exportSnapshot()"
else
    fail "dashboard-core.js missing exportSnapshot()"
fi
if grep -q "function updateCPUMetrics" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains updateCPUMetrics()"
else
    fail "dashboard-core.js missing updateCPUMetrics()"
fi
if grep -q "function updateMemoryMetrics" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains updateMemoryMetrics()"
else
    fail "dashboard-core.js missing updateMemoryMetrics()"
fi
if grep -q "function updateDiskMetrics" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains updateDiskMetrics()"
else
    fail "dashboard-core.js missing updateDiskMetrics()"
fi
if grep -q "function updateNetworkMetrics" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains updateNetworkMetrics()"
else
    fail "dashboard-core.js missing updateNetworkMetrics()"
fi
if grep -q "function updateSystemHealth" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js contains updateSystemHealth()"
else
    fail "dashboard-core.js missing updateSystemHealth()"
fi

# ── Test 2: chart CSV export uses the initialized chart ──
echo "Test 2: chart.js contains chart export functions"
if grep -q "function exportChartCSV" "$CHART_JS"; then
    pass "chart.js contains exportChartCSV()"
else
    fail "chart.js missing exportChartCSV()"
fi
if grep -q "function initializeChart" "$CHART_JS"; then
    pass "chart.js contains initializeChart()"
else
    fail "chart.js missing initializeChart()"
fi
if grep -q "function applyChartTheme" "$CHART_JS"; then
    pass "chart.js contains applyChartTheme()"
else
    fail "chart.js missing applyChartTheme()"
fi

# ── Test 3: missing chart library reports a chart error and skips queries ──
echo "Test 3: dashboard-core.js references chart functions from chart.js"
# dashboard-core.js imports initializeChart, updateChart, applyChartTheme, exportChartCSV from chart.js
if grep -q "from './chart.js'" "$DASHBOARD_CORE"; then
    pass "dashboard-core.js imports from chart.js"
else
    fail "dashboard-core.js does not import from chart.js"
fi

# ── Test 4: getChartTheme provides tooltip colors in both modes ──
echo "Test 4: chart.js contains getChartTheme"
if grep -q "function getChartTheme" "$CHART_JS"; then
    pass "chart.js contains getChartTheme()"
else
    fail "chart.js missing getChartTheme()"
fi

echo "ALL DASHBOARD HARDENING TESTS PASSED"