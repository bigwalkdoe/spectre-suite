import { PROMETHEUS_URL, EXTERNAL_BACKENDS, DEFAULT_REFRESH_INTERVAL, CHART_AUTO_REFRESH_MS, SLOW_METRICS_REFRESH_MS, externalUrl, extBase, READ_ONLY, ACTIONS_ALLOWED } from './config.js';
import { fetchWithTimeout, escapeHtml, setText, setCardLoading, setCardError, clearCardError, runCardUpdate, showToast, setCardUpdated, formatBytes, formatBytesPerSec, formatRelativeTime, formatUptime } from './dom.js';
import { state } from './state.js';
import { queryPrometheus, queryPrometheusFirst, queryPrometheusSeries, checkTargetUp } from './prometheus.js';
import { triggerAction, initActionsApi } from './actions.js';
import { initializeChart, updateChart, applyChartTheme, exportChartCSV } from './chart.js';

export function initExternalLinks() {
    document.querySelectorAll('a[data-ext]').forEach((a) => {
        const backend = a.getAttribute('data-ext');
        const path = a.getAttribute('data-ext-path') || '/';
        const url = externalUrl(backend, path);
        if (url && url !== '#') a.setAttribute('href', url);
    });
    const loc = document.getElementById('dashboardLocation');
    if (loc) loc.textContent = `Prometheus-connected static dashboard (${location.host || 'localhost:8081'})`;
}

function setRefreshing(refreshing) {
    state.isRefreshing = refreshing;
    const btn = document.getElementById('refreshBtn');
    if (!btn) return;
    btn.disabled = refreshing;
    btn.setAttribute('aria-busy', refreshing ? 'true' : 'false');
    btn.classList.toggle('btn--loading', refreshing);
    if (refreshing) stopRefreshCountdown();
    else startRefreshCountdown();
}

function startRefreshCountdown() {
    stopRefreshCountdown();
    if (!state.refreshIntervalMs || state.refreshIntervalMs <= 0) return;
    state.countdownSeconds = Math.floor(state.refreshIntervalMs / 1000);
    updateCountdown();
    state.countdownIntervalId = setInterval(() => {
        state.countdownSeconds--;
        if (state.countdownSeconds <= 0) state.countdownSeconds = Math.floor(state.refreshIntervalMs / 1000);
        updateCountdown();
    }, 1000);
}

function stopRefreshCountdown() {
    if (state.countdownIntervalId) {
        clearInterval(state.countdownIntervalId);
        state.countdownIntervalId = null;
    }
}

function updateCountdown() {
    const el = document.getElementById('refreshCountdown');
    if (!el) return;
    if (!state.refreshIntervalMs || state.refreshIntervalMs <= 0) {
        el.style.display = 'none';
        return;
    }
    el.style.display = 'inline';
    el.textContent = `Next refresh in ${state.countdownSeconds}s`;
}

function loadRefreshInterval() {
    const saved = localStorage.getItem('spectre-refresh-interval');
    const ms = saved !== null ? parseInt(saved, 10) : DEFAULT_REFRESH_INTERVAL;
    state.refreshIntervalMs = isNaN(ms) ? DEFAULT_REFRESH_INTERVAL : ms;
    const select = document.getElementById('refreshInterval');
    if (select) {
        select.value = String(state.refreshIntervalMs);
        if (!select.value) select.value = String(DEFAULT_REFRESH_INTERVAL);
    }
}

export function applyRefreshInterval() {
    if (state.refreshTimerId) {
        clearInterval(state.refreshTimerId);
        state.refreshTimerId = null;
    }
    if (state.refreshIntervalMs > 0 && !document.hidden) {
        state.refreshTimerId = setInterval(fetchAllMetrics, state.refreshIntervalMs);
    }
    startRefreshCountdown();
    updateDiagnostics();
}

function restorePersistedUiState() {
    const savedSeverity = localStorage.getItem('spectre-alert-severity-filter');
    if (savedSeverity) {
        const btn = document.querySelector(`#alertFilters .btn[data-severity="${CSS.escape(savedSeverity)}"]`);
        if (btn) {
            document.querySelectorAll('#alertFilters .btn').forEach(b => {
                b.classList.remove('active');
                b.setAttribute('aria-pressed', 'false');
            });
            btn.classList.add('active');
            btn.setAttribute('aria-pressed', 'true');
            state.activeAlertFilter = savedSeverity;
        }
    }
    const savedRange = localStorage.getItem('spectre-chart-range');
    if (savedRange && { '1h': 1, '6h': 1, '24h': 1, '7d': 1 }[savedRange]) {
        const btn = document.querySelector(`.chart-controls .btn[data-range="${CSS.escape(savedRange)}"]`);
        if (btn) {
            document.querySelectorAll('.chart-controls .btn').forEach(b => {
                b.classList.remove('active');
                b.setAttribute('aria-pressed', 'false');
            });
            btn.classList.add('active');
            btn.setAttribute('aria-pressed', 'true');
        }
    }
}

function initializeTheme() {
    const html = document.documentElement;
    const savedTheme = localStorage.getItem('spectre-theme');
    const toggle = document.getElementById('themeToggle');
    const icon = toggle ? toggle.querySelector('i') : null;
    const isDark = savedTheme === 'dark';
    html.classList.toggle('dark', isDark);
    if (icon) icon.classList.toggle('fa-sun', isDark);
    if (icon) icon.classList.toggle('fa-moon', !isDark);
    if (toggle) {
        toggle.setAttribute('aria-pressed', isDark ? 'true' : 'false');
        toggle.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
    }
}

function toggleDarkMode() {
    const html = document.documentElement;
    const isDark = html.classList.toggle('dark');
    const toggle = document.getElementById('themeToggle');
    const icon = toggle ? toggle.querySelector('i') : null;
    if (icon) {
        icon.classList.toggle('fa-sun', isDark);
        icon.classList.toggle('fa-moon', !isDark);
    }
    if (toggle) {
        toggle.setAttribute('aria-pressed', isDark ? 'true' : 'false');
        toggle.setAttribute('aria-label', isDark ? 'Switch to light mode' : 'Switch to dark mode');
    }
    localStorage.setItem('spectre-theme', isDark ? 'dark' : 'light');
    applyChartTheme();
}

function showHelpDialog() { const d = document.getElementById('keyboardHelp'); if (d) d.style.display = 'flex'; }
function hideHelpDialog() { const d = document.getElementById('keyboardHelp'); if (d) d.style.display = 'none'; }

function handleKeyboard(e) {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) return;
    if (e.key === 'r' || e.key === 'R') { e.preventDefault(); fetchAllMetrics(); }
    else if (e.key === '?') { e.preventDefault(); showHelpDialog(); }
    else if (e.key === 'Escape') {
        hideHelpDialog();
        const container = document.getElementById('toast-container');
        if (container) container.querySelectorAll('.toast').forEach(t => t.remove());
    }
}

function updateTimestamp() {
    if (document.hidden) return;
    const el = document.getElementById('timestamp');
    if (el) el.textContent = new Date().toLocaleString();
}

function updateLastRefreshed() {
    const el = document.getElementById('lastRefreshed');
    if (el) el.textContent = ` | Last refreshed: ${new Date().toLocaleTimeString()}`;
}

function coverageBadgeClass(status) {
    if (status === 'ok') return 'badge-success';
    if (status === 'down' || status === 'missing' || status === 'stale') return 'badge-warning';
    if (status === 'disabled') return 'badge-warning';
    return '';
}

