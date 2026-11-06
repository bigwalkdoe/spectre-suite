# Web Dashboard UX Optimization (Approach A: Polish & Accessibility)

**Date:** 2026-11-06
**Repo:** spectre-suite
**Target:** `web-dashboard/` (index.html, styles.css, dashboard.js)

## Intent and why
The dashboard is the main human-facing view of the suite. Today it shows fake data (process count, temperature use `Math.random()`), has no loading or error states per card, no dark mode, no toast notifications, and dead-feeling quick-action buttons that just `alert()`. Approach A fixes the most frustrating UX problems without new backend infrastructure.

## Goals
- Replace fake process/temperature values with real Prometheus queries where available; show "No data" gracefully otherwise.
- Add per-card loading and error states so users know when data is stale or failed.
- Add a dark-mode toggle (persisted in localStorage).
- Add toast notifications for actions (backup, maintenance, security scan, logs).
- Add keyboard focus styling and accessible focus states on buttons and chart range controls.
- Add a refresh-in-progress indicator on the Refresh button.

## Non-goals
- No new backend/API server.
- No WebSocket or live-push (keep 30s polling).
- No visual redesign (palette, typography, layout unchanged).
- No multi-server support or authentication.

## Constraints
- Single-file HTML/CSS/JS; served by nginx, same-origin proxy to Prometheus.
- Keep Chart.js (vendored) and Font Awesome (CDN).
- Must remain functional when Prometheus is unreachable (degrade gracefully).
- Mobile-responsive behavior preserved.

## Changes (per file)
- `dashboard.js`: real queries for process count (`node_processes_*`) and temperature (`hwmon_*` where exposed), loading/error state per card, toast notifications, refresh-in-progress indicator, dark-mode class toggling, error handling that doesn't blank the whole dashboard.
- `styles.css`: dark-mode variables/rules, focus-visible styles, loading skeleton styles, per-card error states, toast container.
- `index.html`: dark-mode toggle in header, toast container markup, aria-live regions for status updates.

## What's left to the builder
- Exact Prometheus query strings for processes/temperature (confirm they exist in this environment's node-exporter).
- Confirm dark-mode colors don't reduce contrast below WCAG AA on the existing palette.

## Approval needed
Sign off on this doc, then I'll implement via the normal workflow (implementation → test → verify).

---

**Approved?** Reply yes/no and I'll proceed to implementation.
