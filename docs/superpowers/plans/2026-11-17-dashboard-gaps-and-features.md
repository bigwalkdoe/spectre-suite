# Dashboard Gaps and Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evolve the Spectre Suite web dashboard from a read-only Prometheus viewer with fire-and-forget action triggers into a safer, workflow-capable, and more observable ops surface covering alert drill-down/runbooks, action lifecycle/audit, deeper history/drill-downs, and hardening/UX for shared use.

**Architecture:** Keep the current stack (static HTML/CSS/ES modules in `web-dashboard/` served by nginx with same-origin Prometheus/Grafana/Alertmanager proxies, and an allowlisted Python trigger-queue service in `web-dashboard/actions-backend/` consumed by a host handler). Add capabilities in phases: (1) UI/data-quality and read-only safety foundations, (2) action status/results readback and audit, (3) alert/runbook and observability depth (time range, drill-down, coverage, selectors), (4) sharing/hardening profiles and docs. Avoid arbitrary command execution; preserve allowlist, token/header forwarding, and redaction guarantees.

**Tech Stack:** Vanilla HTML/CSS/JavaScript (ES modules), Chart.js (vendored), nginx 1.30.5-alpine config, Python 3 stdlib HTTP server (`dashboard-actions`), Bash host trigger handler/systemd units, Prometheus HTTP API/PromQL, Alertmanager API, Docker Compose monitoring stack.

**Spec:** This plan is derived from the approved gap analysis in-session (2026-11-17): tighter ops workflows (alerts/actions/runbooks/audit), deeper observability (history, drill-downs, multi-host/service views), and hardening/UX for safe sharing. No separate pre-existing spec file; treat this plan + existing `web-dashboard/README.md`, `prometheus/prometheus.yml`, and `prometheus/alert_rules.yml` as the governing context.

## Global Constraints

- Preserve the **allowlisted, no-user-shell-args** action model (`web-dashboard/actions-backend/server.py` `ALLOWLIST`, host handler dispatch). Do not execute scripts in the container.
- Never log, persist in plaintext exports/UI, or echo `DASHBOARD_ACTION_TOKEN` / `X-Dashboard-Action-Token`.
- Keep dashboard and monitoring ports **loopback-published by default** as in `docker-compose.monitoring.yml`; any exposure changes must be explicit and documented.
- Maintain **same-origin proxying** for Prometheus API access (`/api/* -> /prometheus/api/*`) and keep method/rate/conn restrictions in nginx unless a documented security review justifies change.
- Treat missing exporters/series as first-class states (notably **cAdvisor job is disabled** in `prometheus/prometheus.yml`; disk `node_filesystem_*` can be unavailable under userns without `pid:host` on node-exporter) — UI must surface coverage/freshness, not silent emptiness.
- Follow existing file style/patterns (ES modules in `web-dashboard/js/`, CSS in `web-dashboard/styles.css`, nginx hardening patterns, Python stdlib-only backend unless justified).
- Prefer additive, backward-compatible config/query-param behavior (`config.js` patterns: `?actionsBase=off`, backend URL overrides).

## Review Focus

- **Missing/stale metrics:** Every new panel must define and render explicit states for “no series / target down / stale sample / exporter disabled” (e.g. cAdvisor disabled, `node_filesystem_*` absent) rather than showing misleading zeros/healthy badges.
- **Actions auth and safety:** Any new action read/write endpoint must enforce token/auth checks consistently, reject unsafe paths/methods, preserve allowlist boundaries, and never leak secrets in responses/logs/exports.
- **Time/range correctness:** Range queries, chart axes, “last refreshed/sample age”, and comparisons must use consistent units/timezones and not mislabel instant values as ranges (or vice versa).
- **Reverse-proxy/shared exposure:** Changes to proxied UIs (`/prometheus/`, `/grafana/`, `/alertmanager/`), headers/CSP, or action endpoints must not weaken existing hardening defaults; read-only/viewer modes must be enforced where claimed (UI gating is not sufficient alone for protected operations).
- **Large/unbounded data:** Trigger/run history, audit feeds, Prometheus range results, and container lists must be bounded/paginated or capped to avoid UI freezes and oversized responses.

---

## Phase 1 — Foundations: data coverage, read-only mode, drill-down links

### Task 1: Data coverage and freshness diagnostics

