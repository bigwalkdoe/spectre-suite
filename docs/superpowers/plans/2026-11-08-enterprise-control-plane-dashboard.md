# Enterprise Spectre Control-Plane Dashboard (Implementation Plan)

## Choice (dive-in)
**Web-first control plane** served by `spectre.api` (FastAPI, API-key auth), integrating component visibility and safe action dispatch surfaces; TUI/Grafana remain specialized views and are linked from the control plane.

## Delivered foundation
1. Control-plane API endpoints aggregating: system/health, dispatch registry + recent runs, backup/restic signals, monitoring/alerting reachability, security/maintenance signals, component inventory.
2. Enterprise dashboard UI (single-page, dark/light-capable design, component cards/tables/actions) served from the API.
3. Safe, authenticated action dispatch endpoint with explicit audit metadata (uses spectre dispatch; records provenance via normal run path).

## Follow-ups (optional)
- RBAC/SSO, multi-host federation, richer Grafana embedding/proxy, websocket live updates, action approval workflows.