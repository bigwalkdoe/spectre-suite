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

# Test 4: no inline event handlers (CSP script-src 'self' blocks them)
echo "Test 4: index.html has no CSP-blocked inline event handlers"
if grep -nE ' on(click|change|input|submit|keydown|keyup|load|error)=' "$PROJECT_ROOT/web-dashboard/index.html"; then
    fail "index.html contains inline event handlers that CSP 'script-src self' blocks"
else
    pass "index.html has no inline event handlers"
fi

# Test 5: help dialog close controls are wired with addEventListener
echo "Test 5: help dialog close controls are wired in dashboard.js"
if grep -q 'data-help-close' "$PROJECT_ROOT/web-dashboard/index.html" \
    && grep -q "data-help-close" "$JS_FILE"; then
    pass "help dialog close controls are bound via data-help-close"
else
    fail "help dialog close controls are not wired (expected data-help-close binding)"
fi

# Test 6: modal content is painted above the backdrop so the close button is clickable
echo "Test 6: modal content stacks above the backdrop"
CSS_FILE="$PROJECT_ROOT/web-dashboard/styles.css"
if ! grep -q "z-index: 1000" "$CSS_FILE"; then
    fail "styles.css has no backdrop z-index"
fi
if ! grep -q "z-index: 1001" "$CSS_FILE"; then
    fail "styles.css has no modal-content z-index above the backdrop"
fi
# The backdrop rule must come before the content rule so the content wins.
BACKDROP_IDX=$(grep -n "z-index: 1000" "$CSS_FILE" | head -1 | cut -d: -f1)
CONTENT_IDX=$(grep -n "z-index: 1001" "$CSS_FILE" | head -1 | cut -d: -f1)
if [ "$BACKDROP_IDX" -lt "$CONTENT_IDX" ]; then
    pass "modal content z-index follows the backdrop z-index"
else
    fail "backdrop z-index is not painted beneath the modal content"
fi
if grep -q "pointer-events: none" <(sed -n '/\.modal-backdrop {/,/^}/p' "$CSS_FILE"); then
    fail "modal-backdrop uses pointer-events: none (would break backdrop click-to-close)"
fi

echo "ALL KEYBOARD SHORTCUT TESTS PASSED"
