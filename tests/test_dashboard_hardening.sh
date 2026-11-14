#!/bin/bash
# Tests for dashboard production hardening:
#   A) the dashboard must survive a DOM that is missing elements
#   B) chart CSV export must read the live chart it initialized
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
JS_FILE="$PROJECT_ROOT/web-dashboard/dashboard.js"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

echo "Test 1: dashboard.js survives missing DOM elements"
node - "$JS_FILE" <<'NODE'
const fs = require('fs');
const vm = require('vm');

function classList() {
    const set = new Set();
    return {
        add: (c) => set.add(c),
        remove: (c) => set.delete(c),
        contains: (c) => set.has(c),
        toggle: (c, force) => {
            if (force === undefined) {
                if (set.has(c)) { set.delete(c); return false; }
                set.add(c); return true;
            }
            if (force) set.add(c); else set.delete(c);
            return force;
        },
    };
}

function makeSandbox() {
    const clicks = [];
    const sandbox = {
        console: { log() {}, info() {}, warn() {}, error() {} },
        setTimeout: () => 0,
        clearTimeout: () => {},
        setInterval: () => 0,
        clearInterval: () => {},
        requestAnimationFrame: () => 0,
        localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
        sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
        location: { search: '', host: '', hostname: 'localhost', protocol: 'http:', hash: '' },
        navigator: { clipboard: { writeText: () => Promise.reject(new Error('denied')) } },
        CSS: { escape: (s) => s },
        fetch: () => Promise.reject(new Error('offline')),
        AbortController,
        URLSearchParams,
        Blob,
        URL: { createObjectURL: () => 'blob:stub', revokeObjectURL: () => {} },
        document: {
            hidden: false,
            documentElement: { classList: classList() },
            body: { dataset: {}, classList: classList(), appendChild() {} },
            addEventListener() {},
            removeEventListener() {},
            getElementById: () => null,
            querySelector: () => null,
            querySelectorAll: () => [],
            createElement: () => ({
                className: '', innerHTML: '', style: {}, dataset: {},
                setAttribute() {}, removeAttribute() {}, appendChild() {},
                querySelector: () => null, click() { clicks.push(this); }, remove() {},
            }),
        },
    };
    sandbox.window = sandbox;
    sandbox.globalThis = sandbox;
    sandbox.window.matchMedia = () => ({ matches: false, addEventListener() {}, addListener() {} });
    sandbox.window.addEventListener = () => {};
    return { sandbox, clicks };
}

const src = fs.readFileSync(process.argv[2], 'utf8');

(async () => {
    const { sandbox } = makeSandbox();
    const context = vm.createContext(sandbox);
    vm.runInContext(src, context, { filename: 'dashboard.js' });

    const failures = [];
    const check = async (name, fn) => {
        try { await fn(); } catch (err) { failures.push(`${name}: ${err && err.message}`); }
    };

    await check('initializeTheme', () => sandbox.initializeTheme());
    await check('toggleDarkMode', () => sandbox.toggleDarkMode());
    await check('updateTimestamp', () => sandbox.updateTimestamp());
    await check('initializeChart', () => sandbox.initializeChart());
    await check('applyChartTheme', () => sandbox.applyChartTheme());
    await check('updateCPUMetrics', () => sandbox.updateCPUMetrics(42));
    await check('updateMemoryMetrics', () => sandbox.updateMemoryMetrics(42));
    await check('updateDiskMetrics', () => sandbox.updateDiskMetrics(42));
    await check('updateNetworkMetrics', () => sandbox.updateNetworkMetrics(1, 2));
    await check('updateSystemHealth', () => sandbox.updateSystemHealth(1, 2, 3, 4));
    await check('updateBackupStatus', () => sandbox.updateBackupStatus(null, null, null, null, null, null, null, null, null, null, null));
    await check('updateSecurityStatus', () => sandbox.updateSecurityStatus(null, null, null, null, null, null, null, null, null, null));
    await check('updateDiagnostics', () => sandbox.updateDiagnostics());
    await check('renderAlerts', () => sandbox.renderAlerts());
    await check('updateContainerStatus', () => sandbox.updateContainerStatus());
    await check('checkAlerts', () => sandbox.checkAlerts());
    await check('checkPrometheusConnection', () => sandbox.checkPrometheusConnection());
    await check('exportSnapshot', () => sandbox.exportSnapshot());
    await check('exportChartCSV', () => sandbox.exportChartCSV());

    if (failures.length) {
        for (const f of failures) console.error(f);
        process.exit(1);
    }
})();
NODE
if [ $? -eq 0 ]; then pass "all entry points tolerate missing DOM elements"; else fail "dashboard throws when DOM elements are missing"; fi

