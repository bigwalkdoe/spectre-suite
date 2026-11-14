#!/bin/bash
# Tests for dashboard keyboard shortcuts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

# Test 1: index.html contains keyboard help dialog
echo "Test 1: index.html contains keyboard help dialog"
if grep -q 'id="keyboardHelp"' "$PROJECT_ROOT/web-dashboard/index.html"; then
    pass "index.html contains #keyboardHelp element"
else
    fail "index.html missing #keyboardHelp element"
fi

# Test 2: dashboard.js contains keyboard shortcut functions
echo "Test 2: dashboard.js contains keyboard shortcut functions"
JS_FILE="$PROJECT_ROOT/web-dashboard/dashboard.js"
if grep -q "function handleKeyboard" "$JS_FILE"; then
    pass "dashboard.js contains handleKeyboard()"
else
    fail "dashboard.js missing handleKeyboard()"
fi
if grep -q "function showHelpDialog" "$JS_FILE"; then
    pass "dashboard.js contains showHelpDialog()"
else
    fail "dashboard.js missing showHelpDialog()"
fi
if grep -q "function hideHelpDialog" "$JS_FILE"; then
    pass "dashboard.js contains hideHelpDialog()"
else
    fail "dashboard.js missing hideHelpDialog()"
fi

# Test 3: styles.css contains keyboard help dialog styles
echo "Test 3: styles.css contains keyboard help dialog styles"
CSS_FILE="$PROJECT_ROOT/web-dashboard/styles.css"
if grep -q "#keyboardHelp" "$CSS_FILE"; then
    pass "styles.css contains #keyboardHelp styles"
else
    fail "styles.css missing #keyboardHelp styles"
fi

echo "ALL KEYBOARD SHORTCUT TESTS PASSED"
