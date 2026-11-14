# Web Dashboard Polish — Form Scrolling, Stub Removal, Production Hardening

**Date:** 2026-11-14
**Repo:** spectre-suite
**Target:** `web-dashboard/index.html`, `web-dashboard/styles.css`, `web-dashboard/dashboard.js`
**Spec:** `docs/superpowers/specs/2026-11-14-web-dashboard-ux-enhancements.md`

## Intent and why

The Spectre web dashboard has three production-hardening gaps that need fixing:

1. **Form mouse scrolling** — `<select>` elements (refreshInterval, reportType, reportRange) and `<input type="search">` (containerFilter) scroll the entire page on touch devices instead of scrolling within the dropdown/option list. This is a serious UX problem on mobile and touch devices.

2. **Stub code** — The dashboard.js `renderContainers()` function has a placeholder `currentContainerNames` population that is never actually populated from real data, making the containers card non-functional. The `dashboard.js` also has orphaned variables and dead code paths.

3. **Production hardening** — The dashboard lacks proper error handling for missing DOM elements, has no fallback for when Prometheus is completely unreachable (shows blank cards), and lacks proper error boundaries for individual card updates.

## Goals

1. **Fix form scrolling** — Add `overscroll-behavior: contain` to all `<select>` and `<input type="search">` elements so scrolling within dropdowns doesn't scroll the page on touch devices.
2. **Remove stubs** — Remove dead code and incomplete implementations (unused variables, empty functions, dead code paths).
3. **Production polish** — Add proper error handling, graceful degradation when Prometheus is unreachable, and ensure all DOM queries have null checks.

## Non-goals

- No new features or UI redesign.
- No backend changes.
- No authentication or multi-server support.

## Constraints

- Static dashboard; served by nginx; vanilla JavaScript; no framework.
- Must remain functional when Prometheus is unreachable.
- Mobile-responsive behavior preserved.
- All existing features must continue to work after changes.

## Approaches considered

**A) Fix each issue separately** (selected) — Each fix is independent and can be committed separately. Easiest to review and rollback.

**B) One big refactor** — Riskier, harder to review, harder to rollback.

## How it gets built

**Task 1 — Fix form scrolling CSS:**
- Add `overscroll-behavior: contain` to `.refresh-interval-select`, `.report-type-select`, `.report-range-select`, `.container-filter-input` in `styles.css`.
- Add `-webkit-overflow-scrolling: touch` for iOS Safari compatibility.
- Add `touch-action: manipulation` to prevent double-tap zoom on buttons.

**Task 2 — Remove stubs and dead code:**
- Remove `chartRequestToken` if unused (or properly wire it).
- Remove `lastContainerSignature` / `lastContainerMeta` if unused.
- Remove unused variables in `dashboard.js`.

**Task 3 — Production hardening:**
- Add null checks for all `document.getElementById()` calls.
- Add graceful degradation when Prometheus is unreachable (show "No data" instead of blank cards).
- Add proper error boundaries for individual card updates.
- Ensure all async functions have proper error handling.

## What's left to the builder

- Exact countdown format for the refresh timer.
- Whether to add tooltips to all buttons.

## Status

Approved and executed (2026-11-14). All three tasks shipped on `main`:
form scrolling (`overscroll-behavior: contain`), stub/dead-code removal, and
production hardening (DOM null checks, graceful Prometheus degradation, error
boundaries per card). Two follow-up defects found during hardening were fixed
in the same pass: `exportChartCSV` read `window.chart` (always undefined) and
built its header with string+array concatenation, and `getChartTheme()`
omitted tooltip colors so dark-mode tooltips fell back to Chart.js light
defaults.

## Deferred

- `getChartTheme()` tooltip colors — now provided (`tooltipBg`/`tooltipText`/
  `tooltipBorder`) with a regression test in `tests/test_dashboard_hardening.sh`.
- `updateChart()` `if (!chart) return;` guard — already present; no change needed.
- Reviewer subagent dispatches failed ("Model unavailable" / "Insufficient
  balance"); self-review was performed against the diff instead.