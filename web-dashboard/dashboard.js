// Dashboard JavaScript
// Requests go to the nginx in this compose file, which proxies /api/ to
// Prometheus, so the default is same-origin and empty. It used to default to
// `${location.protocol}//${location.hostname}:9090`, a different origin from the
// page, and Prometheus sends no Access-Control-Allow-Origin, so every fetch was
// blocked and the dashboard rendered empty.
// Override with ?prometheus=https://prometheus.example.com to read from a
// Prometheus reachable from the browser rather than through this proxy.
const PROMETHEUS_URL = new URLSearchParams(location.search).get('prometheus') || '';
// Defaults to same-origin nginx proxy (/actions -> dashboard-actions service).
// Override with ?actionsBase=https://... or set to "off" to disable.
const ACTIONS_BASE_PARAM = new URLSearchParams(location.search).get('actionsBase');
const ACTIONS_BASE = ACTIONS_BASE_PARAM === 'off' ? '' : (ACTIONS_BASE_PARAM || '/actions');

// External backend UIs. Default to same-origin nginx proxy paths so dashboard
// links/endpoints reach their backends via the dashboard origin
// (web-dashboard/nginx.conf: /grafana/, /prometheus/, /alertmanager/).
// Backends serve under matching route prefixes (docker-compose.monitoring.yml).
// Overrides: full base URL via ?grafanaUrl=|?prometheusUrl=|?alertmanagerUrl=;
// or direct host:port (with subpath) via ?grafanaPort=|?prometheusPort=|?alertmanagerPort=.
const _qs = new URLSearchParams(location.search);
const _host = location.hostname || 'localhost';
const _proto = location.protocol === 'https:' ? 'https:' : 'http:';
function _backendUrl(urlKey, portKey, defaultPort, proxyBase) {
    const full = _qs.get(urlKey);
    if (full) return full.replace(/\/$/, '');
    if (_qs.get(portKey)) {
        // Explicit direct-port override; backends serve under their subpath prefix.
        return `${_proto}//${_host}:${_qs.get(portKey)}${proxyBase}`;
    }
    return proxyBase; // same-origin proxied (default)
}
const EXTERNAL_BACKENDS = {
    grafana: _backendUrl('grafanaUrl', 'grafanaPort', '3002', '/grafana'),
    prometheus: _backendUrl('prometheusUrl', 'prometheusPort', '9090', '/prometheus'),
    alertmanager: _backendUrl('alertmanagerUrl', 'alertmanagerPort', '9093', '/alertmanager'),
};
function externalUrl(backend, path = '/') {
    const base = EXTERNAL_BACKENDS[backend];
    if (!base) return '#';
    const p = path.startsWith('/') ? path : `/${path}`;
    return `${base}${p}`;
}
function extBase(key) {
    const v = EXTERNAL_BACKENDS && EXTERNAL_BACKENDS[key] ? String(EXTERNAL_BACKENDS[key]) : '';
    return v.replace(/\/$/, '');
}
function initExternalLinks() {
    document.querySelectorAll('a[data-ext]').forEach((a) => {
        const backend = a.getAttribute('data-ext');
        const path = a.getAttribute('data-ext-path') || '/';
        const url = externalUrl(backend, path);
        if (url && url !== '#') a.setAttribute('href', url);
    });
    const loc = document.getElementById('dashboardLocation');
    if (loc) loc.textContent = `Prometheus-connected static dashboard (${location.host || 'localhost:8081'})`;
}

const DEFAULT_REFRESH_INTERVAL = 30000; // 30 seconds

let refreshIntervalMs = DEFAULT_REFRESH_INTERVAL;
let refreshTimerId = null;
let chart = null;
let chartRequestToken = 0; // Monotonic token to discard stale updateChart responses
let isRefreshing = false;
let lastPrometheusConnected = null;
let currentAlerts = [];
let activeAlertFilter = 'all';
let lastQueryStats = { total: 0, succeeded: 0, failed: 0 };
let lastExporterStatus = { backup: false, agent: false, baseline: false };
let lastChartRefreshAt = 0;
let slowMetricsCache = null;
let slowMetricsCacheAt = 0;
let lastContainerSignature = null;
let currentContainerNames = [];
let lastContainerMeta = { hasUnlabeledRecent: false };

const FETCH_TIMEOUT_MS = 12000;
const CHART_AUTO_REFRESH_MS = 5 * 60 * 1000;
const SLOW_METRICS_REFRESH_MS = 5 * 60 * 1000;

async function fetchWithTimeout(url, options = {}, timeoutMs = FETCH_TIMEOUT_MS) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    try {
        return await fetch(url, { ...options, signal: controller.signal });
    } finally {
        clearTimeout(timeoutId);
    }
}

// UI helpers: loading states, error states, and toasts
function setCardLoading(cardId, isLoading) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.toggle('card--loading', isLoading);
    card.setAttribute('aria-busy', isLoading ? 'true' : 'false');
}

function setCardError(cardId, message) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.remove('card--loading');
    card.setAttribute('aria-busy', 'false');
    card.classList.add('card--error');
    let errorEl = card.querySelector('.error-message');
    if (!errorEl) {
        errorEl = document.createElement('div');
        errorEl.className = 'error-message';
        errorEl.setAttribute('role', 'alert');
        const body = card.querySelector('.card-body') || card;
        body.appendChild(errorEl);
    }
    errorEl.innerHTML = `<i class="fas fa-exclamation-circle" aria-hidden="true"></i> ${escapeHtml(message)}`;
}

function clearCardError(cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.remove('card--error', 'card--loading');
    card.setAttribute('aria-busy', 'false');
    const errorEl = card.querySelector('.error-message');
    if (errorEl) errorEl.remove();
}

