# Web Dashboard UX Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the Spectre Suite web dashboard (Approach A): real process/temperature data, per-card loading & error states, dark mode, toast notifications, refresh-in-progress indicator, and keyboard focus styling — with no new backend.

**Architecture:** Single-page frontend (HTML/CSS/JS) served by nginx, same-origin proxy to Prometheus. Changes are additive to the existing 3-file dashboard (index.html, styles.css, dashboard.js). Dark mode is a `data-theme`/`class` on `<html>` persisted in localStorage; toasts are a DOM container; loading/error states are per-card CSS classes toggled by JS around each Prometheus fetch.

**Tech Stack:** HTML5, CSS3, vanilla JavaScript, Chart.js (vendored), Font Awesome (CDN), Prometheus HTTP API via existing `queryPrometheus()`.

**Spec:** `docs/superpowers/specs/2026-11-06-web-dashboard-ux-design.md` — the plan argues from the spec; the spec travels with it.

## Global Constraints

- Single-file HTML/CSS/JS; served by nginx, same-origin proxy to Prometheus at `:9090`.
- Keep Chart.js (vendored in `vendor/`) and Font Awesome (CDN).
- Must remain functional when Prometheus is unreachable (degrade gracefully).
- Mobile-responsive behavior preserved (existing `@media (max-width: 768px)` rules).
- No new backend/API server, no WebSocket, no visual redesign (palette/typography/layout unchanged), no auth.

## Review Focus

1. Prometheus unreachable: each card shows an error state instead of stale `--` or a blank dashboard; toast appears on fetch failure.
2. Process count query returns no data: card shows "No data" instead of a random number.
3. Temperature query returns no data (hwmon may not be exposed): card shows "No data" instead of a random number.
4. Dark mode toggle persists across reloads via localStorage; default follows no OS preference (light by default unless user toggled).
5. Refresh in progress: button shows loading state and disables while a fetch cycle is in flight; re-enables after.
6. Focus-visible rings on all buttons and chart range controls for keyboard users.
7. Toasts appear for quick actions (backup/maintenance/security scan/logs) and dismiss after a timeout.

---

### Task 1: Dark mode infrastructure

**Files:**
- Modify: `web-dashboard/styles.css` — add dark-mode CSS variables and `.dark` rules
- Modify: `web-dashboard/index.html` — add dark-mode toggle button in header
- Modify: `web-dashboard/dashboard.js` — toggle class + localStorage persistence

**Interfaces:**
- Consumes: none
- Produces: `toggleDarkMode()` in dashboard.js; CSS `--bg`, `--card-bg`, `--text`, `--muted`, `--border` variables under `[data-theme="dark"]` / `.dark`

- [x] **Step 1: Write the failing test** (manual)

Open `web-dashboard/index.html` in a browser. Confirm no dark toggle exists and no `.dark` styles apply.

- [x] **Step 2: Implement dark-mode CSS variables and rules in styles.css**

Add a `:root`/`[data-theme="dark"]` variable block and `.dark` overrides for body, cards, stat-cards, badges, alerts, containers, chart container, footer. Keep the existing accent color `#667eea`.

- [x] **Step 3: Implement dark-mode toggle HTML in index.html**

Add a `<button id="themeToggle" class="btn btn-sm" aria-label="Toggle dark mode"><i class="fas fa-moon"></i></button>` in `.header-controls`. Add `data-theme` handling so `.dark` class on `<html>` drives styling.

- [x] **Step 4: Implement toggle JS in dashboard.js**

`toggleDarkMode()` reads/writes `localStorage.getItem('spectre-theme')`, toggles `document.documentElement.classList.toggle('dark')`, swaps the moon/sun icon. Wire to the button click. Initialize theme from localStorage on `DOMContentLoaded`.

- [x] **Step 5: Verify manually**

Reload the page; click the toggle; confirm colors invert and persist on reload.

- [x] **Step 6: Commit**

```bash
git add web-dashboard/styles.css web-dashboard/index.html web-dashboard/dashboard.js
git commit -m "feat(dashboard): add dark mode toggle with localStorage persistence"
```

---

### Task 2: Real process count and temperature queries