function updateDiagnostics() {
    const queryHealth = document.getElementById('queryHealth');
    const backupExporter = document.getElementById('backupExporterStatus');
    const agentMetrics = document.getElementById('agentMetricsStatus');
    const baselineExporter = document.getElementById('baselineExporterStatus');
    const autoRefresh = document.getElementById('autoRefreshStatus');
    const diagStatus = document.getElementById('diagnosticsStatus');
    const coverageEl = document.getElementById('coverageDetails');

    if (queryHealth) {
        if (state.lastQueryStats.total === 0) queryHealth.textContent = 'No queries run';
        else queryHealth.textContent = `${state.lastQueryStats.succeeded}/${state.lastQueryStats.total} metrics loaded (${state.lastQueryStats.failed} failed)`;
    }
    if (backupExporter) backupExporter.textContent = state.lastExporterStatus.backup ? 'Publishing metrics' : 'No data (not scheduled or no output)';
    if (agentMetrics) agentMetrics.textContent = state.lastExporterStatus.agent ? 'Publishing metrics' : 'No data (agent unavailable)';
    if (baselineExporter) baselineExporter.textContent = state.lastExporterStatus.baseline ? 'Publishing metrics' : 'No data (not scheduled or no output)';
    if (autoRefresh) {
        if (state.refreshIntervalMs > 0) {
            const label = state.refreshIntervalMs >= 60000 ? `${state.refreshIntervalMs / 60000}m` : `${state.refreshIntervalMs / 1000}s`;
            autoRefresh.textContent = `Every ${label}`;
        } else autoRefresh.textContent = 'Disabled';
    }

    const cov = state.coverageStatus || {};
    if (coverageEl) {
        const entries = Object.entries(cov);
        if (!entries.length) {
            coverageEl.innerHTML = '<span class="muted">Coverage not yet checked.</span>';
        } else {
            coverageEl.innerHTML = entries.map(([key, info]) => {
                const status = info?.status || 'unknown';
                const reason = escapeHtml(info?.reason || status);
                const label = escapeHtml(key);
                return `<div class="coverage-row"><span class="coverage-label">${label}</span><span class="badge ${coverageBadgeClass(status)}">${escapeHtml(status)}</span><span class="coverage-reason">${reason}</span></div>`;
            }).join('');
        }
    }

    if (diagStatus) {
        const values = Object.values(cov);
        const hasCoverageIssues = values.some(v => ['down', 'missing', 'stale', 'disabled'].includes(v?.status));
        const healthy = state.lastQueryStats.failed === 0 && state.lastQueryStats.total > 0 && !hasCoverageIssues;
        const degraded = (state.lastQueryStats.succeeded > 0 && state.lastQueryStats.failed > 0) || hasCoverageIssues;
        diagStatus.textContent = healthy ? 'OK' : degraded ? 'Degraded' : state.lastQueryStats.total === 0 ? '--' : 'Issues';
        diagStatus.className = healthy ? 'badge badge-success' : degraded ? 'badge badge-warning' : 'badge';
    }
}

// --- metric renderers ---
function updateCPUMetrics(cpuUsage) {
    if (cpuUsage === null) return;
    setText('cpuUsage', cpuUsage.toFixed(1) + '%');
    const change = document.getElementById('cpuChange');
    if (change) {
        if (cpuUsage > 80) { change.textContent = 'High'; change.className = 'stat-change negative'; }
        else if (cpuUsage > 60) { change.textContent = 'Moderate'; change.className = 'stat-change'; }
        else { change.textContent = 'Normal'; change.className = 'stat-change positive'; }
    }
    clearCardError('cpuCard'); setCardUpdated('cpuCard');
}
function updateMemoryMetrics(memoryUsage) {
    if (memoryUsage === null) return;
    setText('memoryUsage', memoryUsage.toFixed(1) + '%');
    const change = document.getElementById('memoryChange');
    if (change) {
        if (memoryUsage > 80) { change.textContent = 'High'; change.className = 'stat-change negative'; }
        else if (memoryUsage > 60) { change.textContent = 'Moderate'; change.className = 'stat-change'; }
        else { change.textContent = 'Normal'; change.className = 'stat-change positive'; }
    }
    clearCardError('memoryCard'); setCardUpdated('memoryCard');
}
function updateDiskMetrics(diskUsage) {
    if (diskUsage === null) return;
    setText('diskUsage', diskUsage.toFixed(1) + '%');
    const change = document.getElementById('diskChange');
    if (change) {
        if (diskUsage > 80) { change.textContent = 'High'; change.className = 'stat-change negative'; }
        else if (diskUsage > 60) { change.textContent = 'Moderate'; change.className = 'stat-change'; }
        else { change.textContent = 'Normal'; change.className = 'stat-change positive'; }
    }
    clearCardError('diskCard'); setCardUpdated('diskCard');
}
function updateNetworkMetrics(networkIn, networkOut) {
    if (networkIn === null || networkOut === null) return;
    const totalBytes = networkIn + networkOut;
    const networkEl = document.getElementById('networkIO');
    if (networkEl) {
        networkEl.textContent = formatBytesPerSec(totalBytes);
        networkEl.title = `${(totalBytes / 1024).toFixed(1)} KB/s (RX+TX, 5m rate)`;
    }
    const change = document.getElementById('networkChange');
    if (change) {
        if (totalBytes > 100 * 1024 * 1024) { change.textContent = 'High'; change.className = 'stat-change negative'; change.title = ''; }
        else if (totalBytes < 5120) { change.textContent = 'Idle'; change.className = 'stat-change'; change.title = 'Near-zero measured RX+TX (5m rate). Verify in Prometheus if unexpected.'; }
        else { change.textContent = 'Normal'; change.className = 'stat-change positive'; change.title = ''; }
    }
    clearCardError('networkCard'); setCardUpdated('networkCard');
}
function updateSystemHealth(systemLoad, bootTime, processCount, temperature) {
    if (systemLoad !== null) {
        setText('systemLoad', systemLoad.toFixed(2));
        const healthStatus = document.getElementById('healthStatus');
        if (healthStatus) {
            if (systemLoad > 2.0) { healthStatus.textContent = 'High Load'; healthStatus.className = 'badge badge-danger'; }
            else if (systemLoad > 1.0) { healthStatus.textContent = 'Moderate Load'; healthStatus.className = 'badge badge-warning'; }
            else { healthStatus.textContent = 'Healthy'; healthStatus.className = 'badge badge-success'; }
        }
    }
    if (bootTime !== null) setText('uptime', formatUptime(Date.now() / 1000 - bootTime));
    setText('processes', processCount !== null ? Math.floor(processCount) : 'No data');
    setText('temperature', temperature !== null ? Math.floor(temperature) + '°C' : 'No data');
    clearCardError('healthCard'); setCardUpdated('healthCard');
}