function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast toast--${type}`;
    toast.setAttribute('role', type === 'error' ? 'alert' : 'status');
    const iconClass = type === 'success' ? 'fa-check-circle' : type === 'error' ? 'fa-exclamation-triangle' : 'fa-info-circle';
    toast.innerHTML = `<i class="fas ${iconClass}" aria-hidden="true"></i><span class="toast-message">${escapeHtml(message)}</span>`;
    container.appendChild(toast);
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    setTimeout(() => {
        if (!reduceMotion) {
            toast.style.opacity = '0';
            toast.style.transform = 'translateX(120%)';
            setTimeout(() => toast.remove(), 300);
        } else {
            toast.remove();
        }
    }, 4000);
}

function setRefreshing(refreshing) {
    isRefreshing = refreshing;
    const btn = document.getElementById('refreshBtn');
    if (!btn) return;
    btn.disabled = refreshing;
    btn.setAttribute('aria-busy', refreshing ? 'true' : 'false');
    btn.classList.toggle('btn--loading', refreshing);
    if (refreshing) {
        stopRefreshCountdown();
    } else {
        startRefreshCountdown();
    }
}

let countdownIntervalId = null;
let countdownSeconds = 0;

function startRefreshCountdown() {
    stopRefreshCountdown();
    if (!refreshIntervalMs || refreshIntervalMs <= 0) return;
    countdownSeconds = Math.floor(refreshIntervalMs / 1000);
    updateCountdown();
    countdownIntervalId = setInterval(() => {
        countdownSeconds--;
        if (countdownSeconds <= 0) {
            countdownSeconds = Math.floor(refreshIntervalMs / 1000);
        }
        updateCountdown();
    }, 1000);
}

function stopRefreshCountdown() {
    if (countdownIntervalId) {
        clearInterval(countdownIntervalId);
        countdownIntervalId = null;
    }
}

function updateCountdown() {
    const el = document.getElementById('refreshCountdown');
    if (!el) return;
    if (!refreshIntervalMs || refreshIntervalMs <= 0) {
        el.style.display = 'none';
        return;
    }
    el.style.display = 'inline';
    el.textContent = `Next refresh in ${countdownSeconds}s`;
}

function showHelpDialog() {
    const dialog = document.getElementById('keyboardHelp');
    if (dialog) dialog.style.display = 'flex';
}

function hideHelpDialog() {
    const dialog = document.getElementById('keyboardHelp');
    if (dialog) dialog.style.display = 'none';
}

function handleKeyboard(e) {
    // Don't trigger shortcuts when typing in an input/textarea
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.isContentEditable) return;

    if (e.key === 'r' || e.key === 'R') {
        e.preventDefault();
        fetchAllMetrics();
    } else if (e.key === '?') {
        e.preventDefault();
        showHelpDialog();
    } else if (e.key === 'Escape') {
        hideHelpDialog();
        // Dismiss toasts
        const container = document.getElementById('toast-container');
        if (container) {
            const toasts = container.querySelectorAll('.toast');
            toasts.forEach(t => t.remove());
        }
    }
}

function loadRefreshInterval() {
    const saved = localStorage.getItem('spectre-refresh-interval');
    const ms = saved !== null ? parseInt(saved, 10) : DEFAULT_REFRESH_INTERVAL;
    refreshIntervalMs = isNaN(ms) ? DEFAULT_REFRESH_INTERVAL : ms;
    const select = document.getElementById('refreshInterval');
    if (select) {
        select.value = String(refreshIntervalMs);
        if (!select.value) select.value = String(DEFAULT_REFRESH_INTERVAL);
    }
}

function applyRefreshInterval() {
    if (refreshTimerId) {
        clearInterval(refreshTimerId);
        refreshTimerId = null;
    }
    if (refreshIntervalMs > 0 && !document.hidden) {
        refreshTimerId = setInterval(fetchAllMetrics, refreshIntervalMs);
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
            activeAlertFilter = savedSeverity;
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

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    initializeTheme();
    loadRefreshInterval();
    restorePersistedUiState();
    initializeDashboard();
    updateTimestamp();
    setInterval(updateTimestamp, 1000);
    applyRefreshInterval();

    // Keyboard shortcuts
    document.addEventListener('keydown', (e) => {
        handleKeyboard(e);
    });

    startRefreshCountdown();
    // visible again. Background tabs otherwise keep querying Prometheus forever.
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
            if (refreshTimerId) {
                clearInterval(refreshTimerId);
                refreshTimerId = null;
            }
        } else {
            applyRefreshInterval();
            fetchAllMetrics();
        }
    });
    
    // Event listeners
    document.getElementById('refreshBtn').addEventListener('click', fetchAllMetrics);
    document.getElementById('themeToggle').addEventListener('click', toggleDarkMode);
    const exportBtn = document.getElementById('exportBtn');
    if (exportBtn) exportBtn.addEventListener('click', exportSnapshot);
    const exportCsvBtn = document.getElementById('chartExportCsv');
    if (exportCsvBtn) exportCsvBtn.addEventListener('click', exportChartCSV);
    document.querySelectorAll('[data-dashboard-action]').forEach((btn) => {
        btn.addEventListener('click', () => {
            const action = btn.dataset.dashboardAction;
            if (action === 'backup') runBackup();
            else if (action === 'maintenance') runMaintenance();
            else if (action === 'security-scan') runSecurityScan();
            else if (action === 'logs') viewLogs();
        });
    });
    document.getElementById('refreshInterval').addEventListener('change', (e) => {
        refreshIntervalMs = parseInt(e.target.value, 10) || 0;
        localStorage.setItem('spectre-refresh-interval', String(refreshIntervalMs));
        applyRefreshInterval();
        showToast(refreshIntervalMs > 0 ? `Auto-refresh set to ${e.target.selectedOptions[0]?.text || 'custom'}` : 'Auto-refresh disabled', 'info');
    });
    
    // Chart range buttons
    document.querySelectorAll('.chart-controls .btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const target = e.currentTarget;
            document.querySelectorAll('.chart-controls .btn').forEach(b => {
                b.classList.remove('active');
                b.setAttribute('aria-pressed', 'false');
            });
            target.classList.add('active');
            target.setAttribute('aria-pressed', 'true');
            const range = target.dataset.range || '1h';
            localStorage.setItem('spectre-chart-range', range);
            updateChart(range);
        });
    });

    // Alert severity filters
    document.querySelectorAll('#alertFilters .btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const target = e.currentTarget;
            document.querySelectorAll('#alertFilters .btn').forEach(b => {
                b.classList.remove('active');
                b.setAttribute('aria-pressed', 'false');
            });
            target.classList.add('active');
            target.setAttribute('aria-pressed', 'true');
            activeAlertFilter = target.dataset.severity || 'all';
            localStorage.setItem('spectre-alert-severity-filter', activeAlertFilter);
            renderAlerts();
        });
    });

    const containerFilter = document.getElementById('containerFilter');
    if (containerFilter) {
        containerFilter.addEventListener('input', () => renderContainers());
    }
});

function initializeTheme() {
    const html = document.documentElement;
    const savedTheme = localStorage.getItem('spectre-theme');
    const toggle = document.getElementById('themeToggle');
    const icon = toggle.querySelector('i');
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
    const icon = toggle.querySelector('i');

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

function getChartTheme() {
    const isDark = document.documentElement.classList.contains('dark');
    return {
        gridColor: isDark ? 'rgba(148, 163, 184, 0.15)' : 'rgba(0,0,0,0.05)',
        tickColor: isDark ? '#94a3b8' : '#666',
        legendColor: isDark ? '#e2e8f0' : '#333'
    };
}

function applyChartTheme() {
    if (!chart) return;
    const theme = getChartTheme();
    chart.options.scales.x.grid.color = theme.gridColor;
    chart.options.scales.x.ticks.color = theme.tickColor;
    chart.options.scales.y.grid.color = theme.gridColor;
    chart.options.scales.y.ticks.color = theme.tickColor;
    if (chart.options.scales.y.title) chart.options.scales.y.title.color = theme.tickColor;
    if (chart.options.scales.y1) {
        chart.options.scales.y1.grid.color = theme.gridColor;
        chart.options.scales.y1.ticks.color = theme.tickColor;
        if (chart.options.scales.y1.title) chart.options.scales.y1.title.color = theme.tickColor;
    }
    chart.options.plugins.legend.labels = { ...(chart.options.plugins.legend.labels || {}), color: theme.legendColor };
    if (chart.options.plugins.tooltip) {
        chart.options.plugins.tooltip.backgroundColor = theme.tooltipBg;
        chart.options.plugins.tooltip.titleColor = theme.tooltipText;
        chart.options.plugins.tooltip.bodyColor = theme.tooltipText;
        chart.options.plugins.tooltip.borderColor = theme.tooltipBorder;
    }
    chart.update('none');
}

function updateLastRefreshed() {
    const el = document.getElementById('lastRefreshed');
    if (!el) return;
    const now = new Date();
    el.textContent = ` | Last refreshed: ${now.toLocaleTimeString()}`;
}

function setCardUpdated(cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    let el = card.querySelector('.card-updated');
    const text = `Updated ${new Date().toLocaleTimeString()}`;
    if (!el) {
        el = document.createElement('div');
        el.className = 'card-updated';
        const target = card.querySelector('.stat-content') || card.querySelector('.card-body') || card;
        target.appendChild(el);
    }
    el.innerHTML = `<i class="fas fa-clock" aria-hidden="true"></i> ${escapeHtml(text)}`;
}

function updateDiagnostics() {
    const queryHealth = document.getElementById('queryHealth');
    const backupExporter = document.getElementById('backupExporterStatus');
    const agentMetrics = document.getElementById('agentMetricsStatus');
    const baselineExporter = document.getElementById('baselineExporterStatus');
    const securityExporter = document.getElementById('securityExporterStatus');
    const autoRefresh = document.getElementById('autoRefreshStatus');
    const diagStatus = document.getElementById('diagnosticsStatus');

    if (queryHealth) {
        if (lastQueryStats.total === 0) {
            queryHealth.textContent = 'No queries run';
        } else {
            queryHealth.textContent = `${lastQueryStats.succeeded}/${lastQueryStats.total} metrics loaded (${lastQueryStats.failed} failed)`;
        }
    }
    if (backupExporter) {
        backupExporter.textContent = lastExporterStatus.backup ? 'Publishing metrics' : 'No data (not scheduled or no output)';
    }
    if (agentMetrics) {
        agentMetrics.textContent = lastExporterStatus.agent ? 'Publishing metrics' : 'No data (agent unavailable)';
    }
    if (baselineExporter) {
        baselineExporter.textContent = lastExporterStatus.baseline ? 'Publishing metrics' : 'No data (not scheduled or no output)';
    }
    if (securityExporter) {
        securityExporter.textContent = (lastExporterStatus.agent || lastExporterStatus.baseline) ? 'Publishing metrics' : 'No data (agent/exporter unavailable)';
    }
    if (autoRefresh) {
        if (refreshIntervalMs > 0) {
            const label = refreshIntervalMs >= 60000 ? `${refreshIntervalMs / 60000}m` : `${refreshIntervalMs / 1000}s`;
            autoRefresh.textContent = `Every ${label}`;
        } else {
            autoRefresh.textContent = 'Disabled';
        }
    }
    if (diagStatus) {
        const healthy = lastQueryStats.failed === 0 && lastQueryStats.total > 0;
        const degraded = lastQueryStats.succeeded > 0 && lastQueryStats.failed > 0;
        diagStatus.textContent = healthy ? 'OK' : degraded ? 'Degraded' : lastQueryStats.total === 0 ? '--' : 'Issues';
        diagStatus.className = healthy ? 'badge badge-success' : degraded ? 'badge badge-warning' : 'badge';
    }
}

function escapeHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function formatBytes(bytes) {
    if (bytes === null || bytes === undefined || isNaN(bytes)) return 'No data';
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const val = bytes / Math.pow(1024, i);
    return `${val.toFixed(val >= 10 ? 0 : 1)} ${units[i]}`;
}

function formatBytesPerSec(bytesPerSec) {
    if (bytesPerSec === null || bytesPerSec === undefined || isNaN(bytesPerSec)) return 'No data';
    if (bytesPerSec <= 0) return '0 B/s';
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s', 'TB/s'];
    const i = Math.min(Math.floor(Math.log(bytesPerSec) / Math.log(1024)), units.length - 1);
    const val = bytesPerSec / Math.pow(1024, i);
    return `${val.toFixed(val >= 10 || i === 0 ? 0 : 1)} ${units[i]}`;
}

function formatRelativeTime(epochSeconds) {
    if (!epochSeconds || epochSeconds <= 0) return 'Never';
    const diff = Math.floor(Date.now() / 1000 - epochSeconds);
    if (diff < 0) return 'Just now';
    if (diff < 60) return `${diff}s ago`;
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
}

function initializeDashboard() {
    initExternalLinks();
    initializeChart();
    fetchAllMetrics({ refreshChart: true });
    checkPrometheusConnection();
}

function updateTimestamp() {
    if (document.hidden) return;
    const now = new Date();
    document.getElementById('timestamp').textContent = now.toLocaleString();
}

// Prometheus query function
async function queryPrometheus(query) {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`);
        if (!response.ok) {
            console.error(`Prometheus query HTTP ${response.status} for: ${query}`);
            return null;
        }
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.result) || data.data.result.length === 0) {
            return null;
        }
        return parseFloat(data.data.result[0].value[1]);
    } catch (error) {
        console.error('Error querying Prometheus:', error);
        return null;
    }
}

