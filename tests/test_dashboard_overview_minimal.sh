#!/bin/bash
# Overview = at-a-glance minimal: only .quick-stats on `overview`.
# Other cards stay on their sidepanel pages (data-show-pages without `overview`).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HTML="$PROJECT_ROOT/web-dashboard/index.html"

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; exit 1; }

node - "$HTML" <<'NODE'
const fs = require('fs');
const html = fs.readFileSync(process.argv[2], 'utf8');
const errs = [];

function pagesOf(predicate) {
    // collect data-show-pages for elements matching a simple class/id needle
    const re = /<([a-z0-9]+)\b([^>]*)>/gi;
    let m; const out = [];
    while ((m = re.exec(html))) {
        const attrs = m[2];
        if (!predicate(attrs)) continue;
        const d = attrs.match(/data-show-pages="([^"]*)"/);
        out.push(d ? d[1].split(/\s+/).filter(Boolean) : []);
    }
    return out;
}
const has = (attrs, needle) => attrs.includes(needle);

// .quick-stats stays on overview (at-a-glance key metrics)
const qs = pagesOf(a => has(a, 'class="quick-stats"') || /\bclass="[^"]*\bquick-stats\b[^"]*"/.test(a));
if (qs.length === 0) errs.push('.quick-stats not found');
if (!qs.some(p => p.includes('overview'))) errs.push('.quick-stats lost `overview`');

// these cards must NOT render on overview; keep their sidepanel page
const offOverview = [
    ['alertsCard','alerts'],
    ['securityCard','security'],
    ['healthCard','health'],
    ['backupCard','backup'],
    ['containersCard','containers'],
    ['chartCard','trends'],
    ['reportsCard','reports'],
    ['diagnosticsCard','diagnostics'],
    ['actionActivityCard', null],
];
for (const [id, side] of offOverview) {
    const re = new RegExp('<section\\b[^>]*\\bid="' + id + '"[^>]*>');
    const m = html.match(re);
    if (!m) { errs.push(id + ' not found'); continue; }
    const d = m[0].match(/data-show-pages="([^"]*)"/);
    const pages = d ? d[1].split(/\s+/).filter(Boolean) : [];
    if (pages.includes('overview')) errs.push(id + ' still renders on `overview`');
    if (side && !pages.includes(side)) errs.push(id + ' lost sidepanel page `' + side + '`');
}

if (errs.length) { console.error(errs.join('\n')); process.exit(1); }
NODE
pass "overview minimal: .quick-stats on overview; other cards on sidepanel pages"