function updateBackupStatus(lastSuccess, healthOk, healthTs, repoBytes, repoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs) {
    const statusEl = document.getElementById('backupStatus');
    const lastEl = document.getElementById('lastBackup');
    const healthEl = document.getElementById('backupHealth');
    const resticHealthEl = document.getElementById('resticHealth');
    const sizeEl = document.getElementById('backupSize');
    const offsiteEl = document.getElementById('resticOffsite');
    const verifyEl = document.getElementById('resticVerify');

    const effectiveLast = (lastSuccess && lastSuccess > 0) ? lastSuccess : (resticLastSuccess && resticLastSuccess > 0 ? resticLastSuccess : null);
    const hasData = effectiveLast !== null || healthOk !== null || repoBytes !== null || resticHealthOk !== null || resticVerifyOk !== null || resticOffsite !== null;
    if (!hasData) {
        if (statusEl) { statusEl.textContent = 'No data'; statusEl.className = 'badge'; }
        [lastEl, healthEl, resticHealthEl, sizeEl, offsiteEl, verifyEl].forEach(el => { if (el) el.textContent = 'No data'; });
        setCardError('backupCard', 'Backup metrics unavailable (exporter may not be running)');
        return;
    }
    if (lastEl) { lastEl.textContent = effectiveLast ? formatRelativeTime(effectiveLast) : 'Never'; if (effectiveLast) lastEl.title = new Date(effectiveLast * 1000).toLocaleString(); }
    if (healthEl) {
        if (healthOk === 1) healthEl.textContent = `OK${healthTs ? ` (${formatRelativeTime(healthTs)})` : ''}`;
        else if (healthOk === 0) healthEl.textContent = `Failed${healthTs ? ` (${formatRelativeTime(healthTs)})` : ''}`;
        else healthEl.textContent = 'No data';
        if (healthTs) healthEl.title = new Date(healthTs * 1000).toLocaleString();
    }
    if (resticHealthEl) {
        if (resticHealthOk === 1) resticHealthEl.textContent = `OK${resticHealthTs ? ` (${formatRelativeTime(resticHealthTs)})` : ''}`;
        else if (resticHealthOk === 0 && resticHealthTs) resticHealthEl.textContent = `Degraded (${formatRelativeTime(resticHealthTs)})`;
        else if (resticHealthTs) resticHealthEl.textContent = formatRelativeTime(resticHealthTs);
        else resticHealthEl.textContent = 'No data';
        if (resticHealthTs) resticHealthEl.title = new Date(resticHealthTs * 1000).toLocaleString();
    }
    if (sizeEl) {
        const sizeText = formatBytes(repoBytes);
        const freeText = repoFree !== null ? formatBytes(repoFree) : null;
        sizeEl.textContent = freeText ? `${sizeText} / ${freeText} free` : sizeText;
    }
    if (offsiteEl) { offsiteEl.textContent = (resticOffsite && resticOffsite > 0) ? formatRelativeTime(resticOffsite) : 'No data'; if (resticOffsite && resticOffsite > 0) offsiteEl.title = new Date(resticOffsite * 1000).toLocaleString(); }
    if (verifyEl) {
        if (resticVerifyOk === 1) verifyEl.textContent = `Passed${resticVerifyTs ? ` (${formatRelativeTime(resticVerifyTs)})` : ''}`;
        else if (resticVerifyOk === 0 && resticVerifyTs) verifyEl.textContent = `Failed (${formatRelativeTime(resticVerifyTs)})`;
        else if (resticVerifyTs) verifyEl.textContent = formatRelativeTime(resticVerifyTs);
        else verifyEl.textContent = 'No data';
        if (resticVerifyTs) verifyEl.title = new Date(resticVerifyTs * 1000).toLocaleString();
    }
    if (statusEl) {
        const isHealthy = healthOk === 1;
        const isStale = effectiveLast && (Date.now() / 1000 - effectiveLast) > 86400 * 2;
        const verifyBad = resticVerifyOk === 0;
        const resticHealthBad = resticHealthOk === 0 && !!resticHealthTs;
        const lowFreeSpace = repoFree !== null && repoFree < 20 * 1024 * 1024 * 1024;
        if (isHealthy && !isStale && !verifyBad && !resticHealthBad && !lowFreeSpace) { statusEl.textContent = 'OK'; statusEl.className = 'badge badge-success'; }
        else if (healthOk === 0 || isStale || verifyBad || resticHealthBad || lowFreeSpace) { statusEl.textContent = 'Attention'; statusEl.className = 'badge badge-warning'; }
        else { statusEl.textContent = 'Unknown'; statusEl.className = 'badge'; }
    }
    clearCardError('backupCard'); setCardUpdated('backupCard');
}

function updateSecurityStatus(spectreUp, everScanned, lastScan, unresolved, critical, high, medium, low, agentReason, baseline) {
    const statusEl = document.getElementById('securityStatus');
    const agentEl = document.getElementById('agentStatusDetail');
    const scanEl = document.getElementById('lastSecurityScan');
    const vulnEl = document.getElementById('vulnerabilities');
    const severityEl = document.getElementById('severityBreakdown');
    const checkLabel = (v) => (v === 1 ? 'OK' : v === 0 ? 'Issue' : 'Unknown');
    const hasSecurityMetrics = spectreUp !== null;
    if (!hasSecurityMetrics) {
        const b = baseline || {};
        const hasBaseline = b.exporterUp === 1 || b.neverRun !== null || b.lastRun !== null;
        if (hasBaseline) {
            if (statusEl) { statusEl.textContent = b.neverRun === 1 ? 'Baseline Pending' : (b.stale === 1 ? 'Baseline Stale' : 'Baseline Only'); statusEl.className = b.stale === 1 ? 'badge badge-warning' : (b.neverRun === 1 ? 'badge badge-warning' : 'badge badge-success'); }
            if (agentEl) agentEl.textContent = 'Unavailable';
            if (scanEl) {
                if (b.neverRun === 1) scanEl.textContent = 'No baseline evidence yet';
                else if (b.lastRun && b.lastRun > 0) { scanEl.textContent = formatRelativeTime(b.lastRun); scanEl.title = new Date(b.lastRun * 1000).toLocaleString(); }
                else scanEl.textContent = 'Unknown';
            }
            if (vulnEl) vulnEl.textContent = b.neverRun === 1 ? '—' : 'n/a';
            if (severityEl) {
                const parts = [`OPA ${checkLabel(b.opaOk)}`, `Drift ${checkLabel(b.drift === 1 ? 0 : b.drift === 0 ? 1 : -1)}`, `TrivyFS ${checkLabel(b.trivyFsOk)}`, `Gitleaks ${checkLabel(b.gitleaksOk)}`];
                severityEl.textContent = parts.join(' · ');
                severityEl.title = 'Security baseline pipeline checks (distinct from agent/runtime findings). OPA/TrivyFS/Gitleaks: 1=ok, 0=issue, -1=unknown. Drift shown as OK/Issue.';
            }
            clearCardError('securityCard');
            if (b.neverRun === 1) setCardError('securityCard', 'Security agent metrics unavailable. Baseline exporter is publishing, but no baseline evidence has run yet.');
            setCardUpdated('securityCard');
            return;
        }
        if (statusEl) { statusEl.textContent = 'No data'; statusEl.className = 'badge'; }
        [agentEl, scanEl, vulnEl, severityEl].forEach(el => { if (el) el.textContent = 'No data'; });
        setCardError('securityCard', 'Security metrics unavailable');
        return;
    }

    if (spectreUp === 0) {
        const reasonText = agentReason ? agentReason.replace(/_/g, ' ') : 'unavailable';
        if (statusEl) { statusEl.textContent = 'Agent Down'; statusEl.className = 'badge badge-danger'; }
        if (agentEl) agentEl.textContent = `Down (${reasonText})`;
        if (scanEl) scanEl.textContent = 'Agent unavailable';
        if (vulnEl) vulnEl.textContent = 'Unknown';
        if (severityEl) severityEl.textContent = 'Unknown';
        setCardError('securityCard', `Spectre security agent is down: ${reasonText}`);
        return;
    }

    if (agentEl) agentEl.textContent = 'Up';
    if (scanEl) {
        if (everScanned === 1 && lastScan) { scanEl.textContent = formatRelativeTime(lastScan); scanEl.title = new Date(lastScan * 1000).toLocaleString(); }
        else if (everScanned === 0) scanEl.textContent = 'Never scanned';
        else scanEl.textContent = 'No data';
    }

    const totalFindings = unresolved !== null ? Math.floor(unresolved) : null;
    const c = critical !== null ? Math.floor(critical) : 0;
    const h = high !== null ? Math.floor(high) : 0;
    const m = medium !== null ? Math.floor(medium) : 0;
    const l = low !== null ? Math.floor(low) : 0;
    if (vulnEl) vulnEl.textContent = totalFindings !== null ? String(totalFindings) : 'No data';
    if (severityEl) {
        if (totalFindings !== null) { severityEl.textContent = `C:${c} H:${h} M:${m} L:${l}`; severityEl.title = `Critical: ${c}, High: ${h}, Medium: ${m}, Low: ${l}`; }
        else severityEl.textContent = 'No data';
    }
    if (statusEl) {
        if (totalFindings === null) { statusEl.textContent = 'Unknown'; statusEl.className = 'badge'; }
        else if (c > 0 || totalFindings > 10) { statusEl.textContent = 'At Risk'; statusEl.className = 'badge badge-danger'; }
        else if (h > 0 || totalFindings > 0) { statusEl.textContent = 'Review'; statusEl.className = 'badge badge-warning'; }
        else { statusEl.textContent = 'Secure'; statusEl.className = 'badge badge-success'; }
    }
    clearCardError('securityCard'); setCardUpdated('securityCard');
}