async function queryPrometheusFirst(query) {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`);
        if (!response.ok) return null;
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.result) || data.data.result.length === 0) {
            return null;
        }
        return data.data.result[0];
    } catch (error) {
        return null;
    }
}

// Fetch all metrics
async function fetchAllMetrics(opts = {}) {
    const refreshChart = opts instanceof Event ? true : !!(opts && opts.refreshChart);
    if (isRefreshing) return;
    setRefreshing(true);

    const forceSlow = refreshChart;
    const slowIsCached = !forceSlow && slowMetricsCache && Date.now() - slowMetricsCacheAt < SLOW_METRICS_REFRESH_MS;
    const activeRange = document.querySelector('.chart-controls .btn.active')?.dataset.range || '1h';
    const activePage = document.body.dataset.activePage || 'overview';
    const chartVisible = activePage === 'overview' || activePage === 'trends';
    const chartNow = Date.now();
    const shouldRefreshChart = chartVisible && (refreshChart || chartNow - lastChartRefreshAt >= CHART_AUTO_REFRESH_MS);
    if (shouldRefreshChart) lastChartRefreshAt = chartNow;

    const cardIds = ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'alertsCard', 'containersCard', 'chartCard', 'backupCard', 'securityCard'];
    const loadingCardIds = ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'alertsCard', 'containersCard'];
    if (!slowIsCached) loadingCardIds.push('backupCard', 'securityCard');
    if (shouldRefreshChart) loadingCardIds.push('chartCard');
    cardIds.forEach(id => clearCardError(id));
    loadingCardIds.forEach(id => setCardLoading(id, true));

    try {
        // Start core, slow, alerts, and container fetches at the same time.
        // Core previously waited for slow metrics to finish before rendering.
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
        const slowPromise = slowIsCached
            ? Promise.resolve(slowMetricsCache)
            : Promise.all([
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
                const [
                    backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree,
                    resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs,
                    spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved,
                    findingsCritical, findingsHigh, findingsMedium, findingsLow,
                    baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale,
                    baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk,
                    agentReasonResult
                ] = slowResults;
                slowMetricsCache = {
                    backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree,
                    resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs,
                    spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved,
                    findingsCritical, findingsHigh, findingsMedium, findingsLow,
                    baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale,
                    baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk,
                    agentReasonResult
                };
                slowMetricsCacheAt = Date.now();
                return slowMetricsCache;
            });
        const alertsPromise = checkAlerts();
        const containersPromise = updateContainerStatus();
        const chartPromise = shouldRefreshChart ? updateChart(activeRange) : Promise.resolve();

        const coreResults = await corePromise;
        const [cpu, mem, disk, netIn, netOut, load1, bootTime, processes, tempHwmon, tempThermal] = coreResults;
        const temp = tempHwmon ?? tempThermal;

        // Render core cards as soon as their queries resolve; slow backup/security
        // queries keep running in the background.
        const coreAllNull = [cpu, mem, disk, netIn, netOut, load1, bootTime].every(v => v === null);
        if (coreAllNull) {
            showToast('Prometheus unreachable — showing no data', 'error');
            ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard'].forEach(id => setCardError(id, 'No data from Prometheus'));
        } else {
            updateCPUMetrics(cpu);
            updateMemoryMetrics(mem);
            updateDiskMetrics(disk);
            updateNetworkMetrics(netIn, netOut);
            updateSystemHealth(load1, bootTime, processes, temp);

            if (cpu === null) setCardError('cpuCard', 'CPU data unavailable');
            if (mem === null) setCardError('memoryCard', 'Memory data unavailable');
            if (disk === null) setCardError('diskCard', 'Disk data unavailable');
            if (netIn === null && netOut === null) setCardError('networkCard', 'Network data unavailable');
        }
        ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard'].forEach(id => setCardLoading(id, false));

        const slow = await slowPromise;
        const slowFetched = !slowIsCached;
        const {
            backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree,
            resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs,
            spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved,
            findingsCritical, findingsHigh, findingsMedium, findingsLow,
            baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale,
            baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk,
            agentReasonResult
        } = slow;
        const baseline = {
            exporterUp: baselineExporterUp, neverRun: baselineNeverRun, lastRun: baselineLastRun, stale: baselineStale,
            opaOk: baselineOpaOk, drift: baselineDrift, trivyFsOk: baselineTrivyFsOk, gitleaksOk: baselineGitleaksOk
        };

        const slowValues = [backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs, spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, baselineExporterUp, baselineNeverRun, baselineLastRun, baselineStale, baselineOpaOk, baselineDrift, baselineTrivyFsOk, baselineGitleaksOk];
        const executed = coreResults.length + (slowFetched ? 28 : 0);
        const executedValues = slowFetched ? [...coreResults, ...slowValues] : coreResults;
        const succeeded = executedValues.filter(v => v !== null).length + (slowFetched && agentReasonResult ? 1 : 0);
        lastQueryStats = { total: executed, succeeded, failed: executed - succeeded };
        lastExporterStatus = {
            backup: [backupLastSuccess, backupHealthOk, resticLastSuccess, resticHealthOk, resticHealthTs].some(v => v !== null),
            agent: spectreUp !== null,
            baseline: baselineExporterUp === 1,
            security: spectreUp !== null || baselineExporterUp === 1
        };

        const agentReason = agentReasonResult?.metric?.reason || null;
        updateBackupStatus(backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes, backupRepoFree, resticLastSuccess, resticOffsite, resticHealthOk, resticHealthTs, resticVerifyOk, resticVerifyTs);
        updateSecurityStatus(spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh, findingsMedium, findingsLow, agentReason, baseline);
        ['backupCard', 'securityCard'].forEach(id => setCardLoading(id, false));
        await Promise.allSettled([alertsPromise, containersPromise, chartPromise]);
        ['alertsCard', 'containersCard', 'chartCard'].forEach(id => setCardLoading(id, false));
        updateLastRefreshed();
        updateDiagnostics();
    } catch (err) {
        console.error('Fetch error:', err);
        showToast('Failed to refresh metrics', 'error');
        ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'backupCard', 'securityCard'].forEach(id => setCardError(id, 'Fetch failed'));
        lastQueryStats = { total: 0, succeeded: 0, failed: 0 };
        updateDiagnostics();
    } finally {
        cardIds.forEach(id => setCardLoading(id, false));
        setRefreshing(false);
    }
}

// Update CPU metrics
function updateCPUMetrics(cpuUsage) {
    if (cpuUsage !== null) {
        document.getElementById('cpuUsage').textContent = cpuUsage.toFixed(1) + '%';
        const change = document.getElementById('cpuChange');
        if (cpuUsage > 80) {
            change.textContent = 'High';
            change.className = 'stat-change negative';
        } else if (cpuUsage > 60) {
            change.textContent = 'Moderate';
            change.className = 'stat-change';
        } else {
            change.textContent = 'Normal';
            change.className = 'stat-change positive';
        }
        clearCardError('cpuCard');
        setCardUpdated('cpuCard');
    }
}

// Update Memory metrics
function updateMemoryMetrics(memoryUsage) {
    if (memoryUsage !== null) {
        document.getElementById('memoryUsage').textContent = memoryUsage.toFixed(1) + '%';
        const change = document.getElementById('memoryChange');
        if (memoryUsage > 80) {
            change.textContent = 'High';
            change.className = 'stat-change negative';
        } else if (memoryUsage > 60) {
            change.textContent = 'Moderate';
            change.className = 'stat-change';
        } else {
            change.textContent = 'Normal';
            change.className = 'stat-change positive';
        }
        clearCardError('memoryCard');
        setCardUpdated('memoryCard');
    }
}

// Update Disk metrics
function updateDiskMetrics(diskUsage) {
    if (diskUsage !== null) {
        document.getElementById('diskUsage').textContent = diskUsage.toFixed(1) + '%';
        const change = document.getElementById('diskChange');
        if (diskUsage > 80) {
            change.textContent = 'High';
            change.className = 'stat-change negative';
        } else if (diskUsage > 60) {
            change.textContent = 'Moderate';
            change.className = 'stat-change';
        } else {
            change.textContent = 'Normal';
            change.className = 'stat-change positive';
        }
        clearCardError('diskCard');
        setCardUpdated('diskCard');
    }
}

// Update Network metrics
function updateNetworkMetrics(networkIn, networkOut) {
    if (networkIn !== null && networkOut !== null) {
        const totalBytes = networkIn + networkOut;
        document.getElementById('networkIO').textContent = formatBytesPerSec(totalBytes);
        document.getElementById('networkIO').title = `${(totalBytes / 1024).toFixed(1)} KB/s (RX+TX, 5m rate)`;
        const change = document.getElementById('networkChange');
        if (totalBytes > 100 * 1024 * 1024) { // > 100 MB/s
            change.textContent = 'High';
            change.className = 'stat-change negative';
        } else if (totalBytes < 5120) { // < ~5 KB/s: effectively idle/near-zero; avoid green "Normal" for 0.00
            change.textContent = 'Idle';
            change.className = 'stat-change';
            change.title = 'Near-zero measured RX+TX (5m rate). Verify in Prometheus if unexpected.';
        } else {
            change.textContent = 'Normal';
            change.className = 'stat-change positive';
            change.title = '';
        }
        clearCardError('networkCard');
        setCardUpdated('networkCard');
    }
}

// Update System Health
function updateSystemHealth(systemLoad, bootTime, processCount, temperature) {
    if (systemLoad !== null) {
        document.getElementById('systemLoad').textContent = systemLoad.toFixed(2);
        
        const healthStatus = document.getElementById('healthStatus');
        if (systemLoad > 2.0) {
            healthStatus.textContent = 'High Load';
            healthStatus.className = 'badge badge-danger';
        } else if (systemLoad > 1.0) {
            healthStatus.textContent = 'Moderate Load';
            healthStatus.className = 'badge badge-warning';
        } else {
            healthStatus.textContent = 'Healthy';
            healthStatus.className = 'badge badge-success';
        }
    }

    if (bootTime !== null) {
        const uptimeSeconds = Date.now() / 1000 - bootTime;
        const uptime = formatUptime(uptimeSeconds);
        document.getElementById('uptime').textContent = uptime;
    }

    if (processCount !== null) {
        document.getElementById('processes').textContent = Math.floor(processCount);
    } else {
        document.getElementById('processes').textContent = 'No data';
    }

    if (temperature !== null) {
        document.getElementById('temperature').textContent = Math.floor(temperature) + '°C';
    } else {
        document.getElementById('temperature').textContent = 'No data';
    }
    clearCardError('healthCard');
    setCardUpdated('healthCard');
}

function formatUptime(seconds) {
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    
    if (days > 0) {
        return `${days}d ${hours}h ${minutes}m`;
    } else if (hours > 0) {
        return `${hours}h ${minutes}m`;
    } else {
        return `${minutes}m`;
    }
}

// Update Backup Status
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

    if (lastEl) {
        lastEl.textContent = effectiveLast ? formatRelativeTime(effectiveLast) : 'Never';
        if (effectiveLast) lastEl.title = new Date(effectiveLast * 1000).toLocaleString();
    }

    if (healthEl) {
        if (healthOk === 1) {
            healthEl.textContent = `OK${healthTs ? ` (${formatRelativeTime(healthTs)})` : ''}`;
        } else if (healthOk === 0) {
            healthEl.textContent = `Failed${healthTs ? ` (${formatRelativeTime(healthTs)})` : ''}`;
        } else {
            healthEl.textContent = 'No data';
        }
        if (healthTs) healthEl.title = new Date(healthTs * 1000).toLocaleString();
    }

    if (resticHealthEl) {
        if (resticHealthOk === 1) {
            resticHealthEl.textContent = `OK${resticHealthTs ? ` (${formatRelativeTime(resticHealthTs)})` : ''}`;
        } else if (resticHealthOk === 0 && resticHealthTs) {
            resticHealthEl.textContent = `Degraded (${formatRelativeTime(resticHealthTs)})`;
        } else if (resticHealthTs) {
            resticHealthEl.textContent = formatRelativeTime(resticHealthTs);
        } else {
            resticHealthEl.textContent = 'No data';
        }
        if (resticHealthTs) resticHealthEl.title = new Date(resticHealthTs * 1000).toLocaleString();
    }

    if (sizeEl) {
        const sizeText = formatBytes(repoBytes);
        const freeText = repoFree !== null ? formatBytes(repoFree) : null;
        sizeEl.textContent = freeText ? `${sizeText} / ${freeText} free` : sizeText;
    }

    if (offsiteEl) {
        offsiteEl.textContent = (resticOffsite && resticOffsite > 0) ? formatRelativeTime(resticOffsite) : 'No data';
        if (resticOffsite && resticOffsite > 0) offsiteEl.title = new Date(resticOffsite * 1000).toLocaleString();
    }

    if (verifyEl) {
        if (resticVerifyOk === 1) {
            verifyEl.textContent = `Passed${resticVerifyTs ? ` (${formatRelativeTime(resticVerifyTs)})` : ''}`;
        } else if (resticVerifyOk === 0 && resticVerifyTs) {
            verifyEl.textContent = `Failed (${formatRelativeTime(resticVerifyTs)})`;
        } else if (resticVerifyTs) {
            verifyEl.textContent = formatRelativeTime(resticVerifyTs);
        } else {
            verifyEl.textContent = 'No data';
        }
        if (resticVerifyTs) verifyEl.title = new Date(resticVerifyTs * 1000).toLocaleString();
    }

    if (statusEl) {
        const isHealthy = healthOk === 1;
        const isStale = effectiveLast && (Date.now() / 1000 - effectiveLast) > 86400 * 2;
        const verifyBad = resticVerifyOk === 0;
        const resticHealthBad = resticHealthOk === 0 && !!resticHealthTs;
        const lowFreeSpace = repoFree !== null && repoFree < 20 * 1024 * 1024 * 1024;
        if (isHealthy && !isStale && !verifyBad && !resticHealthBad && !lowFreeSpace) {
            statusEl.textContent = 'OK';
            statusEl.className = 'badge badge-success';
        } else if (healthOk === 0 || isStale || verifyBad || resticHealthBad || lowFreeSpace) {
            statusEl.textContent = 'Attention';
            statusEl.className = 'badge badge-warning';
        } else {
            statusEl.textContent = 'Unknown';
            statusEl.className = 'badge';
        }
    }
    clearCardError('backupCard');
    setCardUpdated('backupCard');
}

// Update Security Status
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
            if (statusEl) {
                statusEl.textContent = b.neverRun === 1 ? 'Baseline Pending' : (b.stale === 1 ? 'Baseline Stale' : 'Baseline Only');
                statusEl.className = b.stale === 1 ? 'badge badge-warning' : (b.neverRun === 1 ? 'badge badge-warning' : 'badge badge-success');
            }
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
        if (everScanned === 1 && lastScan) {
            scanEl.textContent = formatRelativeTime(lastScan);
            scanEl.title = new Date(lastScan * 1000).toLocaleString();
        } else if (everScanned === 0) {
            scanEl.textContent = 'Never scanned';
        } else {
            scanEl.textContent = 'No data';
        }
    }

    const totalFindings = unresolved !== null ? Math.floor(unresolved) : null;
    const c = critical !== null ? Math.floor(critical) : 0;
    const h = high !== null ? Math.floor(high) : 0;
    const m = medium !== null ? Math.floor(medium) : 0;
    const l = low !== null ? Math.floor(low) : 0;

    if (vulnEl) {
        vulnEl.textContent = totalFindings !== null ? String(totalFindings) : 'No data';
    }

    if (severityEl) {
        if (totalFindings !== null) {
            severityEl.textContent = `C:${c} H:${h} M:${m} L:${l}`;
            severityEl.title = `Critical: ${c}, High: ${h}, Medium: ${m}, Low: ${l}`;
        } else {
            severityEl.textContent = 'No data';
        }
    }

    if (statusEl) {
        if (totalFindings === null) {
            statusEl.textContent = 'Unknown';
            statusEl.className = 'badge';
        } else if (c > 0 || totalFindings > 10) {
            statusEl.textContent = 'At Risk';
            statusEl.className = 'badge badge-danger';
        } else if (h > 0 || totalFindings > 0) {
            statusEl.textContent = 'Review';
            statusEl.className = 'badge badge-warning';
        } else {
            statusEl.textContent = 'Secure';
            statusEl.className = 'badge badge-success';
        }
    }
    clearCardError('securityCard');
    setCardUpdated('securityCard');
}
function renderContainers() {
    const grid = document.getElementById('containersGrid');
    if (!grid) return;
    const q = (document.getElementById('containerFilter')?.value || '').trim().toLowerCase();
    const names = Array.isArray(currentContainerNames) ? currentContainerNames : [];
    const filteredNames = q ? names.filter(n => n.toLowerCase().includes(q)) : names;
    const renderKey = `${lastContainerSignature}|${q}`;
    if (renderKey === lastRenderedContainerKey) return;
    lastRenderedContainerKey = renderKey;

    if (!names.length) {
        if (lastContainerMeta.hasUnlabeledRecent) {
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

// Update Container Status
async function updateContainerStatus() {
    try {
        // Real per-container state from cAdvisor: use container_last_seen series
        // with a 24h recency window (same window the Grafana resource dashboard
        // uses: container_last_seen > (time() - 86400)). Containers with recent
        // activity are reported running; an empty set means no recent data.
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
            if (isRootOrSystem) {
                hasUnlabeledRecent = true;
                continue;
            }
            seen.set(name, Math.max(seen.get(name) || 0, lastSeen));
        }

        const containerNames = [...seen.keys()].sort();
        const containerStatus = document.getElementById('containerStatus');
        const hasData = containerNames.length > 0;
        currentContainerNames = containerNames;
        lastContainerMeta = { hasUnlabeledRecent };
        lastContainerSignature = `${containerNames.join('|')}|${hasUnlabeledRecent ? 'u' : ''}`;
        lastRenderedContainerKey = null;
        renderContainers();

        if (hasData) {
            const groupCount = new Set(containerNames.map(n => (n || '').split(/[-_]/)[0] || n || 'other')).size;
            containerStatus.textContent = `${containerNames.length} running · ${groupCount} group${groupCount === 1 ? '' : 's'}`;
            containerStatus.className = 'badge badge-success';
        } else {
            containerStatus.textContent = hasUnlabeledRecent ? 'Labels missing' : 'No data';
            containerStatus.className = hasUnlabeledRecent ? 'badge badge-warning' : 'badge';
        }
        clearCardError('containersCard');
        setCardUpdated('containersCard');
    } catch (error) {
        console.error('Error fetching container status:', error);
        lastContainerSignature = null;
        lastRenderedContainerKey = null;
        currentContainerNames = [];
        lastContainerMeta = { hasUnlabeledRecent: false };
        setCardError('containersCard', 'Container data unavailable');
        document.getElementById('containersGrid').innerHTML = '<div class="no-alerts no-alerts--degraded"><i class="fas fa-triangle-exclamation" aria-hidden="true"></i><span><strong>Container data unavailable.</strong> Unable to fetch recent container status.</span></div>';
        const containerStatus = document.getElementById('containerStatus');
        if (containerStatus) {
            containerStatus.textContent = 'No data';
            containerStatus.className = 'badge';
        }
    }
}

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

    const filtered = activeAlertFilter === 'all'
        ? currentAlerts
        : currentAlerts.filter(a => (a.labels?.severity || 'info') === activeAlertFilter);

    const countEl = document.getElementById('alertCount');
    countEl.textContent = String(currentAlerts.length);
    const hasCritical = currentAlerts.some(a => (a.labels?.severity || '') === 'critical');
    const hasWarning = currentAlerts.some(a => (a.labels?.severity || '') === 'warning');
    countEl.className = hasCritical ? 'badge badge-danger' : hasWarning ? 'badge badge-warning' : 'badge badge-success';

    if (currentAlerts.length === 0) {
        alertsList.innerHTML = '<div class="no-alerts no-alerts--ok"><i class="fas fa-check-circle" aria-hidden="true"></i><span><strong>All clear.</strong> No active alerts are firing.</span></div>';
        return;
    }
    if (filtered.length === 0) {
        alertsList.innerHTML = `<div class="empty-state"><i class="fas fa-filter" aria-hidden="true"></i><span>No <strong>${escapeHtml(activeAlertFilter)}</strong> alerts match the current filter (${currentAlerts.length} total).</span></div>`;
        return;
    }

    const filterNote = activeAlertFilter !== 'all' ? `<div class="alert-filter-note muted" aria-live="polite">Showing ${filtered.length} of ${currentAlerts.length} active alerts</div>` : '';

    alertsList.innerHTML = filterNote + filtered.map(alert => {
        const rawSeverity = String(alert.labels?.severity || 'info').toLowerCase();
        const severity = ['critical', 'warning', 'info'].includes(rawSeverity) ? rawSeverity : 'info';
        const name = alert.labels?.alertname || 'Unnamed alert';
        const description = alert.annotations?.description || alert.annotations?.summary || '';
        const startMs = parseAlertTime(alert.activeAt || alert.startsAt);
        const safeName = document.createElement('span');
        safeName.textContent = name;
        const safeDesc = document.createElement('span');
        safeDesc.textContent = description;
        const timeStr = startMs ? new Date(startMs).toLocaleString() : 'Unknown time';
        const ageStr = formatAlertAge(startMs);
        const promBase = extBase('prometheus');
        const amBase = extBase('alertmanager');
        const alertname = alert.labels?.alertname ? String(alert.labels.alertname) : '';
        const promqlName = alertname.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ');
        const amFilter = alertname ? encodeURIComponent(`{alertname="${alertname.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, ' ')}"}`) : '';
        const promGraphHref = (promBase && alertname)
            ? `${promBase}/graph?g0.expr=${encodeURIComponent(`ALERTS{alertname="${promqlName}"}`)}&g0.tab=1`
            : (promBase ? `${promBase}/alerts` : '');
        const amHref = amBase
            ? `${amBase}/#/alerts${amFilter ? `?receiver=&silenced=false&inhibited=false&active=true&filter=${amFilter}` : ''}`
            : '';
        const links = [
            promGraphHref ? `<a href="${escapeHtml(promGraphHref)}" target="_blank" rel="noopener noreferrer" title="${escapeHtml(alertname ? 'Open in Prometheus with pre-filled ALERTS query' : 'Open Prometheus alerts')}" aria-label="Open in Prometheus">Prometheus</a>` : '',
            amHref ? `<a href="${escapeHtml(amHref)}" target="_blank" rel="noopener noreferrer" title="${escapeHtml(alertname ? 'Open in Alertmanager (filter pre-filled where supported)' : 'Open Alertmanager')}" aria-label="Open in Alertmanager">Alertmanager</a>` : ''
        ].filter(Boolean).join('');
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
        </div>
    `;
    }).join('');
}

// Check Alerts
async function checkAlerts() {
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/alerts`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.alerts)) {
            throw new Error('Invalid alerts response');
        }

        currentAlerts = data.data.alerts.filter(alert => alert.state === 'firing');
        renderAlerts();
        clearCardError('alertsCard');
        setCardUpdated('alertsCard');
    } catch (error) {
        console.error('Error checking alerts:', error);
        currentAlerts = [];
        clearCardError('alertsCard');
        const alertsCard = document.getElementById('alertsCard');
        if (alertsCard) alertsCard.classList.add('card--error');
        document.getElementById('alertsList').innerHTML = '<div class="no-alerts no-alerts--degraded"><i class="fas fa-triangle-exclamation" aria-hidden="true"></i><span><strong>Alerts unavailable.</strong> Unable to fetch alert data from Prometheus/Alertmanager.</span></div>';
    }
}

