#!/bin/bash
# Tests for dashboard form-control touch scrolling (mobile UX).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CSS_FILE="$PROJECT_ROOT/web-dashboard/styles.css"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

echo "Test 1: form controls contain their own scroll gesture"
node - "$CSS_FILE" <<'NODE'
const fs = require('fs');
const css = fs.readFileSync(process.argv[2], 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((m) => ({
    selectors: m[1].split(',').map((s) => s.trim()),
    decls: m[2],
}));
function hasProp(selector, prop) {
    const re = new RegExp(`(^|[;\\s])${prop.replace(/[-]/g, '\\-')}\\s*:`);
    return rules.some((r) => r.selectors.includes(selector) && re.test(r.decls));
}
const controls = ['.refresh-interval-select', '.report-type-select', '.report-range-select', '.container-filter-input'];
let bad = 0;
for (const sel of controls) {
    for (const prop of ['overscroll-behavior', '-webkit-overflow-scrolling']) {
        if (!hasProp(sel, prop)) {
            console.error(`missing ${prop} on ${sel}`);
            bad++;
        }
    }
}
process.exit(bad === 0 ? 0 : 1);
NODE
if [ $? -eq 0 ]; then pass "all form controls set overscroll-behavior and -webkit-overflow-scrolling"; else fail "form controls missing touch-scroll containment"; fi

echo "Test 2: buttons use touch-action: manipulation"
node - "$CSS_FILE" <<'NODE'
const fs = require('fs');
const css = fs.readFileSync(process.argv[2], 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map((m) => ({
    selectors: m[1].split(',').map((s) => s.trim()),
    decls: m[2],
}));
const ok = rules.some((r) => (r.selectors.includes('.btn') || r.selectors.includes('button')) && /touch-action\s*:\s*manipulation/.test(r.decls));
process.exit(ok ? 0 : 1);
NODE
if [ $? -eq 0 ]; then pass "buttons set touch-action: manipulation"; else fail "no touch-action: manipulation rule for buttons"; fi

echo "ALL FORM SCROLLING TESTS PASSED"