// --- alerts ---
function parseAlertTime(value) {
    if (!value) return null;
    if (typeof value === 'number') return value * 1000;
    const t = Date.parse(value);
    return isNaN(t) ? null : t;
}
function formatAlertAge(startMs) {
    if (!startMs) return '';
    const diff = Math.floor((Date.now() - startMs) / 1000);
    if (diff < 60) return `firing ${diff}s`;
    if (diff < 3600) return `firing ${Math.floor(diff / 60)}m`;
    if (diff < 86400) return `firing ${Math.floor(diff / 3600)}h ${Math.floor((diff % 3600) / 60)}m`;
    return `firing ${Math.floor(diff / 86400)}d`;
}
function renderAlerts() {
    const alertsList = document.getElementById('alertsList');
    if (!alertsList) return;
    const currentAlerts = state.currentAlerts;
    const filtered = state.activeAlertFilter === 'all' ? currentAlerts : currentAlerts.filter(a => (a.labels?.severity || 'info') === state.activeAlertFilter);
    const countEl = document.getElementById('alertCount');
    if (countEl) {
        countEl.textContent = String(currentAlerts.length);
        const hasCritical = currentAlerts.some(a => (a.labels?.severity || '') === 'critical');
        const hasWarning = currentAlerts.some(a => (a.labels?.severity || '') === 'warning');
        countEl.className = hasCritical ? 'badge badge-danger' : hasWarning ? 'badge badge-warning' : 'badge badge-success';
    }
    if (currentAlerts.length === 0) { alertsList.innerHTML = '<div class="no-alerts no-alerts--ok"><i class="fas fa-check-circle" aria-hidden="true"></i><span><strong>All clear.</strong> No active alerts are firing.</span></div>'; return; }
    if (filtered.length === 0) { alertsList.innerHTML = `<div class="empty-state"><i class="fas fa-filter" aria-hidden="true"></i><span>No <strong>${escapeHtml(state.activeAlertFilter)}</strong> alerts match the current filter (${currentAlerts.length} total).</span></div>`; return; }
    const filterNote = state.activeAlertFilter !== 'all' ? `<div class="alert-filter-note muted" aria-live="polite">Showing ${filtered.length} of ${currentAlerts.length} active alerts</div>` : '';
    alertsList.innerHTML = filterNote + filtered.map(alert => {
        const rawSeverity = String(alert.labels?.severity || 'info').toLowerCase();
        const severity = ['critical', 'warning', 'info'].includes(rawSeverity) ? rawSeverity : 'info';
        const name = alert.labels?.alertname || 'Unnamed alert';
        const description = alert.annotations?.description || alert.annotations?.summary || '';
        const startMs = parseAlertTime(alert.activeAt || alert.startsAt);
        const safeName = document.createElement('span'); safeName.textContent = name;
        const safeDesc = document.createElement('span'); safeDesc.textContent = description;
        const timeStr = startMs ? new Date(startMs).toLocaleString() : 'Unknown time';
        const ageStr = formatAlertAge(startMs);
        const promBase = extBase('prometheus');
        const amBase = extBase('alertmanager');
        const alertname = alert.labels?.alertname ? String(alert.labels.alertname) : '';
        const promqlName = alertname.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ');
        const amFilter = alertname ? encodeURIComponent(`{alertname="${alertname.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')}"}`) : '';
        const promGraphHref = (promBase && alertname) ? `${promBase}/graph?g0.expr=${encodeURIComponent(`ALERTS{alertname="${promqlName}"}`)}&g0.tab=1` : (promBase ? `${promBase}/alerts` : '');
        const amHref = amBase ? `${amBase}/#/alerts${amFilter ? `?receiver=&silenced=false&inhibited=false&active=true&filter=${amFilter}` : ''}` : '';
        const links = [promGraphHref ? `<a href="${escapeHtml(promGraphHref)}" target="_blank" rel="noopener noreferrer" title="${escapeHtml(alertname ? 'Open in Prometheus with pre-filled ALERTS query' : 'Open Prometheus alerts')}" aria-label="Open in Prometheus">Prometheus</a>` : '', amHref ? `<a href="${escapeHtml(amHref)}" target="_blank" rel="noopener noreferrer" title="${escapeHtml(alertname ? 'Open in Alertmanager (filter pre-filled where supported)' : 'Open Alertmanager')}" aria-label="Open in Alertmanager">Alertmanager</a>` : ''].filter(Boolean).join('');
        return `
        <div class="alert-item ${escapeHtml(severity)}">
            <div class="alert-title">${safeName.innerHTML}</div>
            <div class="alert-description">${safeDesc.innerHTML}</div>
            <div class="alert-meta">
                <span class="alert-severity-tag">${escapeHtml(severity)}</span>
                <span class="alert-age">${escapeHtml(ageStr)}</span>
                <span class="alert-time">${escapeHtml(timeStr)}</span>
                ${links ? `<span class="alert-actions">${links}</span>` : ''}
            </div>
        </div>`;
    }).join('');
}