// Check Prometheus Connection
async function checkPrometheusConnection() {
    const statusIndicator = document.getElementById('systemStatus');
    const statusText = document.getElementById('systemStatusText');
    try {
        const response = await fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/status/buildinfo`);
        const prometheusStatus = document.getElementById('prometheusStatus');
        if (response.ok) {
            prometheusStatus.textContent = 'Connected';
            prometheusStatus.style.color = '#10b981';
            if (statusIndicator) {
                statusIndicator.classList.remove('offline');
                statusIndicator.classList.add('online');
            }
            if (statusText) statusText.textContent = 'All Systems Operational';
            if (lastPrometheusConnected === false) {
                showToast('Prometheus reconnected', 'success');
            }
            lastPrometheusConnected = true;
        } else {
            prometheusStatus.textContent = 'Disconnected';
            prometheusStatus.style.color = '#ef4444';
            if (statusIndicator) {
                statusIndicator.classList.remove('online');
                statusIndicator.classList.add('offline');
            }
            if (statusText) statusText.textContent = 'Prometheus Disconnected';
            if (lastPrometheusConnected !== false) {
                showToast('Prometheus disconnected', 'error');
            }
            lastPrometheusConnected = false;
        }
    } catch (error) {
        document.getElementById('prometheusStatus').textContent = 'Disconnected';
        document.getElementById('prometheusStatus').style.color = '#ef4444';
        if (statusIndicator) {
            statusIndicator.classList.remove('online');
            statusIndicator.classList.add('offline');
        }
        if (statusText) statusText.textContent = 'Prometheus Unreachable';
        if (lastPrometheusConnected !== false) {
            showToast('Prometheus unreachable', 'error');
        }
        lastPrometheusConnected = false;
    }
}

// Initialize Chart
function initializeChart() {
    const ctx = document.getElementById('resourceChart').getContext('2d');
    const theme = getChartTheme();
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [
                {
                    label: 'CPU Usage (%)',
                    data: [],
                    borderColor: '#667eea',
                    backgroundColor: 'rgba(102, 126, 234, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 3,
                    borderWidth: 1.5
                },
                {
                    label: 'Memory Usage (%)',
                    data: [],
                    borderColor: '#f5576c',
                    backgroundColor: 'rgba(245, 87, 108, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 3,
                    borderWidth: 1.5
                },
                {
                    label: 'Disk Usage (%)',
                    data: [],
                    borderColor: '#4facfe',
                    backgroundColor: 'rgba(79, 172, 254, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 3,
                    borderWidth: 1.5
                },
                {
                    label: 'Network I/O (RX+TX, 5m rate)',
                    data: [],
                    borderColor: '#f59e0b',
                    backgroundColor: 'rgba(245, 158, 11, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointRadius: 0,
                    pointHoverRadius: 3,
                    borderWidth: 1.5,
                    yAxisID: 'y1'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation: reduceMotion ? false : { duration: 150 },
            interaction: {
                intersect: false,
                mode: 'index'
            },
            scales: {
                x: {
                    grid: { display: false, color: theme.gridColor },
                    ticks: { maxTicksLimit: 10, color: theme.tickColor }
                },
                y: {
                    type: 'linear',
                    position: 'left',
                    min: 0,
                    max: 100,
                    grid: { color: theme.gridColor },
                    ticks: {
                        color: theme.tickColor,
                        callback: (v) => v + '%'
                    },
                    title: { display: true, text: 'Usage', color: theme.tickColor }
                },
                y1: {
                    type: 'linear',
                    position: 'right',
                    min: 0,
                    beginAtZero: true,
                    grid: { drawOnChartArea: false, color: theme.gridColor },
                    ticks: {
                        color: theme.tickColor,
                        callback: (v) => formatBytesPerSec(v)
                    },
                    title: { display: true, text: 'Network', color: theme.tickColor }
                }
            },
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: { color: theme.legendColor, usePointStyle: true, boxWidth: 8, boxHeight: 8, padding: 14 }
                },
                tooltip: {
                    animation: !reduceMotion,
                    backgroundColor: theme.tooltipBg,
                    titleColor: theme.tooltipText,
                    bodyColor: theme.tooltipText,
                    borderColor: theme.tooltipBorder,
                    borderWidth: 1,
                    padding: 10,
                    displayColors: true,
                    callbacks: {
                        label: (ctx) => {
                            const v = ctx.parsed.y;
                            if (ctx.dataset.yAxisID === 'y1') {
                                return ` ${ctx.dataset.label}: ${formatBytesPerSec(v)}`;
                            }
                            return ` ${ctx.dataset.label}: ${Number.isFinite(v) ? v.toFixed(1) : '—'}%`;
                        }
                    }
                }
            }
        }
    });
}

async function updateChart(range) {
    const secondsMap = { '1h': 3600, '6h': 21600, '24h': 86400, '7d': 604800 };
    const seconds = secondsMap[range] || 3600;
    // Cap chart resolution to roughly 400 points per series. The previous 60s
    // step produced 1,440 points per series over 24h, which is more detail than
    // the chart can show and makes both Prometheus response and rendering heavier.
    const step = range === '7d' ? 3600 : Math.max(60, Math.ceil(seconds / 400));
    const spansMultipleDays = seconds > 86400;

    const now = Math.floor(Date.now() / 1000);
    const start = now - seconds;

    const queries = [
        '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))',
        '100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))',
        '100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))',
        'sum(rate(node_network_receive_bytes_total{device!~"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*"}[5m])) + sum(rate(node_network_transmit_bytes_total{device!~"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*"}[5m]))'
    ];

    // Bump the in-flight token; any in-progress fetch is now stale.
    const myToken = ++chartRequestToken;

    try {
        const responses = await Promise.all(queries.map(q =>
            fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(q)}&start=${start}&end=${now}&step=${step}`, {}, 20000)
        ));

        if (myToken !== chartRequestToken) return; // a newer update has superseded us

        if (responses.some(r => !r.ok)) {
            console.error('Chart range query failed:',
                responses.map((r, i) => `${i}: HTTP ${r.status}`).join(', '));
            setCardError('chartCard', 'Chart data unavailable');
            return;
        }

        const results = await Promise.all(responses.map(r => r.json()));

        if (myToken !== chartRequestToken) return; // recheck after the second await

        if (results.some(d => d.status !== 'success')) {
            console.error('Chart range query returned non-success status');
            setCardError('chartCard', 'Chart data unavailable');
            return;
        }

        const labelSeries = results
            .map(r => r?.data?.result?.[0]?.values)
            .find(v => Array.isArray(v) && v.length > 0);
        if (!labelSeries) {
            chart.data.labels = [];
            chart.data.datasets.forEach(d => { d.data = []; });
            chart.update();
            lastChartRefreshAt = Date.now();
            setCardError('chartCard', 'No trend data available');
            return;
        }

        const timestamps = labelSeries.map(v => {
            const d = new Date(v[0] * 1000);
            // Include the date component for ranges that cross day boundaries
            // so the x-axis remains interpretable past 24h.
            return spansMultipleDays
                ? d.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
                : d.toLocaleTimeString();
        });

        chart.data.labels = timestamps;
        chart.data.datasets.forEach((dataset, i) => {
            dataset.data = results[i]?.data?.result?.[0]?.values?.map(v => parseFloat(v[1])) || [];
        });
        chart.update();
        lastChartRefreshAt = Date.now();
        clearCardError('chartCard');
        setCardUpdated('chartCard');
    } catch (e) {
        if (myToken === chartRequestToken) {
            console.error('Error updating chart:', e);
            setCardError('chartCard', 'Chart update failed');
        }
    }
}

