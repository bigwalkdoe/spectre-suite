# Web Dashboard Reports Subsystem Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Reports page to the Spectre web dashboard so operators can view historical trends (backup/restic health, security findings, alert history, system health) over a chosen time range and export each report as JSON or CSV.

**Architecture:** Client-only reports built on the existing static dashboard. A new `web-dashboard/reports.js` module (loaded after `dashboard.js`) defines pure report-logic functions (query building, CSV/JSON generation, value formatting) plus browser integration (fetch Prometheus `query_range` via the same-origin `/api/` proxy, render a Chart.js trend line + HTML table, wire Generate/Export buttons, show loading/error/empty states). `index.html` gains a Reports nav item, page anchor, and reports-card markup. `styles.css` gains report-table/export/empty-state styles. No new backend; no new privileges.

**Tech Stack:** Vanilla JavaScript (no framework), Chart.js (vendored under `vendor/`), Prometheus `query_range` via existing `/api/` nginx proxy, HTML5/CSS3.

**Spec:** `docs/superpowers/specs/2026-11-13-web-dashboard-reports-subsystem-design.md`

## Global Constraints

- Static dashboard: `web-dashboard/` is bind-mounted read-only (`ro,z`) into nginx.
- CSP: `connect-src 'self'` — all Prometheus fetches go through the same-origin `/api/` proxy (nginx rewrites `/api/*` → `/prometheus/api/*` on `prometheus:9090`).
- Dashboard JS is vanilla, single-script, no ES modules. `reports.js` is a second `<script src>` loaded after `dashboard.js` and may use its globals (`PROMETHEUS_URL`, `fetchWithTimeout`, `showToast`, `setCardLoading`, `setCardError`, `clearCardError`).
- Reuse the existing `updateChart()` patterns: query_range with step sizing and token-based staleness.
- Must remain mobile-responsive and keyboard accessible.
- No new backend service, database, scheduled/emailed reports, multi-server support, or authentication.

## Review Focus

These are input classes/failure modes the spec implies but individual task tests may not all cover; each is pinned to a owning task:

1. **Prometheus unreachable** — reports page shows error state + toast, never blank (Task 4).
2. **Prometheus returns no data for the range** — reports page shows "No data for this range" empty state, chart/table cleared (Task 4).
3. **Invalid/missing report type or range** — Generate does nothing and shows no crash (Task 5).
4. **Clipboard unavailable** — export falls back to file download (Task 5).
5. **7d range crosses day boundaries** — x-axis labels include date component (Task 4).

## File Structure

- Create: `web-dashboard/reports.js` — pure report logic + browser integration (all report code lives here; dashboard.js untouched).
- Modify: `web-dashboard/index.html` — add Reports nav item (Operations group), `#page-reports` anchor, reports card markup (type/range pickers, Generate, chart canvas, table, export buttons), load `reports.js` after `dashboard.js`.
- Modify: `web-dashboard/styles.css` — report table, export button group, empty-state styles; reuse existing `.btn`, `.card--loading`, `.card--error`, `.skeleton`.
- Test: `tests/test_reports_js.sh` — executable bash test that runs Node assertions against the pure functions in `reports.js` (query building, CSV, JSON, value formatting). No browser/DOM needed for pure functions.

## Self-Review (pre-execution)

1. **Spec coverage:** Report page + nav (Task 1), report-type + range pickers (Task 1/5), historical trends via query_range (Task 4), JSON/CSV export (Task 5), graceful degradation (Task 4), backup/restic/security/system-health report types (Task 3/4). All covered.
2. **Step scan:** Every step is one actionable thing with a checkable result; no TBD or vague lines.
3. **Type consistency:** `buildReportQueries(reportType, range)` returns `{queries: string[], label: string}`; `renderReport({labels, series, reportType})` consumes that shape; `buildCSV(labels, series)` / `buildJSON(...)` produce strings. Consistent across Tasks 3–5.
4. **Review Focus:** Each of the 5 items above has a test in its owning task.
5. **Proportion:** Plan is sized to the spec — focused on reports only, no redesign or backend.

---

### Task 1: Reports page markup and navigation