async function checkAlerts() {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/alerts`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.alerts)) throw new Error('Invalid alerts response');
        state.currentAlerts = data.data.alerts.filter(alert => alert.state === 'firing');
        renderAlerts();
        clearCardError('alertsCard'); setCardUpdated('alertsCard');
    } catch (error) {
        console.error('Error checking alerts:', error);
        state.currentAlerts = [];
        clearCardError('alertsCard');
        const alertsCard = document.getElementById('alertsCard');
        if (alertsCard) alertsCard.classList.add('card--error');
        const alertsList = document.getElementById('alertsList');
        if (alertsList) alertsList.innerHTML = '<div class="no-alerts no-alerts--degraded"><i class="fas fa-triangle-exclamation" aria-hidden="true"></i><span><strong>Alerts unavailable.</strong> Unable to fetch alert data from Prometheus/Alertmanager.</span></div>';
    }
}

// --- containers ---
function renderContainers() {
    const grid = document.getElementById('containersGrid');
    if (!grid) return;
    const q = (document.getElementById('containerFilter')?.value || '').trim().toLowerCase();
    const names = Array.isArray(state.currentContainerNames) ? state.currentContainerNames : [];
    const filteredNames = q ? names.filter(n => n.toLowerCase().includes(q)) : names;
    const renderKey = `${state.lastContainerSignature}|${q}`;
    if (renderKey === state.lastRenderedContainerKey) return;
    state.lastRenderedContainerKey = renderKey;

    if (!names.length) {
        const cadvisorCov = state.coverageStatus?.cadvisor;
        if (cadvisorCov?.status === 'disabled' || cadvisorCov?.status === 'missing') {
            grid.innerHTML = `<div class="no-alerts no-alerts--degraded"><i class="fas fa-cubes" aria-hidden="true"></i><span><strong>Container metrics unavailable.</strong> ${escapeHtml(cadvisorCov.reason || 'cAdvisor metrics are not available.')} To populate this view, enable/tune cAdvisor in <code>prometheus/prometheus.yml</code> and <code>docker-compose.monitoring.yml</code>, then restart Prometheus/cAdvisor.</span></div>`;
        } else if (cadvisorCov?.status === 'down') {
            grid.innerHTML = `<div class="no-alerts no-alerts--degraded"><i class="fas fa-cubes" aria-hidden="true"></i><span><strong>Container metrics unavailable.</strong> ${escapeHtml(cadvisorCov.reason || 'cAdvisor target is down.')}</span></div>`;
        } else if (state.lastContainerMeta.hasUnlabeledRecent) {
            grid.innerHTML = '<div class="no-alerts no-alerts--degraded"><i class="fas fa-cubes" aria-hidden="true"></i><span><strong>cAdvisor metrics are present, but no named container labels were found.</strong> Check cAdvisor/Prometheus container label configuration.</span></div>';
        } else {
            grid.innerHTML = '<div class="no-alerts no-alerts--degraded"><i class="fas fa-cubes" aria-hidden="true"></i><span>No recent container data.</span></div>';
        }
        return;
    }
    if (!filteredNames.length) {
        grid.innerHTML = `<div class="empty-state"><i class="fas fa-filter" aria-hidden="true"></i><span>No containers match <strong>${escapeHtml(q)}</strong>.</span></div>`;
        return;
    }
    const containers = filteredNames.map(name => ({ name, status: 'running' }));
    const groups = new Map();
    for (const c of containers) {
        const key = (c.name || '').split(/[-_]/)[0] || c.name || 'other';
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(c);
    }
    const sortedGroups = [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]));
    const renderItem = (container) => `
        <div class="container-item">
            <div class="container-name">${escapeHtml(container.name)}</div>
            <span class="container-status ${escapeHtml(container.status)}">${escapeHtml(container.status)}</span>
        </div>`;
    grid.innerHTML = sortedGroups.map(([key, items]) => `
        <section class="container-group" aria-label="${escapeHtml(key)} containers">
            <div class="container-group-header">
                <span class="container-group-name">${escapeHtml(key)}</span>
                <span class="container-group-count">${items.length}</span>
            </div>
            <div class="containers-grid container-group-items">${items.map(renderItem).join('')}</div>
        </section>`).join('');
}

async function updateCoverageStatus(coreValues = {}) {
    const [nodeUp, cadvisorUp, redisUp, postgresUp, alertmanagerUp, blackboxUp] = await Promise.all([
        checkTargetUp('node'),
        checkTargetUp('cadvisor'),
        checkTargetUp('redis'),
        checkTargetUp('postgres'),
        checkTargetUp('alertmanager'),
        checkTargetUp('blackbox-http'),
    ]);

    const fsSeries = await queryPrometheusSeries('node_filesystem_avail_bytes{mountpoint="/"}');
    const coverage = {};

    coverage.prometheus = state.lastPrometheusConnected === true
        ? { status: 'ok', reason: 'Prometheus API reachable' }
        : state.lastPrometheusConnected === false
            ? { status: 'down', reason: 'Prometheus API unreachable/disconnected' }
            : { status: 'unknown', reason: 'Prometheus connectivity not yet checked' };

    coverage.node_exporter = nodeUp || { status: 'unknown', reason: 'Node exporter status unknown' };

    if (cadvisorUp?.status === 'missing') {
        coverage.cadvisor = { status: 'disabled', reason: 'cAdvisor scrape job/target not present (disabled in prometheus.yml by default due to CPU usage)' };
    } else {
        coverage.cadvisor = cadvisorUp || { status: 'unknown', reason: 'cAdvisor status unknown' };
    }

    coverage.redis_exporter = redisUp || { status: 'unknown', reason: 'Redis exporter status unknown' };
    coverage.postgres_exporter = postgresUp || { status: 'unknown', reason: 'Postgres exporter status unknown' };
    coverage.alertmanager = alertmanagerUp || { status: 'unknown', reason: 'Alertmanager status unknown' };
    coverage.blackbox = blackboxUp || { status: 'unknown', reason: 'Blackbox exporter status unknown' };

    if (Array.isArray(fsSeries) && fsSeries.length > 0) {
        coverage.root_filesystem = { status: 'ok', reason: 'node_filesystem_* series available for mountpoint "/"' };
    } else if (coreValues.disk !== null && coreValues.disk !== undefined) {
        coverage.root_filesystem = { status: 'ok', reason: 'Root filesystem usage metric available' };
    } else if (coverage.node_exporter.status === 'ok') {
        coverage.root_filesystem = { status: 'missing', reason: 'No node_filesystem_* series for mountpoint "/" (can occur when node-exporter cannot read host mountinfo, e.g. userns without pid:host)' };
    } else {
        coverage.root_filesystem = { status: 'unknown', reason: 'Root filesystem metrics unavailable (node exporter not healthy)' };
    }

    coverage.backup_metrics = state.lastExporterStatus.backup
        ? { status: 'ok', reason: 'Backup/restic textfile metrics publishing' }
        : { status: 'missing', reason: 'No backup/restic metrics (exporter not scheduled, not run, or no output)' };
    coverage.agent_metrics = state.lastExporterStatus.agent
        ? { status: 'ok', reason: 'Spectre agent/security metrics publishing' }
        : { status: 'missing', reason: 'No spectre agent/security metrics (agent unavailable or not exporting)' };
    coverage.baseline_metrics = state.lastExporterStatus.baseline
        ? { status: 'ok', reason: 'Security baseline textfile metrics publishing' }
        : { status: 'missing', reason: 'No security baseline metrics (baseline exporter not run or no output)' };

    state.coverageStatus = coverage;
}

async function updateContainerStatus() {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent('container_last_seen')}`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        if (data.status !== 'success') throw new Error('Invalid container response');
        const now = Math.floor(Date.now() / 1000);
        const windowSeconds = 86400;
        const seen = new Map();
        let hasUnlabeledRecent = false;
        for (const series of (data.data?.result || [])) {
            const lastSeen = Number(series.value?.[1]);
            if (!Number.isFinite(lastSeen) || lastSeen < now - windowSeconds) continue;
            const m = series.metric || {};
            const rawName = m.name || m.container_name || m.container || m.container_label_com_docker_compose_service || m['container_label_com.docker.compose.service'] || '';
            const id = String(m.id || '');
            const name = String(rawName).trim();
            const isRootOrSystem = !name || name === '/' || name === 'POD' || id === '/' || /^\/(docker|kubepods|system\.slice)?$/.test(id);
            if (isRootOrSystem) { hasUnlabeledRecent = true; continue; }
            seen.set(name, Math.max(seen.get(name) || 0, lastSeen));
        }
        const containerNames = [...seen.keys()].sort();
        const containerStatus = document.getElementById('containerStatus');
        const hasData = containerNames.length > 0;
        state.currentContainerNames = containerNames;
        state.lastContainerMeta = { hasUnlabeledRecent };
        state.lastContainerSignature = `${containerNames.join('|')}|${hasUnlabeledRecent ? 'u' : ''}`;
        state.lastRenderedContainerKey = null;
        renderContainers();
        if (hasData) {
            const groupCount = new Set(containerNames.map(n => (n || '').split(/[-_]/)[0] || n || 'other')).size;
            containerStatus.textContent = `${containerNames.length} running · ${groupCount} group${groupCount === 1 ? '' : 's'}`;
            containerStatus.className = 'badge badge-success';
        } else {
            containerStatus.textContent = hasUnlabeledRecent ? 'Labels missing' : 'No data';
            containerStatus.className = hasUnlabeledRecent ? 'badge badge-warning' : 'badge';
        }
        clearCardError('containersCard'); setCardUpdated('containersCard');
    } catch (error) {
        console.error('Error fetching container status:', error);
        state.lastContainerSignature = null;
        state.lastRenderedContainerKey = null;
        state.currentContainerNames = [];
        state.lastContainerMeta = { hasUnlabeledRecent: false };
        setCardError('containersCard', 'Container data unavailable');
        const grid = document.getElementById('containersGrid');
        if (grid) grid.innerHTML = '<div class="no-alerts no-alerts--degraded"><i class="fas fa-triangle-exclamation" aria-hidden="true"></i><span><strong>Container data unavailable.</strong> Unable to fetch recent container status.</span></div>';
        const containerStatus = document.getElementById('containerStatus');
        if (containerStatus) { containerStatus.textContent = 'No data'; containerStatus.className = 'badge'; }
    }
}

