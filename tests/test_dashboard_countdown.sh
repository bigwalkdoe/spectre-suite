#!/bin/bash
# Tests for dashboard auto-refresh countdown timer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

# Test 1: index.html contains countdown element with id="refreshCountdown"
echo "Test 1: index.html contains #refreshCountdown element"
if grep -q 'id="refreshCountdown"' "$PROJECT_ROOT/web-dashboard/index.html"; then
    pass "index.html contains #refreshCountdown element"
else
    fail "index.html missing #refreshCountdown element"
fi

# Test 2: dashboard.js contains countdown functions
echo "Test 2: dashboard.js contains countdown functions"
JS_FILE="$PROJECT_ROOT/web-dashboard/dashboard.js"
if grep -q "function startRefreshCountdown" "$JS_FILE"; then
    pass "dashboard.js contains startRefreshCountdown()"
else
    fail "dashboard.js missing startRefreshCountdown()"
fi
if grep -q "function stopRefreshCountdown" "$JS_FILE"; then
    pass "dashboard.js contains stopRefreshCountdown()"
else
    fail "dashboard.js missing stopRefreshCountdown()"
fi
if grep -q "function updateCountdown" "$JS_FILE"; then
    pass "dashboard.js contains updateCountdown()"
else
    fail "dashboard.js missing updateCountdown()"
fi

# Test 3: styles.css contains countdown styles
echo "Test 3: styles.css contains countdown styles"
CSS_FILE="$PROJECT_ROOT/web-dashboard/styles.css"
if grep -q "\.refresh-countdown" "$CSS_FILE"; then
    pass "styles.css contains .refresh-countdown styles"
else
    fail "styles.css missing .refresh-countdown styles"
fi

echo "ALL COUNTDOWN TESTS PASSED"