echo "Test 2: chart CSV export uses the initialized chart"
node - "$JS_FILE" <<'NODE'
const fs = require('fs');
const vm = require('vm');

function classList() {
    const set = new Set();
    return {
        add: (c) => set.add(c), remove: (c) => set.delete(c), contains: (c) => set.has(c),
        toggle: (c, force) => { if (force === undefined) { if (set.has(c)) { set.delete(c); return false; } set.add(c); return true; } if (force) set.add(c); else set.delete(c); return force; },
    };
}

const clicks = [];
const charts = [];
let capturedBlob = null;
class ChartStub {
    constructor(ctx, config) {
        this.ctx = ctx;
        this.data = config.data;
        this.options = JSON.parse(JSON.stringify(config.options || {}));
        charts.push(this);
    }
    update() {}
    resize() {}
}

const sandbox = {
    console: { log() {}, info() {}, warn() {}, error() {} },
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {},
    requestAnimationFrame: () => 0,
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    location: { search: '', host: '', hostname: 'localhost', protocol: 'http:', hash: '' },
    navigator: { clipboard: { writeText: () => Promise.resolve() } },
    CSS: { escape: (s) => s },
    fetch: () => Promise.reject(new Error('offline')),
    AbortController, URLSearchParams, Blob,
    URL: { createObjectURL: (blob) => { capturedBlob = blob; return 'blob:stub'; }, revokeObjectURL: () => {} },
    Chart: ChartStub,
    document: {
        hidden: false,
        documentElement: { classList: classList() },
        body: { dataset: {}, classList: classList(), appendChild() {} },
        addEventListener() {}, removeEventListener() {},
        getElementById: (id) => {
            if (id === 'resourceChart') return { getContext: () => ({}) };
            return null;
        },
        querySelector: () => null,
        querySelectorAll: () => [],
        createElement: () => ({
            className: '', innerHTML: '', style: {}, dataset: {}, download: '', href: '',
            setAttribute() {}, removeAttribute() {}, appendChild() {},
            querySelector: () => null, click() { clicks.push(this); }, remove() {},
        }),
    },
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.window.matchMedia = () => ({ matches: false, addEventListener() {}, addListener() {} });
sandbox.window.addEventListener = () => {};

const src = fs.readFileSync(process.argv[2], 'utf8');
vm.runInContext(src, vm.createContext(sandbox), { filename: 'dashboard.js' });

function parseCsv(text) {
    const rows = [];
    let row = [];
    let field = '';
    let quoted = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (quoted) {
            if (c === '"') {
                if (text[i + 1] === '"') { field += '"'; i++; }
                else quoted = false;
            } else field += c;
        } else if (c === '"') {
            quoted = true;
        } else if (c === ',') {
            row.push(field); field = '';
        } else if (c === '\n') {
            row.push(field); rows.push(row); row = []; field = '';
        } else if (c !== '\r') {
            field += c;
        }
    }
    if (field.length || row.length) { row.push(field); rows.push(row); }
    return rows;
}