async function checkPrometheusConnection() {
    const statusIndicator = document.getElementById('systemStatus');
    const statusText = document.getElementById('systemStatusText');
    const prometheusStatus = document.getElementById('prometheusStatus');
    const setPrometheusStatus = (text, color) => { if (!prometheusStatus) return; prometheusStatus.textContent = text; prometheusStatus.style.color = color; };
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/status/buildinfo`);
        if (response.ok) {
            setPrometheusStatus('Connected', '#10b981');
            if (statusIndicator) { statusIndicator.classList.remove('offline'); statusIndicator.classList.add('online'); }
            if (statusText) statusText.textContent = 'All Systems Operational';
            if (state.lastPrometheusConnected === false) showToast('Prometheus reconnected', 'success');
            state.lastPrometheusConnected = true;
        } else {
            setPrometheusStatus('Disconnected', '#ef4444');
            if (statusIndicator) { statusIndicator.classList.remove('online'); statusIndicator.classList.add('offline'); }
            if (statusText) statusText.textContent = 'Prometheus Disconnected';
            if (state.lastPrometheusConnected !== false) showToast('Prometheus disconnected', 'error');
            state.lastPrometheusConnected = false;
        }
    } catch (error) {
        setPrometheusStatus('Disconnected', '#ef4444');
        if (statusIndicator) { statusIndicator.classList.remove('online'); statusIndicator.classList.add('offline'); }
        if (statusText) statusText.textContent = 'Prometheus Unreachable';
        if (state.lastPrometheusConnected !== false) showToast('Prometheus unreachable', 'error');
        state.lastPrometheusConnected = false;
    }
}

export async function fetchAllMetrics(opts = {}) {
    const refreshChart = opts instanceof Event ? true : !!(opts && opts.refreshChart);
    if (state.isRefreshing) return;
    setRefreshing(true);

    const forceSlow = refreshChart;
    const slowIsCached = !forceSlow && state.slowMetricsCache && Date.now() - state.slowMetricsCacheAt < SLOW_METRICS_REFRESH_MS;
    const activeRange = document.querySelector('.chart-controls .btn.active')?.dataset.range || '1h';
    const activePage = document.body.dataset.activePage || 'overview';
    const chartVisible = activePage === 'overview' || activePage === 'trends';
    const alertsVisible = activePage === 'overview' || activePage === 'alerts';
    const containersVisible = activePage === 'overview' || activePage === 'containers';
    const chartNow = Date.now();
    const shouldRefreshChart = chartVisible && (refreshChart || chartNow - state.lastChartRefreshAt >= CHART_AUTO_REFRESH_MS);
    if (shouldRefreshChart) state.lastChartRefreshAt = chartNow;

    const cardIds = ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'alertsCard', 'containersCard', 'chartCard', 'backupCard', 'securityCard'];
    const loadingCardIds = ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard'];
    if (alertsVisible) loadingCardIds.push('alertsCard');
    if (containersVisible) loadingCardIds.push('containersCard');
    if (!slowIsCached) loadingCardIds.push('backupCard', 'securityCard');
    if (shouldRefreshChart) loadingCardIds.push('chartCard');
    cardIds.forEach(id => clearCardError(id));
    loadingCardIds.forEach(id => setCardLoading(id, true));

    try {
        const corePromise = Promise.all([
            queryPrometheus('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))'),
            queryPrometheus('100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'),
            queryPrometheus('100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))'),
            queryPrometheus('sum(rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*"}[5m]))'),
            queryPrometheus('sum(rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*"}[5m]))'),
            queryPrometheus('node_load1'),
            queryPrometheus('node_boot_time_seconds'),
            queryPrometheus('node_procs_running'),
            queryPrometheus('avg(node_hwmon_temp_celsius)'),
            queryPrometheus('avg(node_thermal_zone_temp)')
        ]);
        const slowPromise = slowIsCached ? Promise.resolve(state.slowMetricsCache) : Promise.all([
            queryPrometheus('backup_last_success_timestamp'),
            queryPrometheus('backup_health_check_ok'),
            queryPrometheus('backup_health_check_timestamp'),
            queryPrometheus('backup_repo_size_bytes'),
            queryPrometheus('backup_repo_fs_free_bytes'),
            queryPrometheus('restic_last_success_timestamp'),
            queryPrometheus('restic_last_offsite_success_timestamp'),
            queryPrometheus('restic_health_ok'),
            queryPrometheus('restic_health_timestamp'),
            queryPrometheus('restic_verify_ok'),
            queryPrometheus('restic_verify_timestamp'),
            queryPrometheus('spectre_agent_up'),
            queryPrometheus('spectre_security_ever_scanned'),
            queryPrometheus('security_last_scan_timestamp'),
            queryPrometheus('security_findings_unresolved'),
            queryPrometheus('security_findings_unresolved_by_severity{severity="critical"}'),
            queryPrometheus('security_findings_unresolved_by_severity{severity="high"}'),
            queryPrometheus('security_findings_unresolved_by_severity{severity="medium"}'),
            queryPrometheus('security_findings_unresolved_by_severity{severity="low"}'),
            queryPrometheus('max(spectre_security_baseline_exporter_up)'),
            queryPrometheus('max(spectre_security_baseline_never_run)'),
            queryPrometheus('max(spectre_security_baseline_last_run_timestamp_seconds)'),
            queryPrometheus('max(spectre_security_baseline_stale)'),
            queryPrometheus('max(spectre_security_baseline_opa_check_ok)'),
            queryPrometheus('max(spectre_security_baseline_drift_detected)'),
            queryPrometheus('max(spectre_security_baseline_trivy_fs_ok)'),
            queryPrometheus('max(spectre_security_baseline_gitleaks_ok)'),
            queryPrometheusFirst('spectre_agent_up_reason')
        ]).then((slowResults) => {
            const [backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs, spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale, baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk, agentReasonResult] = slowResults;
            state.slowMetricsCache = { backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs, spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale, baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk, agentReasonResult };
            state.slowMetricsCacheAt = Date.now();
            return state.slowMetricsCache;
        });
        const alertsPromise = alertsVisible ? checkAlerts() : Promise.resolve();
        const containersPromise = containersVisible ? updateContainerStatus() : Promise.resolve();
        const chartPromise = shouldRefreshChart ? updateChart(activeRange) : Promise.resolve();

        const coreResults = await corePromise;
        const [cpu, mem, disk, netIn, netOut, load1, bootTime, processes, tempHwmon, tempThermal] = coreResults;
        const temp = tempHwmon ?? tempThermal;
        const coreAllNull = [cpu, mem, disk, netIn, netOut, load1, bootTime].every(v => v === null);
        if (coreAllNull) {
            showToast('Prometheus unreachable — showing no data', 'error');
            ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard'].forEach(id => setCardError(id, 'No data from Prometheus'));
        } else {
            runCardUpdate('cpuCard', () => updateCPUMetrics(cpu));
            runCardUpdate('memoryCard', () => updateMemoryMetrics(mem));
            runCardUpdate('diskCard', () => updateDiskMetrics(disk));
            runCardUpdate('networkCard', () => updateNetworkMetrics(netIn, netOut));
            runCardUpdate('healthCard', () => updateSystemHealth(load1, bootTime, processes, temp));
            if (cpu === null) setCardError('cpuCard', 'CPU data unavailable');
            if (mem === null) setCardError('memoryCard', 'Memory data unavailable');
            if (disk === null) setCardError('diskCard', 'Disk data unavailable');
            if (netIn === null && netOut === null) setCardError('networkCard', 'Network data unavailable');
        }
        ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard'].forEach(id => setCardLoading(id, false));

        const slow = await slowPromise;
        const slowFetched = !slowIsCached;
        const { backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs, spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale, baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk, agentReasonResult } = slow;
        const baseline = { exporterUp: baselineExporterUp, neverRun: baselineNeverRun, lastRun: baselineLastRun, stale: baselineStale, opaOk: baselineOpaOk, drift: baselineDrift, trivyFsOk: baselineTrivyFsOk, gitleaksOk: baselineGitleaksOk };
        const slowValues = [backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs, spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale, baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk];
        const executed = coreResults.length + (slowFetched ? 28 : 0);
        const executedValues = slowFetched ? [...coreResults, ...slowValues] : coreResults;
        const succeeded = executedValues.filter(v => v !== null).length + (slowFetched && agentReasonResult ? 1 : 0);
        state.lastQueryStats = { total: executed, succeeded, failed: executed - succeeded };
        state.lastExporterStatus = {
            backup: [backupLastSuccess, backupHealthOk, resticLastSuccess, resticHealthOk, resticHealthTs].some(v => v !== null),
            agent: spectreUp !== null,
            baseline: baselineExporterUp === 1
        };
        const agentReason = agentReasonResult?.metric?.reason || null;
        runCardUpdate('backupCard', () => updateBackupStatus(backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs));
        runCardUpdate('securityCard', () => updateSecurityStatus(spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, agentReason, baseline));
        ['backupCard', 'securityCard'].forEach(id => setCardLoading(id, false));
        await Promise.allSettled([alertsPromise, containersPromise, chartPromise]);
        const settleCardIds = [];
        if (alertsVisible) settleCardIds.push('alertsCard');
        if (containersVisible) settleCardIds.push('containersCard');
        if (shouldRefreshChart) settleCardIds.push('chartCard');
        settleCardIds.forEach(id => setCardLoading(id, false));
        await updateCoverageStatus({ disk });
        renderContainers();
        updateLastRefreshed();
        updateDiagnostics();
    } catch (err) {
        console.error('Fetch error:', err);
        showToast('Failed to refresh metrics', 'error');
        ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'backupCard', 'securityCard'].forEach(id => setCardError(id, 'Fetch failed'));
        state.lastQueryStats = { total: 0, succeeded: 0, failed: 0 };
        updateDiagnostics();
    } finally {
        cardIds.forEach(id => setCardLoading(id, false));
        setRefreshing(false);
    }
}

async function exportSnapshot() {
    const snapshot = {
        exportedAt: new Date().toISOString(),
        prometheusConnected: document.getElementById('prometheusStatus')?.textContent || null,
        systemStatus: document.getElementById('systemStatusText')?.textContent || null,
        metrics: {
            cpu: document.getElementById('cpuUsage')?.textContent,
            memory: document.getElementById('memoryUsage')?.textContent,
            disk: document.getElementById('diskUsage')?.textContent,
            network: document.getElementById('networkIO')?.textContent,
            load: document.getElementById('systemLoad')?.textContent,
            uptime: document.getElementById('uptime')?.textContent,
            processes: document.getElementById('processes')?.textContent,
            temperature: document.getElementById('temperature')?.textContent
        },
        backup: {
            status: document.getElementById('backupStatus')?.textContent,
            lastBackup: document.getElementById('lastBackup')?.textContent,
            health: document.getElementById('backupHealth')?.textContent,
            resticHealth: document.getElementById('resticHealth')?.textContent,
            sizeFree: document.getElementById('backupSize')?.textContent,
            resticOffsite: document.getElementById('resticOffsite')?.textContent,
            resticVerify: document.getElementById('resticVerify')?.textContent
        },
        security: {
            status: document.getElementById('securityStatus')?.textContent,
            agent: document.getElementById('agentStatusDetail')?.textContent,
            lastScan: document.getElementById('lastSecurityScan')?.textContent,
            unresolved: document.getElementById('vulnerabilities')?.textContent,
            severity: document.getElementById('severityBreakdown')?.textContent
        },
        alerts: {
            count: document.getElementById('alertCount')?.textContent,
            active: state.currentAlerts.map(a => ({ name: a.labels?.alertname, severity: a.labels?.severity, description: a.annotations?.description || a.annotations?.summary }))
        },
        diagnostics: {
            queryHealth: document.getElementById('queryHealth')?.textContent,
            backupExporter: document.getElementById('backupExporterStatus')?.textContent,
            agentMetrics: document.getElementById('agentMetricsStatus')?.textContent,
            baselineExporter: document.getElementById('baselineExporterStatus')?.textContent
        }
    };
    const text = JSON.stringify(snapshot, null, 2);
    try {
        await navigator.clipboard.writeText(text);
        showToast('Snapshot copied to clipboard (JSON)', 'success');
    } catch (e) {
        const blob = new Blob([text], { type: 'application/json' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `spectre-dashboard-snapshot-${Date.now()}.json`;
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(url);
        showToast('Snapshot downloaded (clipboard unavailable)', 'info');
    }
}

function initDashboardShell() {
    const links = Array.from(document.querySelectorAll('.nav-item[data-page]'));
    if (!links.length) return;
    const pageSections = Array.from(document.querySelectorAll('[data-show-pages]'));
    const shell = document.querySelector('.app-shell');
    const main = document.querySelector('.app-main');
    const headingIcon = document.querySelector('#pageHeading i');
    const headingText = document.getElementById('pageHeadingText');
    const sidebarBtn = document.getElementById('sidebarToggle');
    const sidebarBackdrop = document.getElementById('sidebarBackdrop');
    const validPages = new Set(links.map(a => a.dataset.page));
    const legacyPageMap = {
        '': 'overview', '#main-content': 'overview', '#page-overview': 'overview', '#page-health': 'health', '#healthCard': 'health',
        '#page-alerts': 'alerts', '#alertsCard': 'alerts', '#page-containers': 'containers', '#containersCard': 'containers',
        '#page-trends': 'trends', '#chartCard': 'trends', '#page-security': 'security', '#securityCard': 'security',
        '#page-backup': 'backup', '#backupCard': 'backup', '#page-reports': 'reports', '#reportsCard': 'reports'
    };
    const isMobileSidebar = () => !!(window.matchMedia && window.matchMedia('(max-width: 980px)').matches);
    const syncSidebarState = () => {
        if (!shell) return;
        const collapsed = shell.classList.contains('sidebar-collapsed');
        if (sidebarBtn) {
            sidebarBtn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
            sidebarBtn.setAttribute('aria-label', collapsed ? 'Open navigation' : 'Close navigation');
        }
        if (sidebarBackdrop) sidebarBackdrop.hidden = !isMobileSidebar() || collapsed;
    };
    const closeSidebarIfMobile = () => { if (shell && isMobileSidebar()) { shell.classList.add('sidebar-collapsed'); syncSidebarState(); } };
    const pageFromHash = (hash) => {
        if (!hash) return 'overview';
        if (legacyPageMap[hash]) return legacyPageMap[hash];
        const byHref = links.find(a => a.getAttribute('href') === hash);
        return byHref?.dataset.page || 'overview';
    };
    const setPage = (page, opts = {}) => {
        const activePage = validPages.has(page) ? page : 'overview';
        const activeLink = links.find(a => a.dataset.page === activePage) || links[0];
        links.forEach(a => {
            const active = a === activeLink;
            a.classList.toggle('active', active);
            if (active) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
        });
        pageSections.forEach(el => {
            const pages = (el.getAttribute('data-show-pages') || '').split(/\s+/).filter(Boolean);
            const show = pages.includes(activePage);
            el.setAttribute('data-page-hidden', show ? 'false' : 'true');
            el.setAttribute('aria-hidden', show ? 'false' : 'true');
        });
        document.body.dataset.activePage = activePage;
        if (shell) shell.classList.toggle('dashboard-page--focused', activePage !== 'overview');
        if (headingText && activeLink?.dataset.pageTitle) headingText.textContent = activeLink.dataset.pageTitle;
        if (headingIcon && activeLink?.dataset.pageIcon) headingIcon.className = `fas ${activeLink.dataset.pageIcon}`;
        if (main) main.scrollTo({ top: 0, behavior: opts.smooth ? 'smooth' : 'auto' });
        if (activePage === 'overview' || activePage === 'trends') {
            requestAnimationFrame(() => { if (state.chart && typeof state.chart.resize === 'function') state.chart.resize(); });
            if (state.chart) {
                const range = document.querySelector('.chart-controls .btn.active')?.dataset.range || '1h';
                const stale = !state.lastChartRefreshAt || (Date.now() - state.lastChartRefreshAt) >= CHART_AUTO_REFRESH_MS;
                if (stale) updateChart(range).catch(() => {});
            }
        }
        // When entering alerts/containers pages, refresh soon if data hasn't been loaded for them recently.
        if ((activePage === 'alerts' || activePage === 'containers') && !state.isRefreshing) {
            fetchAllMetrics({ refreshChart: false }).catch(() => {});
        }
        closeSidebarIfMobile();
    };

    links.forEach(a => a.addEventListener('click', (e) => {
        e.preventDefault();
        const page = a.dataset.page || 'overview';
        const hash = `#page-${page}`;
        if (location.hash !== hash) history.pushState(null, '', hash);
        setPage(page, { smooth: false });
    }));
    window.addEventListener('hashchange', () => setPage(pageFromHash(location.hash), { smooth: false }));
    window.addEventListener('popstate', () => setPage(pageFromHash(location.hash), { smooth: false }));
    if (sidebarBtn && shell) {
        sidebarBtn.addEventListener('click', () => {
            shell.classList.toggle('sidebar-collapsed');
            syncSidebarState();
            if (isMobileSidebar() && !shell.classList.contains('sidebar-collapsed')) {
                const firstNav = document.querySelector('.nav-item[data-page]');
                if (firstNav && typeof firstNav.focus === 'function') firstNav.focus();
            }
        });
        if (isMobileSidebar()) shell.classList.add('sidebar-collapsed');
        syncSidebarState();
        const mobileSidebarMq = window.matchMedia ? window.matchMedia('(max-width: 980px)') : null;
        const handleSidebarBreakpoint = () => {
            if (!shell) return;
            if (!isMobileSidebar()) shell.classList.remove('sidebar-collapsed');
            else shell.classList.add('sidebar-collapsed');
            syncSidebarState();
        };
        if (mobileSidebarMq) {
            if (typeof mobileSidebarMq.addEventListener === 'function') mobileSidebarMq.addEventListener('change', handleSidebarBreakpoint);
            else if (typeof mobileSidebarMq.addListener === 'function') mobileSidebarMq.addListener(handleSidebarBreakpoint);
        }
    }
    if (sidebarBackdrop && shell) {
        sidebarBackdrop.addEventListener('click', () => {
            shell.classList.add('sidebar-collapsed');
            syncSidebarState();
            if (sidebarBtn && typeof sidebarBtn.focus === 'function') sidebarBtn.focus();
        });
    }
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && shell && isMobileSidebar() && !shell.classList.contains('sidebar-collapsed')) {
            shell.classList.add('sidebar-collapsed');
            syncSidebarState();
            if (sidebarBtn && typeof sidebarBtn.focus === 'function') sidebarBtn.focus();
        }
    });
    setPage(pageFromHash(location.hash), { smooth: false });
}

