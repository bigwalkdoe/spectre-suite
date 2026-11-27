#!/bin/bash
# Structural IA test: #reportsCard must be a cell inside .dashboard-grid
# (not a top-level sibling before .quick-stats), preserving its data-* contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WEB_DIR="$PROJECT_ROOT/web-dashboard"

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; exit 1; }

if node - "$WEB_DIR/index.html" <<'NODE'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');

// 1. reportsCard keeps its id + data-show-pages contract
const cardMatch = html.match(/<section\b[^>]*\bid="reportsCard"[^>]*>/);
if (!cardMatch) { console.error('reportsCard section not found'); process.exit(1); }
if (!/\bdata-show-pages="reports"/.test(cardMatch[0])) { console.error('reportsCard lost data-show-pages="reports"'); process.exit(1); }

// 2. reportsCard is INSIDE .dashboard-grid: grid opens before it and a matching close exists after
const gridStart = html.indexOf('class="dashboard-grid"');
const cardStart = html.indexOf('id="reportsCard"');
if (gridStart === -1 || cardStart === -1 || gridStart > cardStart) { console.error('reportsCard is not inside .dashboard-grid'); process.exit(1); }
const gridRegion = html.slice(gridStart, html.indexOf('</main>', gridStart));
// crude balance check on sections within grid region
const opens = (gridRegion.match(/<section\b/g) || []).length;
const closes = (gridRegion.match(/<\/section>/g) || []).length;
if (opens !== closes) { console.error(`unbalanced sections in .dashboard-grid: ${opens} open vs ${closes} close`); process.exit(1); }
// card ends before grid ends
const gridEnd = html.lastIndexOf('</section>', html.indexOf('</main>', gridStart));
if (html.indexOf('id="reportsCard"', gridStart) > gridEnd) { console.error('reportsCard not balanced inside grid'); process.exit(1); }

// 3. required inner ids preserved
for (const id of ['reportType','reportRange','reportGenerate','reportChart','reportTable','reportEmpty','reportExportJson','reportExportCsv','reportExportStatus','reportChartBody']) {
    if (!html.includes('id="' + id + '"')) { console.error('missing inner id ' + id); process.exit(1); }
}
process.exit(0);
NODE
then
    pass "reportsCard is a balanced cell inside .dashboard-grid; data-show-pages + inner ids preserved"
else
    fail "reportsCard is not structurally inside .dashboard-grid or lost its data-* contract"
fi