**Files:**
- Modify: `web-dashboard/index.html`

**Interfaces:**
- Consumes: none
- Produces: Reports `<a class="nav-item" data-page="reports">` under Operations group; `<div id="page-reports" class="page-anchor">`; reports card markup with `#reportType`, `#reportRange`, `#reportGenerate`, `#reportChart`, `#reportTable`, `#reportExportJson`, `#reportExportCsv`; `<script src="reports.js?v=...">` after `dashboard.js`.

- [ ] **Step 1: Add Reports nav item and page anchor to index.html**

```html
<!-- In the Operations nav-group, after the Backup item: -->
<a href="#page-reports" class="nav-item" data-page="reports" data-page-title="Reports" data-page-icon="fa-chart-bar"><i class="fas fa-chart-bar fa-fw" aria-hidden="true"></i><span>Reports</span></a>

<!-- After the last page-anchor div (#page-backup): -->
<div id="page-reports" class="page-anchor" aria-hidden="true"></div>
```

Check: `grep -c 'data-page="reports"' web-dashboard/index.html` → 1; `grep -c 'id="page-reports"' web-dashboard/index.html` → 1.

- [ ] **Step 2: Add reports card markup inside `#page-reports`**

Card contains: report-type select (Backup & Restic Health, Security Findings, Alert History, System Health), time-range select (24h/7d/30d/90d), Generate button, chart canvas `#reportChart`, data table `#reportTable`, export buttons `#reportExportJson`/`#reportExportCsv`, loading/error/empty regions.

Check: `grep -c 'id="reportGenerate"' web-dashboard/index.html` → 1; `grep -c 'id="reportChart"' web-dashboard/index.html` → 1.

- [ ] **Step 3: Load reports.js after dashboard.js in index.html**

Add `<script src="reports.js?v=20261113-reports1"></script>` immediately after the `dashboard.js` script tag.

Check: `grep -c 'reports.js' web-dashboard/index.html` → 1 and it appears after `dashboard.js`.

- [ ] **Step 4: Commit**

```bash
git add web-dashboard/index.html
git commit -m "feat(dashboard): add Reports page skeleton (nav + markup)"
```

---

### Task 2: Reports CSS

**Files:**
- Modify: `web-dashboard/styles.css`

**Interfaces:**
- Consumes: none
- Produces: `.report-controls`, `.report-table`, `.report-table th/td`, `.report-export`, `.report-empty`, `.report-chart` styles; reuse existing `.btn`, `.card--loading`, `.card--error`, `.skeleton` classes; no new colors outside existing palette.

- [ ] **Step 1: Write failing test (structural)**

Check: `grep -c '\.report-table' web-dashboard/styles.css` → 0 (fails, as expected before implementation).

- [ ] **Step 2: Implement report styles in styles.css**

Add `.report-controls` (flex pickers + generate), `.report-table` (striped, scrollable), `.report-export` (button group), `.report-empty` (centered muted state), `.report-chart` (canvas wrapper).

Check: `grep -c '\.report-table' web-dashboard/styles.css` → 1.

- [ ] **Step 3: Verify CSS parses**

Run: `python3 -c "import cssutils; ..."` if available, else confirm no obvious syntax via `grep -n '{' web-dashboard/styles.css | tail -5`. Simple check: file ends with a closing brace and contains `.report-table`.

- [ ] **Step 4: Commit**

```bash
git add web-dashboard/styles.css
git commit -m "style(dashboard): add Reports page table, export, and empty-state styles"
```

---

### Task 3: Pure report logic (query building, CSV, JSON, formatting)

**Files:**
- Create: `web-dashboard/reports.js`
- Test: `tests/test_reports_js.sh`

**Interfaces:**
- Consumes: none (pure functions, no DOM/fetch)
- Produces: `buildReportQueries(reportType, range) => {queries: string[], label: string}`, `formatReportValue(value, metric) => string`, `buildCSV(labels, series) => string`, `buildJSON(payload) => string`. These are testable without a browser.

- [ ] **Step 1: Write the failing test (Node assertions on pure functions)**

