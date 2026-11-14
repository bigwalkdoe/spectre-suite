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

echo "Test 4: page cards are not nested inside zero-height page anchors"
if node - "$WEB_DIR/index.html" <<'NODE'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
// Each .page-anchor is a zero-height (height:0; overflow:hidden) scroll
// target for the hash router; it must stay empty. A card nested inside one is
// clipped to nothing and the page renders blank, so anchors may only contain
// whitespace before their closing </div>.
const anchors = [...html.matchAll(/<div\b[^>]*class=["'][^"']*\bpage-anchor\b[^"']*["'][^>]*>([\s\S]*?)<\/div>/g)];
let bad = 0;
for (const match of anchors) {
    if (match[1].trim() !== '') {
        console.error(`page-anchor contains markup and will clip its page: ${match[1].trim().slice(0, 60)}...`);
        bad++;
    }
}
if (anchors.length === 0) {
    console.error('no page-anchor elements found; the check cannot judge the layout');
    bad++;
}
process.exit(bad === 0 ? 0 : 1);
NODE
then
    pass "every page anchor is an empty scroll target"
else
    fail "a page card is nested inside a zero-height page anchor"
fi

echo "ALL DASHBOARD DEAD-CODE TESTS PASSED"
