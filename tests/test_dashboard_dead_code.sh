#!/bin/bash
# Tests for dashboard dead code / stale DOM references.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/web-dashboard"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

echo "Test 1: no reference to the removed #securityExporterStatus element"
if grep -q "securityExporterStatus" "$WEB_DIR/dashboard.js" "$WEB_DIR/index.html"; then
    fail "#securityExporterStatus is still referenced but never rendered"
else
    pass "#securityExporterStatus is gone from dashboard.js and index.html"
fi

echo "Test 2: lastExporterStatus has no unused 'security' key"
if grep -qE "security:\s*spectreUp" "$WEB_DIR/dashboard.js"; then
    fail "lastExporterStatus still carries an unread 'security' key"
else
    pass "lastExporterStatus has no unread 'security' key"
fi

echo "Test 3: every getElementById() id exists in index.html"
if node - "$WEB_DIR/index.html" "$WEB_DIR/dashboard.js" "$WEB_DIR/reports.js" <<'NODE'
const fs = require('fs');
const [htmlPath, ...jsPaths] = process.argv.slice(2);
const html = fs.readFileSync(htmlPath, 'utf8');
const ids = new Set([...html.matchAll(/\bid=["']([^"']+)["']/g)].map((m) => m[1]));
let missing = 0;
for (const file of jsPaths) {
    const src = fs.readFileSync(file, 'utf8');
    const refs = [...new Set([...src.matchAll(/getElementById\(["']([^"']+)["']\)/g)].map((m) => m[1]))];
    for (const id of refs) {
        if (!ids.has(id)) {
            console.error(`${file}: getElementById('${id}') has no matching element`);
            missing++;
        }
    }
}
process.exit(missing === 0 ? 0 : 1);
NODE
then
    pass "all DOM ids referenced by dashboard.js/reports.js exist"
else
    fail "dashboard.js/reports.js reference ids that index.html does not render"
fi

echo "ALL DASHBOARD DEAD-CODE TESTS PASSED"
