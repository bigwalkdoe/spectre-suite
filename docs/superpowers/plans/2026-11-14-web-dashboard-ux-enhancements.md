# Web Dashboard UX Enhancements — Auto-refresh Countdown, Keyboard Shortcuts, CSV Export

**Date:** 2026-11-14
**Repo:** spectre-suite
**Target:** `web-dashboard/index.html`, `web-dashboard/styles.css`, `web-dashboard/dashboard.js`
**Parent plan:** `docs/superpowers/plans/2026-11-06-web-dashboard-ux-plan.md` (already complete)

## Intent and why

The Spectre web dashboard already has auto-refresh (15s/30s/1m/5m/Off), but there is no visual indication of when the next refresh will fire. Operators watching the dashboard cannot tell whether auto-refresh is active or when data will next update. Additionally, keyboard users must navigate to the Refresh button rather than using a keyboard shortcut, and there is no way to export chart data (only a JSON snapshot export exists). These three small, additive improvements improve operator visibility and efficiency.

## Goals

1. **Auto-refresh countdown timer** — Show a countdown (e.g., "Next refresh in 24s") next to the Refresh button when auto-refresh is active. Countdown updates every second and is cleared when auto-refresh is off or disabled.
2. **Keyboard shortcuts** — `R` triggers a manual refresh; `?` opens a help dialog showing all keyboard shortcuts; `Esc` dismisses toasts/dialogs.
3. **Chart data CSV export** — Add a "Export CSV" button next to the existing JSON export button that downloads the current chart data as a CSV file.

## Non-goals

- No new backend or API changes.
- No WebSocket or live-push.
- No visual redesign (palette/typography/layout unchanged).
- No authentication changes.

## Constraints

- Static dashboard; served by nginx; vanilla JavaScript; no framework.
- Chart.js vendored; Font Awesome CDN.
- Must remain functional when Prometheus is unreachable (degrade gracefully).
- Mobile-responsive behavior preserved.
- All keyboard shortcuts must have visible UI hints (tooltip or help dialog).

## Approaches considered

**A) Add all three features in one task** — Fastest but harder to review/test individually.

**B) Three separate tasks** (selected) — Each feature is independently testable and committable. Cleaner review and easier rollback if one causes issues.

## How it gets built

**Task 1 — Auto-refresh countdown timer:**
- Add a countdown text element next to the Refresh button in `index.html`.
- Add CSS styling in `styles.css`.
- Implement `startRefreshCountdown()` and `stopRefreshCountdown()` in `dashboard.js`, wired into `setRefreshing()` / `fetchAllMetrics()` / `applyRefreshInterval()`.
- Update countdown every second via `setInterval`.

**Task 2 — Keyboard shortcuts:**
- Add keyboard event listener in `dashboard.js`: `R` triggers `fetchAllMetrics()`, `?` shows help dialog, `Esc` dismisses toasts/dialogs.
- Add help dialog markup in `index.html` and styles in `styles.css`.

**Task 3 — Chart data CSV export:**
- Add "Export CSV" button next to Export JSON button in `index.html`.
- Implement `exportChartCSV()` in `dashboard.js` that extracts chart labels/data and downloads as CSV.

## What's left to the builder

- Exact countdown format (e.g., "Next refresh in 24s" vs "24s").
- Exact keyboard shortcut labels in help dialog.
- CSV column naming.

## Approval needed

Sign off on this short design (reply yes/no). If approved, I'll write the implementation plan and proceed.