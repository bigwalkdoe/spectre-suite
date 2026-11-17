# Dashboard Gaps and Features — Rollout & Verification Notes (2026-11-17)

## Scope delivered
Implemented across Phases 1-4 of `docs/superpowers/plans/2026-11-17-dashboard-gaps-and-features.md` on branch `feat/dashboard-gaps-and-features`:
- **Foundations:** Prometheus/exporter coverage & freshness diagnostics, read-only viewer mode (`?readOnly=1`), alert/metric/container drill-down links.
- **Ops workflows:** host trigger handler persists bounded/redacted run status artifacts (`dashboard-actions/triggers/runs/`), `dashboard-actions` read-only runs API (`GET /actions/runs*`, token-protected) proxied via nginx, dashboard Action Activity panel, alert runbooks (`web-dashboard/runbooks/<AlertName>.md`).
- **Observability:** global chart time range (1h/6h/24h/7d, persisted) with `query_range`, improved drill-down navigation, fleet/targets rollup in diagnostics, cAdvisor strategy/guidance (kept disabled by default with tuned enablement notes), report query/no-data alignment.
- **Hardening & docs:** action request content-type validation, documented sharing/exposure profiles and edge hardening guidance, updated dashboard/root docs and in-UI coverage guidance.

## Automated/static verification (executed)
- `node --check` for all `web-dashboard/js/*.js` files: **pass**
- `python3 -m py_compile web-dashboard/actions-backend/server.py`: **pass**
- `bash -n spectre/actions/dashboard-actions/process-triggers.sh`: **pass**
- `nginx:1.30.5-alpine nginx -t` with mounted `web-dashboard/nginx.conf` and `web-dashboard/00-http-hardening.conf`: **pass**
- `docker compose -f docker-compose.monitoring.yml config`: **pass**

## Not fully validated in this environment
- Live browser/UI smoke test against a running monitoring stack (Prometheus data, alert firing states, Grafana/Alertmanager proxy behavior, Chart.js rendering, action token flows).
- End-to-end action execution with installed host systemd handler (queue -> host dispatch -> status transitions visible in UI).
- Prometheus rule/runtime behavior beyond config syntax/compose rendering (no rule semantic changes introduced; `prometheus.yml` comment-only cAdvisor guidance).

## Manual smoke test checklist (operator)
1. `docker compose -f docker-compose.monitoring.yml up -d --build web-dashboard dashboard-actions` (and required dependencies).
2. Open dashboard: pages load/navigate without console errors; metrics render or show explicit coverage/missing states.
3. Alerts: filters, drill-down links, and runbook panel work (including missing-runbook fallback).
4. Read-only: `?readOnly=1` shows banner and blocks action triggers.
5. Actions (configured): queue returns trigger ID; host handler writes `runs/<id>.json`; Activity panel shows queued/running/succeeded/failed states (auth errors surfaced clearly).
6. Security posture: methods/limits/CSP headers preserved; no tokens in logs/UI exports; admin UI proxies restricted per chosen deployment profile.

## Rulings/limitations (see ledger for full list)
- Partial Task 9/10 depth: drill-down navigation and fleet rollups added, but not full in-dashboard per-entity comparison panels or query-threaded instance selectors.
- cAdvisor remains disabled by default due to prior CPU impact; enablement is documented/tunable.
- Optional Prometheus recording rules and strict origin/CSRF/runtime nginx profile toggles deferred to avoid risk/breakage in this pass; rely on documented edge controls and token/auth.