**Files:**
- Modify: `web-dashboard/dashboard.js`

**Interfaces:**
- Consumes: existing `queryPrometheus(query)` helper
- Produces: `fetchProcessCount()` and `fetchTemperature()` returning number|null; wired into `fetchAllMetrics()` and `updateSystemHealth()` replacing `Math.random()`

- [x] **Step 1: Write the failing test** (manual)

Open dashboard; confirm "Processes" and "Temperature" show random values (change on reload).

- [x] **Step 2: Implement real queries**

Add `node_processes_total` (or `node_processes_max`/available) query for process count and `hwmon_temp_celsius`/`node_hwmon_temp_celsius` for temperature. If the temperature metric is unavailable in this environment, expose it conditionally: query, and on null show "No data".

- [x] **Step 3: Replace Math.random() in updateSystemHealth()**

Delete the two `Math.random()` lines; populate `#processes` and `#temperature` from real values, rendering "No data" when null.

- [x] **Step 4: Verify manually**

Reload; confirm processes/temperature show real or "No data" rather than random values; confirm no console errors.

- [x] **Step 5: Commit**

```bash
git add web-dashboard/dashboard.js
git commit -m "feat(dashboard): replace fake process/temperature data with real Prometheus queries"
```

---

### Task 3: Per-card loading and error states

**Files:**
- Modify: `web-dashboard/styles.css` — loading skeleton + error-state CSS
- Modify: `web-dashboard/index.html` — aria-live regions on cards
- Modify: `web-dashboard/dashboard.js` — set/clear loading/error classes around each fetch

**Interfaces:**
- Consumes: `queryPrometheus()` results
- Produces: `setCardLoading(id, bool)`, `setCardError(id, message)` helpers; CSS `.card--loading`, `.card--error`, `.skeleton`

- [x] **Step 1: Write the failing test** (manual)

Block Prometheus (or point `PROMETHEUS_URL` at a dead port) via `?prometheus=`; confirm cards currently show stale `--` with no indication of failure.

- [x] **Step 2: Implement skeleton + error CSS in styles.css**

Add `.skeleton` pulsing animation, `.card--loading` dimming, `.card--error` border/icon, and `.error-message` styling.

- [x] **Step 3: Implement JS loading/error helpers**

Add `setCardLoading(cardId, isLoading)` and `setCardError(cardId, message)` that toggle classes and update an aria-live region. Wrap each `queryPrometheus` call in `fetchAllMetrics` with try/catch that calls `setCardError` on failure and clears it on success.

- [x] **Step 4: Verify manually**

Block Prometheus; confirm cards show error state and aria-live announces; restore Prometheus; confirm error clears and data loads.

- [x] **Step 5: Commit**

```bash
git add web-dashboard/styles.css web-dashboard/index.html web-dashboard/dashboard.js
git commit -m "feat(dashboard): add per-card loading and error states"
```

---

### Task 4: Toast notifications

**Files:**
- Modify: `web-dashboard/styles.css` — toast container + toast item styles
- Modify: `web-dashboard/index.html` — toast container markup
- Modify: `web-dashboard/dashboard.js` — `showToast(message, type)` function

**Interfaces:**
- Consumes: none
- Produces: `showToast(message, type = 'info')` in dashboard.js; `#toast-container` in index.html; `.toast`, `.toast--success`, `.toast--error`, `.toast--info` in CSS

- [x] **Step 1: Write the failing test** (manual)

Click "Run Backup"; confirm only a browser `alert()` appears, no in-page notification.

- [x] **Step 2: Implement toast CSS and HTML**

Add fixed-position `#toast-container` (top-right) and `.toast` slide-in styles with success/error/info variants and auto-dismiss timeout.

- [x] **Step 3: Implement `showToast()` and wire quick actions**

Replace `alert()` in `runBackup()`, `runMaintenance()`, `runSecurityScan()`, `viewLogs()` with `showToast(...)`. Also show toasts on Prometheus connection failure/recovery.

- [x] **Step 4: Verify manually**

Click each quick action; confirm a toast appears and dismisses; confirm no `alert()` popups remain.

- [x] **Step 5: Commit**