**Files:**
- Modify: `web-dashboard/js/prometheus.js`
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/js/state.js`
- Modify: `web-dashboard/js/dom.js` (only if helper needed)
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: reusable helpers for target/series presence and last-sample age (e.g. query wrappers around `up{job="..."}`, `timestamp(<metric>)` / max sample time) and UI rendering for per-job coverage states.
- Consumes: existing `queryPrometheus`/`queryPrometheusFirst`, `state.lastExporterStatus`, diagnostics card.

- [ ] **Step 1: Inventory required signals and gaps**
  - Map cards/pages to backing metrics/jobs: node (`node`), blackbox, redis/postgres exporters, business-metrics textfile series (`backup_*`, `security_*`, `*_baseline*`, monitoring stack), alerting, and note `cadvisor` disabled / docker optional.
  - Document expected behavior for missing data per card in code comments near renderers and in README troubleshooting/diagnostics.

- [ ] **Step 2: Add coverage/freshness queries**
  - Implement helpers to check `up{job="<name>"}` and (where cheap) existence/freshness of representative series (e.g. `node_filesystem_avail_bytes{mountpoint="/"}`, `container_*` presence, textfile metric timestamps if available).
  - Store normalized coverage state in `state` (e.g. `unknown|ok|stale|missing|disabled`) with reason strings.

- [ ] **Step 3: Render explicit states in UI**
  - Update diagnostics card and affected cards (containers, disk/alerts-dependent health, backup/security/baseline indicators) to show reasoned states (“cAdvisor disabled in prometheus.yml”, “no filesystem series”, “target down”, “no recent samples”) instead of blank/misleading values.
  - Add CSS classes for info/warning coverage badges consistent with existing theme.

- [ ] **Step 4: Verify**
  - Run: `node --check web-dashboard/js/prometheus.js web-dashboard/js/dashboard-core.js web-dashboard/js/state.js web-dashboard/js/dom.js`
  - Run: `python3 -m http.server` not required; open via nginx/compose if available or static sanity check in browser.
  - Expected: no syntax errors; UI shows actionable messages when a job/metric is absent.

- [ ] **Step 5: Commit**
  - `git add web-dashboard/js/prometheus.js web-dashboard/js/dashboard-core.js web-dashboard/js/state.js web-dashboard/js/dom.js web-dashboard/index.html web-dashboard/styles.css web-dashboard/README.md`
  - `git commit -m "feat(dashboard): add metric coverage and freshness diagnostics"`

### Task 2: Read-only/viewer mode for safe sharing

**Files:**
- Modify: `web-dashboard/js/config.js`
- Modify: `web-dashboard/js/actions.js`
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/README.md`
- Modify: `web-dashboard/nginx.conf` (only if server-side affordance needed; prefer UI/config first)

**Interfaces:**
- Produces: `READ_ONLY` (or equivalent) config derived from query param/config (e.g. `?readOnly=1`) surfaced to UI and actions module.
- Consumes: existing `actionsBase=off` behavior.

- [ ] **Step 1: Define read-only config and precedence**
  - Parse read-only flag in `config.js` with clear precedence relative to `actionsBase=off`; expose helper for “actions allowed”.
  - Document URL/config usage in README.

- [ ] **Step 2: Gate action UI and calls**
  - Hide/disable quick action controls, show “Viewer/read-only mode” banner/indicator, and ensure `triggerAction` no-ops with clear toast when not permitted.
  - Keep token handling inert in read-only mode.

- [ ] **Step 3: Verify**
  - Run: `node --check web-dashboard/js/config.js web-dashboard/js/actions.js web-dashboard/js/dashboard-core.js`
  - Manual: load with `?readOnly=1` and confirm no action requests can be initiated from UI.

- [ ] **Step 4: Commit**
  - `git add web-dashboard/js/config.js web-dashboard/js/actions.js web-dashboard/js/dashboard-core.js web-dashboard/index.html web-dashboard/styles.css web-dashboard/README.md web-dashboard/nginx.conf`
  - `git commit -m "feat(dashboard): add read-only viewer mode"`

### Task 3: Alert and metric drill-down links

