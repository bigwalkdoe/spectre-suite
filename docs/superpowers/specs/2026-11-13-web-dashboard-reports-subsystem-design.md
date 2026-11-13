# Web Dashboard Reports Subsystem (Approach B)

**Date:** 2026-11-13
**Repo:** spectre-suite
**Target:** `web-dashboard/` (index.html, styles.css, dashboard.js) + `docker-compose.monitoring.yml` if a backend endpoint is added
**Spec owner:** agent (implementation pending your approval)

## Intent and why

The north star of Spectre Suite is automated backups, restic snapshot workflows, monitoring/alerting (Prometheus + Grafana + Alertmanager), security/hardening helpers, maintenance jobs, and operational reporting. The dashboard today shows **current** metric values (last backup, last scan, unresolved findings) but has no way to look at **historical** trends or produce a report an operator can keep/share. A reports subsystem turns the dashboard from a status board into an operational reporting surface: pick a report type and time range, see the historical trend, export it.

This is not a new backend. It extends the existing dashboard, which already fetches Prometheus `query_range` through the same-origin `/api/` nginx proxy (used by the Trends chart), and already has an Export button for current-value snapshots.

## Goals

1. A **Reports** page in the dashboard sidebar/nav (new page tab + card).
2. Operator picks a **report type** and **time range** (24h / 7d / 30d / 90d).
3. Page fetches historical data from Prometheus via the existing same-origin `/api/` proxy (`query_range`), renders a trend table + chart, and degrades gracefully when Prometheus is unreachable or has no data for the range.
4. **Export** each report as JSON and CSV (client-side, like the existing Export snapshot button).
5. Reports cover the north-star domains: **backup/restic health**, **security findings**, **alert/incident history**, and **system health (CPU/mem/disk/net)**.

## Non-goals

- No new persistent backend service or database. Reports are generated client-side from Prometheus.
- No scheduled/emailed reports (that is a separate, larger feature).
- No multi-server support (single Prometheus, same as today).
- No authentication/SSO (already a non-goal for the dashboard).
- No modification to Prometheus retention; reports cover only data Prometheus has retained.

## Anti-goals (failure even if it technically works)

- A reports page that only shows the current value again (must be historical/trend).
- A page that breaks when Prometheus is down (must show error state, not blank).
- Adding a backend endpoint that requires container rebuild or new privileges beyond the existing dashboard-actions pattern.

## Constraints

- Static dashboard: `web-dashboard/` is bind-mounted read-only (`ro,z`) into nginx.
- CSP: `connect-src 'self'` — all Prometheus fetches must go through the same-origin `/api/` proxy (nginx rewrites `/api/*` → `/prometheus/api/*` on `prometheus:9090`).
- Dashboard JS is vanilla (no framework), Chart.js vendored under `vendor/`.
- Existing `updateChart()` pattern (query_range, step sizing, token-based staleness) should be reused where sensible.
- Must remain mobile-responsive and keyboard accessible.

## Approaches considered

**A) Lightweight report export** — Enhance the existing Export button to include historical ranges and CSV. Touches only `dashboard.js`. Shippable but small; doesn't feel like a "reports subsystem" and lacks a dedicated page/UX.

**B) Full reports subsystem** (selected) — Dedicated Reports page with report-type + range picker, historical trend table + chart per report, JSON/CSV export. Builds on existing `query_range` + export patterns. Larger surface but directly delivers "operational reporting" from the north star.

**C) Server-side reports via dashboard-actions** — Add a `/reports` endpoint to the `dashboard-actions` Python backend that queries Prometheus server-side and returns a report. Rejected: the container runs as `nobody`, the repo is mounted read-only, and generating/reporting would add new surface + privileges for a feature the client can already do via Prometheus `query_range`.

## How it gets built (parts already decided)

**Navigation:** Add a "Reports" nav item under the Operations group in `index.html` (data-page="reports") and a matching page anchor `<div id="page-reports">`.

**Page markup (`index.html`):** A Reports card containing:
- Report-type selector: Backup & Restic Health / Security Findings / Alert History / System Health
- Time-range selector: 24h / 7d / 30d / 90d
- "Generate" button
- Trend chart canvas (reuses `resourceChart` or a new canvas)
- Data table of historical points
- Export JSON / Export CSV buttons
- Loading + error states (reuse `setCardLoading`/`setCardError`)
- "No data for this range" empty state

**JS (`dashboard.js`):**
- `fetchReportMetrics(reportType, range)` — builds the right Prometheus `query_range` query per report type and range, returns `{labels, series[]}`.
  - Backup & Restic: `backup_last_success_timestamp`, `restic_last_success_timestamp`, `restic_health_ok`, `restic_verify_ok` (gauge values over time)
  - Security: `security_findings_unresolved` (and by-severity), `security_last_scan_timestamp`, `spectre_agent_up`
  - Alerts: Prometheus alert rules firing — use `ALERTS`/`ALERTINGRULES` query_range if available; fall back to current alerts list with note "alert history requires Prometheus recording rules"
  - System Health: reuse the 4 existing chart queries (CPU, memory, disk, network)
- `renderReportChart(labels, series)` — Chart.js line chart (reuse Chart.js, vendored).
- `renderReportTable(labels, series)` — HTML table of timestamp + values.
- `exportReport(format)` — JSON / CSV client-side (Blob download), reusing the existing export fallback pattern.
- Wire Generate button → fetch → render → show/hide loading/error.
- Persist last-selected report type + range in localStorage.

**CSS (`styles.css`):** Report-page table styles, export button group, empty-state styling. Reuse existing `.btn`, `.card--loading`, `.card--error`, `.skeleton` classes.

**Queries (Prometheus) per report type:**
- Backup & Restic: `backup_last_success_timestamp`, `restic_last_success_timestamp`, `max(restic_health_ok)`, `max(restic_verify_ok)`
- Security: `security_findings_unresolved`, `security_findings_unresolved_by_severity{severity="critical"}`, `security_last_scan_timestamp`, `spectre_agent_up`
- Alerts: `ALERTS{alertname!=""}` range if recording rules exist; else note + current alerts
- System Health: the 4 existing `updateChart` queries

**Mapping of gauge timestamps to trend:** Since backup/restic/security metrics are gauge timestamps (Unix seconds), a `query_range` shows when each last succeeded. The table renders `timestamp → value` rows; the chart plots value over time.

## What's left to the builder

- Exact Prometheus query strings per report type (confirm the metric names exist in this environment's exporters — e.g. `backup_last_success_timestamp` from `business-metrics-exporter.sh`, `security_findings_unresolved` from the security exporter/agent).
- Whether alert history is available via Prometheus `ALERTS` query_range or needs recording rules; decide the fallback wording.
- Confirm Chart.js can render a second canvas on the reports page without conflicts with the trends chart.
- CSV column layout per report type.

## Approval needed

Sign off on this design doc (reply yes/no). If approved, I'll write the implementation plan (`writing-plans`), then implement per the normal workflow (implementation → test → verify) and commit.