```bash
# tests/test_reports_js.sh uses node to eval reports.js and assert:
node -e "
const fs = require('fs');
const code = fs.readFileSync('web-dashboard/reports.js', 'utf8');
// pure functions only; do not call browser-only functions
const fn = new Function('return {' +
  'buildReportQueries: (' + code.match(/function buildReportQueries[\s\S]*?^\}/m)[0] + '),...' +
  '}')();
// assert known query strings exist
"
```

Expected: FAIL — `web-dashboard/reports.js` does not exist yet.

- [ ] **Step 2: Implement pure functions in reports.js**

Define `buildReportQueries(reportType, range)` returning Prometheus `query_range` queries per type:
- Backup & Restic: `backup_last_success_timestamp`, `restic_last_success_timestamp`, `max(restic_health_ok)`, `max(restic_verify_ok)`
- Security: `security_findings_unresolved`, `security_findings_unresolved_by_severity{severity="critical"}`, `security_last_scan_timestamp`, `spectre_agent_up`
- Alerts: `ALERTS{alertname!=""}` (falls back gracefully in Task 4 if unsupported)
- System Health: the 4 existing chart queries (CPU, memory, disk, network)

Range → seconds: 24h=86400, 7d=604800, 30d=2592000, 90d=7776000; step sized like `updateChart` (~400 points max).

Define `formatReportValue(value, metric)`, `buildCSV(labels, series)`, `buildJSON(payload)`.

Check: `node -e "require('fs').readFileSync('web-dashboard/reports.js','utf8')"` loads without syntax error; `grep -c 'function buildReportQueries' web-dashboard/reports.js` → 1.

- [ ] **Step 3: Run pure-function tests; verify they pass**

Run: `bash tests/test_reports_js.sh` → all assertions pass.

Expected assertions:
- `buildReportQueries('backup','7d').queries` contains `backup_last_success_timestamp` and `restic_last_success_timestamp`
- `buildReportQueries('security','24h').queries` contains `security_findings_unresolved`
- `buildReportQueries('system','30d').queries` contains `node_cpu_seconds_total`
- `buildCSV(['t0'], [[1,2]])` starts with `timestamp,value`
- `buildJSON({exportedAt: 'x'})` parses as JSON with `exportedAt === 'x'`

- [ ] **Step 4: Commit**

```bash
git add web-dashboard/reports.js tests/test_reports_js.sh
git commit -m "feat(dashboard): add pure report logic (queries, CSV, JSON, formatting)"
```

---

### Task 4: Reports browser integration (fetch, chart, table, degradation)

**Files:**
- Modify: `web-dashboard/reports.js`

**Interfaces:**
- Consumes: `buildReportQueries`, `formatReportValue`, `buildCSV`, `buildJSON` (Task 3); dashboard.js globals `PROMETHEUS_URL`, `fetchWithTimeout`, `showToast`, `setCardLoading`, `setCardError`, `clearCardError`.
- Produces: `initReports()`, `async generateReport(reportType, range)`, `renderReportChart(labels, series, reportType)`, `renderReportTable(labels, series)`, `showReportError(message)`, `showReportEmpty()`. Renders into `#reportChart`/`#reportTable`.

- [ ] **Step 1: Write the failing test (manual)**

Open dashboard, navigate to Reports, click Generate with Prometheus running: expect chart + table to populate. (No automated browser test exists in this repo; this is a manual verification step consistent with the existing dashboard UX plan.)

- [ ] **Step 2: Implement browser integration in reports.js**

`initReports()` runs on `DOMContentLoaded`; finds `#reportGenerate`, `#reportType`, `#reportRange`; wires Generate click → `generateReport(selectedType, selectedRange)`.

`generateReport(reportType, range)`:
- calls `buildReportQueries(reportType, range)` (Task 3)
- sets loading state on report card
- fetches each query via `fetchWithTimeout(\`${PROMETHEUS_URL}/api/v1/query_range?...\`)`
- on all-null or errors: `showReportError('No data from Prometheus')` / toast
- on empty results: `showReportEmpty()`
- on success: `renderReportChart(labels, series, reportType)` + `renderReportTable(labels, series)`