// Export snapshot (frontend-only)
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
            active: currentAlerts.map(a => ({
                name: a.labels?.alertname,
                severity: a.labels?.severity,
                description: a.annotations?.description || a.annotations?.summary
            }))
        },
        diagnostics: {
            queryHealth: document.getElementById('queryHealth')?.textContent,
            backupExporter: document.getElementById('backupExporterStatus')?.textContent,
            agentMetrics: document.getElementById('agentMetricsStatus')?.textContent,
            baselineExporter: document.getElementById('baselineExporterStatus')?.textContent,
            securityExporter: document.getElementById('securityExporterStatus')?.textContent
                || ((lastExporterStatus.agent || lastExporterStatus.baseline) ? 'Publishing metrics' : 'No data (agent/exporter unavailable)')
        }
    };

    const text = JSON.stringify(snapshot, null, 2);
    try {
        await navigator.clipboard.writeText(text);
        showToast('Snapshot copied to clipboard (JSON)', 'success');
    } catch (e) {
        // Fallback: download as file
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

// Export chart data as CSV
function exportChartCSV() {
    const chart = window.chart;
    if (!chart || !chart.data || !chart.data.labels || chart.data.labels.length === 0) {
        showToast('No chart data to export', 'error');
        return;
    }

    const labels = chart.data.labels;
    const datasets = chart.data.datasets;

    // Build CSV header
    const headers = ['Timestamp'] + datasets.map(d => d.label || 'Series');
    const rows = [headers.join(',')];

    // Build data rows
    for (let i = 0; i < labels.length; i++) {
        const row = [labels[i]];
        for (let j = 0; j < datasets.length; j++) {
            const value = datasets[j].data[i];
            row.push(value !== undefined && value !== null ? value.toFixed(2) : '');
        }
        rows.push(row.join(','));
    }

    const csv = rows.join('\n');
    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `spectre-dashboard-chart-${Date.now()}.csv`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
    showToast('Chart exported as CSV', 'success');
}

// Quick Actions (frontend hook with graceful fallback; real backend required for execution)
function getActionToken() {
    return sessionStorage.getItem('spectre-action-token') || '';
}

function setActionToken(token) {
    if (token) sessionStorage.setItem('spectre-action-token', token);
    else sessionStorage.removeItem('spectre-action-token');
}

async function triggerAction(action, label, retry = true) {
    if (!confirm(`This will request "${label}". Continue?`)) return;

    if (!ACTIONS_BASE) {
        showToast(`${label}: actions disabled (actionsBase=off).`, 'error');
        return;
    }

    const token = getActionToken();
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers['X-Dashboard-Action-Token'] = token;

    try {
        const response = await fetch(`${ACTIONS_BASE.replace(/\/$/, '')}/${encodeURIComponent(action)}`, {
            method: 'POST',
            headers,
            body: JSON.stringify({ action, requestedAt: new Date().toISOString() })
        });

        let payload = null;
        try { payload = await response.json(); } catch (_) {}

        if (response.status === 401 && retry) {
            const entered = prompt('Action token required. Enter DASHBOARD_ACTION_TOKEN (stored for this browser session):');
            if (entered) {
                setActionToken(entered.trim());
                return triggerAction(action, label, false);
            }
            showToast(`${label}: action token required.`, 'error');
            return;
        }

        if (response.status === 503 && payload?.error === 'not_configured') {
            showToast(`${label}: action service not configured (set DASHBOARD_ACTION_TOKEN).`, 'error');
            return;
        }

        if (response.ok) {
            const msg = payload?.message || `${label} accepted.`;
            showToast(msg, 'success');
        } else {
            const detail = payload?.message || payload?.error || `HTTP ${response.status}`;
            showToast(`${label} failed: ${detail}`, 'error');
        }
    } catch (e) {
        console.error('Action error:', e);
        showToast(`${label} failed: action endpoint unreachable. Is dashboard-actions running and proxied?`, 'error');
    }
}

function runBackup() {
    triggerAction('backup', 'Run backup');
}

function runMaintenance() {
    triggerAction('maintenance', 'Run maintenance');
}

function runSecurityScan() {
    triggerAction('security-scan', 'Security scan');
}

function viewLogs() {
    showToast('Opening Grafana logs...', 'info');
    window.open(externalUrl('grafana', '/'), '_blank');
}

// Dashboard shell: page routing for side-panel tabs, nav state, and mobile sidebar.
(function initDashboardShell() {
    if (!('querySelectorAll' in document)) return;
    const links = Array.from(document.querySelectorAll('.nav-item[data-page]'));
    const pageSections = Array.from(document.querySelectorAll('[data-show-pages]'));
    const shell = document.querySelector('.app-shell');
    const main = document.querySelector('.app-main');
    const headingIcon = document.querySelector('#pageHeading i');
    const headingText = document.getElementById('pageHeadingText');
    const sidebarBtn = document.getElementById('sidebarToggle');
    const sidebarBackdrop = document.getElementById('sidebarBackdrop');
    const validPages = new Set(links.map(a => a.dataset.page));
    const legacyPageMap = {
        '': 'overview',
        '#main-content': 'overview',
        '#page-overview': 'overview',
        '#page-health': 'health',
        '#healthCard': 'health',
        '#page-alerts': 'alerts',
        '#alertsCard': 'alerts',
        '#page-containers': 'containers',
        '#containersCard': 'containers',
        '#page-trends': 'trends',
        '#chartCard': 'trends',
        '#page-security': 'security',
        '#securityCard': 'security',
        '#page-backup': 'backup',
        '#backupCard': 'backup'
    };

    function isMobileSidebar() {
        return !!(window.matchMedia && window.matchMedia('(max-width: 980px)').matches);
    }
    function syncSidebarState() {
        if (!shell) return;
        const collapsed = shell.classList.contains('sidebar-collapsed');
        if (sidebarBtn) {
            sidebarBtn.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
            sidebarBtn.setAttribute('aria-label', collapsed ? 'Open navigation' : 'Close navigation');
        }
        if (sidebarBackdrop) sidebarBackdrop.hidden = !isMobileSidebar() || collapsed;
    }
    function closeSidebarIfMobile() {
        if (shell && isMobileSidebar()) {
            shell.classList.add('sidebar-collapsed');
            syncSidebarState();
        }
    }

    function pageFromHash(hash) {
        if (!hash) return 'overview';
        if (legacyPageMap[hash]) return legacyPageMap[hash];
        const byHref = links.find(a => a.getAttribute('href') === hash);
        if (byHref?.dataset.page) return byHref.dataset.page;
        return 'overview';
    }

    function setPage(page, opts = {}) {
        const activePage = validPages.has(page) ? page : 'overview';
        const activeLink = links.find(a => a.dataset.page === activePage) || links[0];
        links.forEach(a => {
            const active = a === activeLink;
            a.classList.toggle('active', active);
            if (active) a.setAttribute('aria-current', 'page');
            else a.removeAttribute('aria-current');
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
            requestAnimationFrame(() => { if (chart && typeof chart.resize === 'function') chart.resize(); });
            if (chart && typeof updateChart === 'function') {
                const range = document.querySelector('.chart-controls .btn.active')?.dataset.range || '1h';
                const stale = !lastChartRefreshAt || (Date.now() - lastChartRefreshAt) >= CHART_AUTO_REFRESH_MS;
                if (stale) updateChart(range).catch(() => {});
            }
        }
        closeSidebarIfMobile();
    }

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
            if (!isMobileSidebar()) {
                shell.classList.remove('sidebar-collapsed');
                syncSidebarState();
            } else {
                shell.classList.add('sidebar-collapsed');
                syncSidebarState();
            }
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
})();