(async () => {
    sandbox.initializeChart();
    if (charts.length !== 1) {
        console.error(`expected one chart, got ${charts.length}`);
        process.exit(1);
    }
    const chart = charts[0];
    chart.data.labels = ['Nov 14, 10:00 AM', 'Nov 14, 10:01 AM'];
    chart.data.datasets[0].data = [41.5, 42.25];

    sandbox.exportChartCSV();
    if (clicks.length !== 1) {
        console.error('exportChartCSV() did not download a CSV file');
        process.exit(1);
    }
    if (!String(clicks[0].download).endsWith('.csv')) {
        console.error(`unexpected download name: ${clicks[0].download}`);
        process.exit(1);
    }
    if (!capturedBlob) {
        console.error('exportChartCSV() did not produce a Blob');
        process.exit(1);
    }

    const rows = parseCsv(await capturedBlob.text());
    const expectedColumns = 1 + chart.data.datasets.length;
    if (rows[0].length !== expectedColumns) {
        console.error(`header has ${rows[0].length} fields, expected ${expectedColumns}: ${rows[0].join(' | ')}`);
        process.exit(1);
    }
    if (rows[0][expectedColumns - 1] !== 'Network I/O (RX+TX, 5m rate)') {
        console.error(`comma-bearing label was split: ${rows[0].join(' | ')}`);
        process.exit(1);
    }
    rows.forEach((row, i) => {
        if (row.length !== expectedColumns) {
            console.error(`row ${i} has ${row.length} fields, expected ${expectedColumns}: ${row.join(' | ')}`);
            process.exit(1);
        }
    });
    if (rows[1][0] !== 'Nov 14, 10:00 AM') {
        console.error(`comma-bearing timestamp was split: ${rows[1][0]}`);
        process.exit(1);
    }
})();
NODE
if [ $? -eq 0 ]; then pass "exportChartCSV downloads well-formed CSV"; else fail "exportChartCSV writes a malformed CSV"; fi

echo "Test 3: missing chart library reports a chart error and skips queries"
node - "$JS_FILE" <<'NODE'
const fs = require('fs');
const vm = require('vm');

function classList() {
    const set = new Set();
    return {
        add: (c) => set.add(c), remove: (c) => set.delete(c), contains: (c) => set.has(c),
        toggle: (c, force) => { if (force === undefined) { if (set.has(c)) { set.delete(c); return false; } set.add(c); return true; } if (force) set.add(c); else set.delete(c); return force; },
    };
}

const appended = [];
const chartCard = {
    classList: classList(),
    setAttribute() {},
    querySelector: () => null,
    appendChild: (el) => { appended.push(el); },
};
let fetches = 0;

const sandbox = {
    console: { log() {}, info() {}, warn() {}, error() {} },
    setTimeout: () => 0, clearTimeout: () => {}, setInterval: () => 0, clearInterval: () => {},
    requestAnimationFrame: () => 0,
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    sessionStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    location: { search: '', host: '', hostname: 'localhost', protocol: 'http:', hash: '' },
    navigator: { clipboard: { writeText: () => Promise.resolve() } },
    CSS: { escape: (s) => s },
    fetch: () => { fetches++; return Promise.reject(new Error('offline')); },
    AbortController, URLSearchParams, Blob,
    URL: { createObjectURL: () => 'blob:stub', revokeObjectURL: () => {} },
    document: {
        hidden: false,
        documentElement: { classList: classList() },
        body: { dataset: {}, classList: classList(), appendChild() {} },
        addEventListener() {}, removeEventListener() {},
        getElementById: (id) => {
            if (id === 'resourceChart') return { getContext: () => ({}) };
            if (id === 'chartCard') return chartCard;
            return null;
        },
        querySelector: () => null,
        querySelectorAll: () => [],
        createElement: () => ({
            className: '', innerHTML: '', style: {}, dataset: {},
            setAttribute() {}, removeAttribute() {}, appendChild() {},
            querySelector: () => null, click() {}, remove() {},
        }),
    },
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.window.matchMedia = () => ({ matches: false, addEventListener() {}, addListener() {} });
sandbox.window.addEventListener = () => {};

const src = fs.readFileSync(process.argv[2], 'utf8');
vm.runInContext(src, vm.createContext(sandbox), { filename: 'dashboard.js' });

(async () => {
    // No global Chart: the vendored chart bundle failed to load.
    sandbox.initializeChart();
    if (appended.length !== 1) {
        console.error('initializeChart() did not report a chart error');
        process.exit(1);
    }
    const message = String(appended[0].innerHTML || '');
    if (!/chart/i.test(message) || !/unavailable|library/i.test(message)) {
        console.error(`unexpected chart error message: ${message}`);
        process.exit(1);
    }

    const before = fetches;
    await sandbox.updateChart('1h');
    if (fetches !== before) {
        console.error('updateChart() queried Prometheus even though no chart exists');
        process.exit(1);
    }
})();
NODE
if [ $? -eq 0 ]; then pass "chart library failure degrades without queries or TypeErrors"; else fail "missing chart library causes queries or no error message"; fi

echo "ALL DASHBOARD HARDENING TESTS PASSED"