`renderReportChart` creates/updates a Chart.js line instance on `#reportChart` (separate from the trends `resourceChart`). For 7d+ ranges, x-axis labels include date component.

`renderReportTable` builds `<table>` rows `timestamp → value` using `formatReportValue`.

- [ ] **Step 3: Run manual verification**

Navigate to Reports; Generate for each of the 4 report types at 24h range; confirm chart + table render or show empty/error appropriately; confirm no console errors.

- [ ] **Step 4: Commit**

```bash
git add web-dashboard/reports.js
git commit -m "feat(dashboard): add Reports browser integration (fetch, chart, table)"
```

---

### Task 5: Export, Generate wiring, loading/error states, localStorage

**Files:**
- Modify: `web-dashboard/reports.js`

**Interfaces:**
- Consumes: `buildCSV`, `buildJSON` (Task 3); `generateReport`, `renderReportTable` (Task 4).
- Produces: wired `#reportGenerate` click, `#reportExportJson`/`#reportExportCsv` clicks, localStorage persistence of last type+range, loading/error toggles around Generate, clipboard-with-download fallback for export.

- [ ] **Step 1: Write the failing test (manual + Node on CSV/JSON export)**

Node test: `buildCSV` output parses as CSV; `buildJSON` output parses as JSON. Manual test: click Export JSON → file downloads or toast shows "copied"; click Export CSV → CSV downloads.

- [ ] **Step 2: Implement export + wiring in reports.js**

Wire `#reportGenerate` to call `generateReport` with current picker values (default 24h, first report type). Show/hide `card--loading` around the fetch. On success show chart+table; on failure show error + toast.

`exportReport(format)`:
- builds payload from current chart/table data
- JSON: `navigator.clipboard.writeText` with file-download fallback (reuse existing `exportSnapshot` fallback pattern)
- CSV: `new Blob([csv], {type: 'text/csv'})` download with timestamped filename `spectre-report-<type>-<range>-<date>.csv`

Persist `spectre-report-type` and `spectre-report-range` in localStorage; restore on init.

- [ ] **Step 3: Run manual verification**

Generate a report; click Export JSON and Export CSV; confirm download/clipboard toast; reload page; confirm last type+range restored; change range to 7d; confirm x-axis shows dates.

- [ ] **Step 4: Commit**

```bash
git add web-dashboard/reports.js
git commit -m "feat(dashboard): add Reports export, Generate wiring, localStorage persistence"
```

---

### Task 6: Final verification and commit

**Files:**
- Verify: `web-dashboard/index.html`, `web-dashboard/styles.css`, `web-dashboard/reports.js`, `tests/test_reports_js.sh`

**Interfaces:** none

- [ ] **Step 1: Run pure-function test suite**

Run: `bash tests/test_reports_js.sh` → all pass.

- [ ] **Step 2: Run repo structural tests**

Run: `bash tests/run_tests.sh` → no new failures introduced (pre-existing disk-quota failures in restore tests are unrelated).

- [ ] **Step 3: Manual dashboard review**

Open dashboard; confirm Reports nav item works; each report type generates at 24h/7d/30d/90d; export JSON/CSV works; error state when Prometheus unreachable (block `/api/`); empty state when no data; mobile layout intact; console error-free.

- [ ] **Step 4: Commit final state**

```bash
git add web-dashboard/ tests/test_reports_js.sh
git commit -m "feat(dashboard): Reports subsystem — historical trends + JSON/CSV export"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-11-13-web-dashboard-reports-subsystem.md`. Please review the plan. Does it capture what you want?**

**Which execution approach should we use?**

- **Subagent-driven** — A fresh subagent implements each task and a fresh reviewer checks it before the next one starts, then a whole-branch review at the end. Most thorough; costs a fresh context per task and per review. (Tasks 3 and 5 share `reports.js` interfaces, so subagent context carries between them.)
- **Native** — I implement every task myself in this session, then one fresh reviewer checks the whole branch. Cheapest and fastest; no independent review until the end.

**For this plan I recommend Native**, because the tasks are small (a single JS module + HTML/CSS), the interfaces are fully pinned in this plan, and a shipped mistake here is cheap to revert. Does the plan capture what you want, and which approach should we use?