function applyReadOnlyMode() {
    if (!READ_ONLY) return;
    document.body.classList.add('read-only-mode');
    const banner = document.getElementById('readOnlyBanner');
    if (banner) {
        banner.hidden = false;
        banner.setAttribute('aria-hidden', 'false');
    }
    document.querySelectorAll('[data-dashboard-action="backup"], [data-dashboard-action="maintenance"], [data-dashboard-action="security-scan"]').forEach((btn) => {
        btn.disabled = true;
        btn.setAttribute('aria-disabled', 'true');
        btn.title = 'Disabled in read-only mode';
    });
    const quickActions = document.querySelector('.quick-actions');
    if (quickActions) quickActions.setAttribute('data-read-only', 'true');
}

export function initDashboard() {
    initializeTheme();
    loadRefreshInterval();
    restorePersistedUiState();
    initExternalLinks();
    initActionsApi();
    initializeChart();
    applyReadOnlyMode();
    fetchAllMetrics({ refreshChart: true });
    checkPrometheusConnection();
    updateTimestamp();
    setInterval(updateTimestamp, 1000);
    applyRefreshInterval();

    document.addEventListener('keydown', handleKeyboard);
    startRefreshCountdown();
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
            if (state.refreshTimerId) { clearInterval(state.refreshTimerId); state.refreshTimerId = null; }
        } else {
            applyRefreshInterval();
            fetchAllMetrics();
            checkPrometheusConnection();
        }
    });

    document.getElementById('refreshBtn')?.addEventListener('click', fetchAllMetrics);
    document.getElementById('themeToggle')?.addEventListener('click', toggleDarkMode);
    document.getElementById('exportBtn')?.addEventListener('click', exportSnapshot);
    document.getElementById('chartExportCsv')?.addEventListener('click', exportChartCSV);
    document.querySelectorAll('[data-dashboard-action]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const action = btn.dataset.dashboardAction;
            if (action === 'backup') triggerAction('backup', 'Run backup');
            else if (action === 'maintenance') triggerAction('maintenance', 'Run maintenance');
            else if (action === 'security-scan') triggerAction('security-scan', 'Security scan');
            else if (action === 'logs') { showToast('Opening Grafana logs...', 'info'); window.open(externalUrl('grafana', '/'), '_blank'); }
        });
    });
    document.getElementById('refreshInterval')?.addEventListener('change', (e) => {
        state.refreshIntervalMs = parseInt(e.target.value, 10) || 0;
        localStorage.setItem('spectre-refresh-interval', String(state.refreshIntervalMs));
        applyRefreshInterval();
        showToast(state.refreshIntervalMs > 0 ? `Auto-refresh set to ${e.target.selectedOptions[0]?.text || 'custom'}` : 'Auto-refresh disabled', 'info');
    });
    document.querySelectorAll('.chart-controls .btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const target = e.currentTarget;
            document.querySelectorAll('.chart-controls .btn').forEach(b => { b.classList.remove('active'); b.setAttribute('aria-pressed', 'false'); });
            target.classList.add('active');
            target.setAttribute('aria-pressed', 'true');
            const range = target.dataset.range || '1h';
            localStorage.setItem('spectre-chart-range', range);
            updateChart(range);
        });
    });
    document.querySelectorAll('#alertFilters .btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const target = e.currentTarget;
            document.querySelectorAll('#alertFilters .btn').forEach(b => { b.classList.remove('active'); b.setAttribute('aria-pressed', 'false'); });
            target.classList.add('active');
            target.setAttribute('aria-pressed', 'true');
            state.activeAlertFilter = target.dataset.severity || 'all';
            localStorage.setItem('spectre-alert-severity-filter', state.activeAlertFilter);
            renderAlerts();
        });
    });
    document.getElementById('containerFilter')?.addEventListener('input', () => renderContainers());
    document.querySelectorAll('[data-help-close]').forEach((el) => el.addEventListener('click', hideHelpDialog));

    initDashboardShell();
}