**Files:**
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/js/dom.js` (escape/link helpers as needed)
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: link builders using `externalUrl/extBase`/Prometheus query params for alert exprs, graph ranges, and Alertmanager/silence entry points.

- [ ] **Step 1: Identify drill-down targets**
  - For alerts: use labels/annotations/generatorURL when present; fallback to Prometheus alerts/rules views and Alertmanager UI.
  - For key cards/charts: “Open in Prometheus/Grafana” with preserved metric/query and time window.

- [ ] **Step 2: Implement safe link rendering**
  - Render clickable drill-down controls with proper escaping, `rel="noopener noreferrer"`, and availability checks when backend URL unknown.

- [ ] **Step 3: Verify and commit**
  - Run: `node --check web-dashboard/js/dashboard-core.js web-dashboard/js/dom.js`
  - `git add ... && git commit -m "feat(dashboard): add alert and metric drill-down links"`

---

## Phase 2 — Ops workflows: action lifecycle, status API, audit

### Task 4: Define and persist action run status (host handler + schema)

**Files:**
- Modify: `spectre/actions/dashboard-actions/process-triggers.sh`
- Create/Modify: `web-dashboard/actions-backend/run_status.py` or inline status helpers (if small) / `web-dashboard/actions-backend/README.md`
- Modify: `web-dashboard/actions-backend/server.py` (queue metadata consistency only if needed)
- Modify: `systemd/dashboard-actions/spectre-dashboard-actions.service` or docs (if paths/env change)
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: status/result artifacts per trigger (JSON) with fields: `id`, `action`, `script`, `requestedAt`, `startedAt`, `finishedAt`, `status` (`queued|running|succeeded|failed|rejected`), `exitCode`, `message` (redacted/safe), `logRef` (path/id, not secret content), `actor`/`reason` if provided.
- Consumes: existing trigger JSON files in `TRIGGERS_DIR`.

- [ ] **Step 1: Implement atomic status transitions in host handler**
  - On pickup write running status; on completion write final status; move trigger to `processed/` or `failed/` as today while also recording canonical run record in `TRIGGERS_DIR/runs/` (or agreed dir) with safe permissions.
  - Ensure failures/timeouts still produce a terminal status; keep allowlist dispatch unchanged.

- [ ] **Step 2: Add redaction/size limits**
  - Cap message lengths; never include env/secrets/tokens; include exit code and bounded summary.

- [ ] **Step 3: Verify**
  - Run: `bash -n spectre/actions/dashboard-actions/process-triggers.sh`
  - Run: `python3 -m py_compile web-dashboard/actions-backend/server.py` (+ any new .py files)
  - Dry-run logic review: simulate trigger JSON handling in a temp dir if practical.

- [ ] **Step 4: Commit**
  - `git add spectre/actions/dashboard-actions/process-triggers.sh web-dashboard/actions-backend/* systemd/dashboard-actions/* web-dashboard/README.md dashboard-actions/` (if example dirs tracked)
  - `git commit -m "feat(actions): persist trigger run status and results"`

### Task 5: Expose read-only runs API and nginx proxy

**Files:**
- Modify: `web-dashboard/actions-backend/server.py`
- Modify: `web-dashboard/nginx.conf`
- Modify: `web-dashboard/00-http-hardening.conf` (if rate limits/zones adjusted)
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: authenticated read endpoints (e.g. `GET /runs?limit=&status=` and `GET /runs/<id>`) returning bounded, redacted status records; preserves `POST /<action>` queue behavior and `GET /healthz`.
- Consumes: run/status artifacts from Task 4.

- [ ] **Step 1: Implement safe listing/lookup**
  - Read only from designated runs/status directory; validate IDs/paths; sort newest-first; paginate/cap results.
  - Enforce same token/auth requirements as actions (or stricter read policy as decided) — do not expose unauthenticated run data when token configured.

- [ ] **Step 2: Proxy and limit in nginx**
  - Route read requests (e.g. `/actions/runs...`) to backend with `GET|HEAD` allowed and appropriate rate/conn limits; keep queue POST restrictions intact.

- [ ] **Step 3: Verify**
  - Run: `python3 -m py_compile web-dashboard/actions-backend/server.py`
  - Run: `nginx -t -c /dev/stdin` not directly applicable to fragments; validate with containerized nginx config test if available, else `docker run --rm -v "$PWD/web-dashboard/nginx.conf:/etc/nginx/conf.d/default.conf:ro" -v "$PWD/web-dashboard/00-http-hardening.conf:/etc/nginx/conf.d/00-http-hardening.conf:ro" nginx:1.30.5-alpine nginx -t` (adjust mounts for http-context includes as needed).
  - Expected: config parses; unauthorized reads rejected.

- [ ] **Step 4: Commit**
  - `git add web-dashboard/actions-backend/server.py web-dashboard/nginx.conf web-dashboard/00-http-hardening.conf web-dashboard/README.md`
  - `git commit -m "feat(actions): add read-only run status API"`

### Task 6: Action activity/audit UI and action metadata

**Files:**
- Modify: `web-dashboard/js/actions.js`
- Modify: `web-dashboard/js/dashboard-core.js` (or create `web-dashboard/js/activity.js` if cleaner)
- Modify: `web-dashboard/js/state.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: Activity/Audit panel showing queued/running/completed runs, trigger IDs, safe outcomes, and optional reason; client-side export of visible audit records.
- Consumes: `GET /actions/runs*`, existing trigger POST responses.

- [ ] **Step 1: Fetch and render run history**
  - Poll on interval/visibility rules consistent with existing refresh behavior; handle 401/503/disabled/read-only states clearly.
  - Bound rendered rows and avoid untrusted HTML (escape all fields).

- [ ] **Step 2: Enhance action submission UX**
  - Show per-action descriptions/impact and optional reason input (passed in payload and recorded if backend supports); display returned trigger ID and link to run entry.

- [ ] **Step 3: Verify and commit**
  - Run: `node --check web-dashboard/js/actions.js web-dashboard/js/dashboard-core.js web-dashboard/js/state.js` (+ new module if added)
  - `git add ... && git commit -m "feat(dashboard): add action activity and audit UI"`

### Task 7: Runbooks for alerts

**Files:**
- Create: `web-dashboard/runbooks/README.md`
- Create: `web-dashboard/runbooks/<AlertName>.md` for key alerts in `prometheus/alert_rules.yml` (start: `HighCPUUsage`, `HighMemoryUsage`, `HighDiskUsage`, `NodeExporterDown`, `BackupStale`, `BlackboxExporterDown`, `Watchdog`, `HighPostgresConnections` and critical variants as applicable)
- Modify: `web-dashboard/js/dashboard-core.js` (or create `web-dashboard/js/runbooks.js`)
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/nginx.conf` (ensure runbooks served as static assets; deny only where necessary)

**Interfaces:**
- Produces: runbook resolver by `alertname`/label with safe markdown/text rendering and fallback “no runbook” state.

- [ ] **Step 1: Author minimal, accurate runbooks**
  - Include: meaning, immediate checks, safe mitigations, verification queries/links (Prometheus/Grafana), and escalation/notes; reflect real metrics/jobs in this repo.

- [ ] **Step 2: Render runbook in alert context**
  - Fetch and display runbook content for selected/firing alert; sanitize/escape rendered content (no raw HTML execution).

- [ ] **Step 3: Verify and commit**
  - Run: `node --check` on modified JS modules.
  - Manual: confirm runbook files are reachable and render for a known alert name.
  - `git add web-dashboard/runbooks web-dashboard/js/* web-dashboard/index.html web-dashboard/styles.css web-dashboard/nginx.conf`
  - `git commit -m "feat(dashboard): add alert runbooks"`

---

## Phase 3 — Observability depth: history, drill-down, selectors, containers

### Task 8: Global time range and range-query charting

**Files:**
- Modify: `web-dashboard/js/config.js` (range presets/constants)
- Modify: `web-dashboard/js/state.js`
- Modify: `web-dashboard/js/prometheus.js`
- Modify: `web-dashboard/js/chart.js`
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: selected time window/step propagated to chart and (where appropriate) trend queries via `/api/v1/query_range`; persisted preference.
- Consumes: existing chart controls and Prometheus proxy.

- [ ] **Step 1: Implement range selection state and PromQL range helpers**
  - Support presets (1h/6h/24h/7d and custom if feasible) with bounded max points/step calculation.
  - Distinguish instant vs range queries in code paths.

- [ ] **Step 2: Wire charts/cards to selected range**
  - Update chart refresh logic, labels, and comparisons; ensure manual refresh respects range.

- [ ] **Step 3: Verify and commit**
  - Run: `node --check web-dashboard/js/config.js web-dashboard/js/state.js web-dashboard/js/prometheus.js web-dashboard/js/chart.js web-dashboard/js/dashboard-core.js`
  - `git add ... && git commit -m "feat(dashboard): add global time range and range queries"`

### Task 9: Per-entity drill-down and comparisons

**Files:**
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/js/prometheus.js`
- Modify: `web-dashboard/js/chart.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`

**Interfaces:**
- Produces: detail views/panels for selected container/instance/alert context with historical series and previous-period comparison (`offset`) where valid.

- [ ] **Step 1: Add selection model and detail panel UI**
  - From containers/alerts/charts, select entity -> render focused metrics, labels, and time series.
- [ ] **Step 2: Add comparison queries with guards**
  - Use `offset` comparisons only when sufficient history exists; show “insufficient history” otherwise.
- [ ] **Step 3: Verify and commit**
  - `node --check` modified modules; `git commit -m "feat(dashboard): add drill-down detail views and comparisons"`

### Task 10: Instance/service selectors and fleet rollups

**Files:**
- Modify: `web-dashboard/js/prometheus.js`
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/js/state.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/styles.css`
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: selector values from labels (e.g. `instance`, `job`, blackbox targets) and filtered queries/rollup summaries (targets up/down, worst saturation/latency).

- [ ] **Step 1: Discover available label values**
  - Query Prometheus label APIs/series for relevant jobs; cache and handle empty/multi-instance cases.
- [ ] **Step 2: Apply filters consistently**
  - Thread selected instance/job through metric queries and empty-state messaging.
- [ ] **Step 3: Verify and commit**
  - `node --check ...`; `git commit -m "feat(dashboard): add instance selectors and fleet rollups"`

### Task 11: Containers observability and cAdvisor strategy

**Files:**
- Modify: `prometheus/prometheus.yml` (optional, commented/tuned profile) and/or docs
- Modify: `docker-compose.monitoring.yml` (resource/flag tuning if cAdvisor re-enabled)
- Modify: `web-dashboard/js/dashboard-core.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/README.md`

**Interfaces:**
- Produces: honest containers UX when `cadvisor` absent, and working per-container metrics when enabled/tuned.

- [ ] **Step 1: Make absence explicit now**
  - Detect cAdvisor target/metrics and show current-state guidance (disabled due to CPU; how to enable safely).
- [ ] **Step 2: Define safe enablement profile (if approved to change config)**
  - If re-enabling: adjust scrape interval/flags/resources and document CPU/memory trade-offs; otherwise document external/alternative metric source.
- [ ] **Step 3: Verify and commit**
  - Run: `docker compose -f docker-compose.monitoring.yml config >/tmp/compose.monitoring.rendered.yml` (or equivalent) when compose changed.
  - `node --check` for JS; `git commit -m "feat(observability): improve container metrics coverage and guidance"`

### Task 12: Reports and recording rules alignment

**Files:**
- Modify: `web-dashboard/js/reports.js`
- Modify: `web-dashboard/js/prometheus.js`
- Modify: `web-dashboard/index.html`
- Modify: `web-dashboard/README.md`
- Modify/Create: `prometheus/alert_rules.yml` or separate rules file (recording rules) and reference in `prometheus/prometheus.yml` if added

**Interfaces:**
- Produces: reports driven by available series (backup/security/baseline/uptime/alerts) with clear “no data” reasons and reproducible query metadata.

- [ ] **Step 1: Map report types to concrete metrics**
  - Align with textfile metrics and alert/uptime series present; remove/flag unsupported assumptions.
- [ ] **Step 2: Add recording rules for expensive/common aggregates (optional but recommended)**
  - Only if needed for performance/correctness; validate rule syntax.
- [ ] **Step 3: Verify and commit**
  - `node --check web-dashboard/js/reports.js web-dashboard/js/prometheus.js`
  - If Prometheus config/rules changed: validate with `promtool check config` / `promtool check rules` in container or local tool if available.
  - `git commit -m "feat(dashboard): align reports and metrics contracts"`

---

## Phase 4 — Hardening and sharing profiles

### Task 13: Nginx exposure profiles and action hardening

**Files:**
- Modify: `web-dashboard/nginx.conf`
- Modify: `web-dashboard/00-http-hardening.conf`
- Modify: `web-dashboard/edge-hardening.example.nginx.conf`
- Modify: `web-dashboard/actions-backend/server.py` (origin/referer checks, stricter validation if appropriate)
- Modify: `web-dashboard/README.md`
- Modify: `docker-compose.monitoring.yml` (only if profile wiring requires)

**Interfaces:**
- Produces: documented/toggleable profiles for (a) viewer/read-only dashboard-only, (b) operator with actions, (c) restricted/unrestricted proxied admin UIs; stronger request validation for `/actions/`.

- [ ] **Step 1: Define safe defaults and toggles**
  - Keep default most restrictive compatible with current local use; make loosening explicit.
- [ ] **Step 2: Implement and document proxy restrictions**
  - Allow disabling or further protecting `/prometheus/`, `/grafana/`, `/alertmanager/` paths when sharing; document SSO/TLS/HSTS expectations at edge.
- [ ] **Step 3: Verify and commit**
  - Validate nginx config in container; `python3 -m py_compile web-dashboard/actions-backend/server.py`.
  - `git commit -m "feat(security): add dashboard exposure profiles and action hardening"`

### Task 14: Documentation, onboarding, and operational UX

**Files:**
- Modify: `web-dashboard/README.md`
- Modify: `README.md` (root, dashboard/monitoring sections as relevant)
- Modify: `docs/` pages if present and relevant
- Modify: `web-dashboard/index.html`, `web-dashboard/js/dashboard-core.js`, `web-dashboard/styles.css` (onboarding/empty states/help copy)

**Interfaces:**
- Produces: clear deployment modes, auth/action setup, run/audit semantics, metric coverage caveats, and in-product guidance for operators/viewers.

- [ ] **Step 1: Update docs to match implemented behavior**
  - Include read-only mode, runs/audit endpoints, runbooks, time-range/selector behavior, cAdvisor/filesystem caveats, and security boundaries.
- [ ] **Step 2: Add in-UI onboarding/help**
  - Contextual help for missing data, disabled actions, and how to connect/enable exporters.
- [ ] **Step 3: Verify and commit**
  - Proofread links/paths/commands; `node --check` modified JS.
  - `git commit -m "docs(dashboard): document workflows, observability, and sharing guidance"`

### Task 15: Final verification and rollout notes

**Files:**
- Modify: `CHANGELOG.md` (if project convention expects entries for notable changes)
- Create/Modify: `docs/superpowers/specs/2026-11-17-dashboard-gaps-and-features-rollout.md` (optional rollout/verification notes)

**Interfaces:**
- Produces: verified, deployable set of changes with explicit smoke-test checklist.

- [ ] **Step 1: Run automated/static checks available**
  - `node --check` for all modified `web-dashboard/js/*.js`
  - `python3 -m py_compile web-dashboard/actions-backend/server.py` and any added backend modules
  - `bash -n spectre/actions/dashboard-actions/process-triggers.sh`
  - Nginx config test via container (`nginx:1.30.5-alpine nginx -t`) with mounted config fragments as applicable
  - `docker compose -f docker-compose.monitoring.yml config` if compose changed
  - Prometheus rule/config validation (`promtool`) if rules changed and tooling available

- [ ] **Step 2: Manual smoke test checklist (document results)**
  - Dashboard loads at configured origin; pages navigate; no console errors.
  - Prometheus-backed cards render or show explicit coverage/missing states.
  - Alerts list/drill-downs/runbooks function (or degrade clearly).
  - Read-only mode blocks actions; action queue still works when enabled/configured; run status appears when implemented.
  - Security headers/method restrictions/rate limits preserved.

- [ ] **Step 3: Commit/changelog**
  - `git add CHANGELOG.md docs/superpowers/specs/2026-11-17-dashboard-gaps-and-features-rollout.md` (as applicable)
  - `git commit -m "chore(dashboard): finalize verification and rollout notes"`

---

## Execution Notes

- Implement in **phase order**; each task should leave the dashboard deployable. If a task reveals a required architectural choice (e.g. persistent audit store vs file-backed status), document the decision in-task and keep the simplest file-backed approach consistent with current design unless explicitly expanded.
- For UI-heavy tasks, prefer small incremental commits per task and verify in a running stack when possible (`docker compose -f docker-compose.monitoring.yml up -d --build web-dashboard dashboard-actions`).
- Where Prometheus/tooling containers or CLIs are unavailable in the environment, record what could not be validated and why in commit/rollout notes rather than claiming success.