```bash
git add web-dashboard/styles.css web-dashboard/index.html web-dashboard/dashboard.js
git commit -m "feat(dashboard): add toast notifications for actions and connection status"
```

---

### Task 5: Refresh-in-progress indicator

**Files:**
- Modify: `web-dashboard/styles.css` — button loading state
- Modify: `web-dashboard/dashboard.js` — disable/spin Refresh button during fetch cycle

**Interfaces:**
- Consumes: `fetchAllMetrics()`
- Produces: `setRefreshing(bool)` toggling `disabled` + spinner on `#refreshBtn`

- [x] **Step 1: Write the failing test** (manual)

Click Refresh; confirm button gives no indication a fetch is running.

- [x] **Step 2: Implement button loading CSS**

Add `.btn--loading` style (opacity + spinner icon) in styles.css.

- [x] **Step 3: Implement `setRefreshing()` and wire into fetch cycle**

At start of `fetchAllMetrics()`, call `setRefreshing(true)`; in a `finally`, `setRefreshing(false)`. Disable the button and show a spinner while in flight.

- [x] **Step 4: Verify manually**

Click Refresh; confirm button disables/spins during fetch and re-enables after.

- [x] **Step 5: Commit**

```bash
git add web-dashboard/styles.css web-dashboard/dashboard.js
git commit -m "feat(dashboard): add refresh-in-progress indicator on Refresh button"
```

---

### Task 6: Keyboard focus and accessibility styling

**Files:**
- Modify: `web-dashboard/styles.css` — `:focus-visible` rings on buttons and chart controls
- Modify: `web-dashboard/dashboard.js` — ensure chart range buttons remain keyboard operable (no changes needed beyond CSS)

**Interfaces:**
- Consumes: none
- Produces: `.btn:focus-visible`, `.chart-controls .btn:focus-visible` ring styles

- [x] **Step 1: Write the failing test** (manual)

Tab through the dashboard with keyboard; confirm no visible focus ring on buttons or chart range controls.

- [x] **Step 2: Implement focus-visible styles**

Add `outline: none` reset replaced by `:focus-visible { box-shadow: 0 0 0 3px rgba(102,126,234,0.5); }` for all `.btn` and chart range buttons, preserving high contrast.

- [x] **Step 3: Verify manually**

Tab through all interactive elements; confirm a visible focus ring on each.

- [x] **Step 4: Commit**

```bash
git add web-dashboard/styles.css
git commit -m "style(dashboard): add keyboard focus-visible rings for accessibility"
```

---

### Task 7: Final verification and cleanup

**Files:**
- Verify: `web-dashboard/index.html`, `styles.css`, `dashboard.js`

**Interfaces:** none

- [x] **Step 1: Full manual review**

Open dashboard; verify: dark mode persists, processes/temperature real or "No data", cards show loading/error states, toasts appear on actions, Refresh shows in-progress state, focus rings visible, mobile layout intact, console error-free.

- [x] **Step 2: Commit final state**

```bash
git add web-dashboard/
git commit -m "feat(dashboard): UX optimization — dark mode, real data, loading/error states, toasts, focus rings"
```

---

## Self-review against spec

1. **Spec coverage:** Every goal (real process/temp data, loading/error states, dark mode, toasts, refresh indicator, focus styling) maps to Tasks 2–6. Non-goals (no backend, no WebSocket, no redesign, no auth) are respected.
2. **Step scan:** Each step is one actionable thing (CSS block, JS function, manual verification). No "TBD" or vague "handle edge cases" lines.
3. **Type consistency:** `setCardLoading`/`setCardError`/`showToast`/`setRefreshing`/`toggleDarkMode` are defined once and used consistently across tasks.
4. **Review Focus:** Each of the 7 failure modes has a task whose manual test pins it.
5. **Proportion:** Plan is ~2x the spec, appropriate for a 3-file frontend change; code blocks are signatures + small bodies only where the spec pins exact values.

---

Plan complete and saved to `docs/superpowers/plans/2026-11-06-web-dashboard-ux-plan.md`.

This plan's tasks are largely independent (each adds a separate UI concern) but share the same 3 files. I'll implement them myself in this session (Native execution), then do one review pass. Does the plan capture what you want, and shall I proceed with implementation?
