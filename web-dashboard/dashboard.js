// Dashboard JavaScript
// Requests go to the nginx in this compose file, which proxies /api/ to
// Prometheus, so the default is same-origin and empty. It used to default to
// `${location.protocol}//${location.hostname}:9090`, a different origin from the
// page, and Prometheus sends no Access-Control-Allow-Origin, so every fetch was
// blocked and the dashboard rendered empty.
// Override with ?prometheus=https://prometheus.example.com to read from a
// Prometheus reachable from the browser rather than through this proxy.
const PROMETHEUS_URL = new URLSearchParams(location.search).get('prometheus') || '';
const REFRESH_INTERVAL = 30000; // 30 seconds

let chart = null;
let chartRequestToken = 0; // Monotonic token to discard stale updateChart responses
let isRefreshing = false;
let lastPrometheusConnected = null;

// UI helpers: loading states, error states, and toasts
function setCardLoading(cardId, isLoading) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.toggle('card--loading', isLoading);
}

function setCardError(cardId, message) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.remove('card--loading');
    card.classList.add('card--error');
    let errorEl = card.querySelector('.error-message');
    if (!errorEl) {
        errorEl = document.createElement('div');
        errorEl.className = 'error-message';
        const body = card.querySelector('.card-body') || card;
        body.appendChild(errorEl);
    }
    errorEl.innerHTML = `<i class="fas fa-exclamation-circle"></i> ${message}`;
}

function clearCardError(cardId) {
    const card = document.getElementById(cardId);
    if (!card) return;
    card.classList.remove('card--error', 'card--loading');
    const errorEl = card.querySelector('.error-message');
    if (errorEl) errorEl.remove();
}

function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;
    const toast = document.createElement('div');
    toast.className = `toast toast--${type}`;
    const iconClass = type === 'success' ? 'fa-check-circle' : type === 'error' ? 'fa-exclamation-triangle' : 'fa-info-circle';
    toast.innerHTML = `<i class="fas ${iconClass}"></i><span class="toast-message">${message}</span>`;
    container.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(120%)';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

function setRefreshing(refreshing) {
    isRefreshing = refreshing;
    const btn = document.getElementById('refreshBtn');
    if (!btn) return;
    btn.disabled = refreshing;
    btn.classList.toggle('btn--loading', refreshing);
}

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    initializeTheme();
    initializeDashboard();
    updateTimestamp();
    setInterval(updateTimestamp, 1000);
    setInterval(fetchAllMetrics, REFRESH_INTERVAL);
    
    // Event listeners
    document.getElementById('refreshBtn').addEventListener('click', fetchAllMetrics);
    document.getElementById('themeToggle').addEventListener('click', toggleDarkMode);
    
    // Chart range buttons
    document.querySelectorAll('.chart-controls .btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.chart-controls .btn').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            updateChart(e.target.dataset.range);
        });
    });
});

function initializeTheme() {
    const html = document.documentElement;
    const savedTheme = localStorage.getItem('spectre-theme');
    const toggle = document.getElementById('themeToggle');
    const icon = toggle.querySelector('i');

    if (savedTheme === 'dark') {
        html.classList.add('dark');
        icon.classList.replace('fa-moon', 'fa-sun');
    } else {
        html.classList.remove('dark');
        icon.classList.replace('fa-sun', 'fa-moon');
    }
}

function toggleDarkMode() {
    const html = document.documentElement;
    const isDark = html.classList.toggle('dark');
    const toggle = document.getElementById('themeToggle');
    const icon = toggle.querySelector('i');

    if (isDark) {
        icon.classList.replace('fa-moon', 'fa-sun');
        localStorage.setItem('spectre-theme', 'dark');
    } else {
        icon.classList.replace('fa-sun', 'fa-moon');
        localStorage.setItem('spectre-theme', 'light');
    }
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
    chart.options.plugins.legend.labels = { color: theme.legendColor };
    chart.update('none');
}

function updateLastRefreshed() {
    const el = document.getElementById('lastRefreshed');
    if (!el) return;
    const now = new Date();
    el.textContent = ` | Last refreshed: ${now.toLocaleTimeString()}`;
}

function formatBytes(bytes) {
    if (bytes === null || bytes === undefined || isNaN(bytes)) return 'No data';
    if (bytes === 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const val = bytes / Math.pow(1024, i);
    return `${val.toFixed(val >= 10 ? 0 : 1)} ${units[i]}`;
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
    initializeChart();
    fetchAllMetrics();
    checkPrometheusConnection();
}

function updateTimestamp() {
    const now = new Date();
    document.getElementById('timestamp').textContent = now.toLocaleString();
}

// Prometheus query function
async function queryPrometheus(query) {
    try {
        const response = await fetch(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(query)}`);
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

// Fetch all metrics
async function fetchAllMetrics() {
    if (isRefreshing) return;
    setRefreshing(true);

    const cardIds = ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'alertsCard', 'containersCard', 'chartCard', 'backupCard', 'securityCard'];
    cardIds.forEach(id => { clearCardError(id); setCardLoading(id, true); });

    try {
        const [
            cpu, mem, disk, netIn, netOut, load1, bootTime, processes, temp,
            backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes,
            spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved,
            findingsCritical, findingsHigh
        ] = await Promise.all([
            queryPrometheus('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))'),
            queryPrometheus('100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'),
            queryPrometheus('100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))'),
            queryPrometheus('rate(node_network_receive_bytes_total[5m])'),
            queryPrometheus('rate(node_network_transmit_bytes_total[5m])'),
            queryPrometheus('node_load1'),
            queryPrometheus('node_boot_time_seconds'),
            queryPrometheus('node_processes_total'),
            queryPrometheus('avg(node_hwmon_temp_celsius)'),
            queryPrometheus('backup_last_success_timestamp'),
            queryPrometheus('backup_health_check_ok'),
            queryPrometheus('backup_health_check_timestamp'),
            queryPrometheus('backup_repo_size_bytes'),
            queryPrometheus('spectre_agent_up'),
            queryPrometheus('spectre_security_ever_scanned'),
            queryPrometheus('security_last_scan_timestamp'),
            queryPrometheus('security_findings_unresolved'),
            queryPrometheus('security_findings_unresolved_by_severity{severity="critical"}'),
            queryPrometheus('security_findings_unresolved_by_severity{severity="high"}')
        ]);

        // Treat all-null from core Prometheus as unreachable
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

        updateBackupStatus(backupLastSuccess, backupHealthOk, backupHealthTs, backupRepoBytes);
        updateSecurityStatus(spectreUp, spectreEverScanned, securityLastScan, findingsUnresolved, findingsCritical, findingsHigh);
        updateContainerStatus();
        checkAlerts();
        const activeRange = document.querySelector('.chart-controls .btn.active')?.dataset.range || '1h';
        updateChart(activeRange);
        updateLastRefreshed();
    } catch (err) {
        console.error('Fetch error:', err);
        showToast('Failed to refresh metrics', 'error');
        ['cpuCard', 'memoryCard', 'diskCard', 'networkCard', 'healthCard', 'backupCard', 'securityCard'].forEach(id => setCardError(id, 'Fetch failed'));
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
    }
}

// Update Network metrics
function updateNetworkMetrics(networkIn, networkOut) {
    if (networkIn !== null && networkOut !== null) {
        const totalMB = ((networkIn + networkOut) / 1024 / 1024).toFixed(2);
        document.getElementById('networkIO').textContent = totalMB + ' MB/s';
        const change = document.getElementById('networkChange');
        if ((networkIn + networkOut) > 100 * 1024 * 1024) { // > 100 MB/s
            change.textContent = 'High';
            change.className = 'stat-change negative';
        } else {
            change.textContent = 'Normal';
            change.className = 'stat-change positive';
        }
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
function updateBackupStatus(lastSuccess, healthOk, healthTs, repoBytes) {
    const statusEl = document.getElementById('backupStatus');
    const lastEl = document.getElementById('lastBackup');
    const sizeEl = document.getElementById('backupSize');

    const hasData = lastSuccess !== null || healthOk !== null || repoBytes !== null;
    if (!hasData) {
        if (statusEl) { statusEl.textContent = 'No data'; statusEl.className = 'badge'; }
        if (lastEl) lastEl.textContent = 'No data';
        if (sizeEl) sizeEl.textContent = 'No data';
        setCardError('backupCard', 'Backup metrics unavailable (exporter may not be running)');
        return;
    }

    if (lastEl) {
        lastEl.textContent = lastSuccess ? formatRelativeTime(lastSuccess) : 'Never';
        if (lastSuccess) lastEl.title = new Date(lastSuccess * 1000).toLocaleString();
    }
    if (sizeEl) sizeEl.textContent = formatBytes(repoBytes);

    if (statusEl) {
        const isHealthy = healthOk === 1;
        const isStale = lastSuccess && (Date.now() / 1000 - lastSuccess) > 86400 * 2;
        if (isHealthy && !isStale) {
            statusEl.textContent = 'OK';
            statusEl.className = 'badge badge-success';
        } else if (healthOk === 0 || isStale) {
            statusEl.textContent = 'Attention';
            statusEl.className = 'badge badge-warning';
        } else {
            statusEl.textContent = 'Unknown';
            statusEl.className = 'badge';
        }
        if (healthTs) statusEl.title = `Last health check: ${new Date(healthTs * 1000).toLocaleString()}`;
    }
    clearCardError('backupCard');
}

// Update Security Status
function updateSecurityStatus(spectreUp, everScanned, lastScan, unresolved, critical, high) {
    const statusEl = document.getElementById('securityStatus');
    const firewallEl = document.getElementById('firewallStatus');
    const fail2banEl = document.getElementById('fail2banStatus');
    const scanEl = document.getElementById('lastSecurityScan');
    const vulnEl = document.getElementById('vulnerabilities');

    // Firewall/Fail2Ban aren't exposed as Prometheus metrics in this suite
    if (firewallEl) firewallEl.textContent = 'No data';
    if (fail2banEl) fail2banEl.textContent = 'No data';

    const hasSecurityMetrics = spectreUp !== null;
    if (!hasSecurityMetrics) {
        if (statusEl) { statusEl.textContent = 'No data'; statusEl.className = 'badge'; }
        if (scanEl) scanEl.textContent = 'No data';
        if (vulnEl) vulnEl.textContent = 'No data';
        setCardError('securityCard', 'Security metrics unavailable');
        return;
    }

    if (spectreUp === 0) {
        if (statusEl) { statusEl.textContent = 'Agent Down'; statusEl.className = 'badge badge-danger'; }
        if (scanEl) scanEl.textContent = 'Agent unavailable';
        if (vulnEl) vulnEl.textContent = 'Unknown';
        setCardError('securityCard', 'Spectre security agent is down');
        return;
    }

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
    const criticalCount = critical !== null ? Math.floor(critical) : 0;
    const highCount = high !== null ? Math.floor(high) : 0;

    if (vulnEl) {
        if (totalFindings !== null) {
            vulnEl.textContent = totalFindings + (criticalCount + highCount > 0 ? ` (${criticalCount} critical, ${highCount} high)` : '');
        } else {
            vulnEl.textContent = 'No data';
        }
    }

    if (statusEl) {
        if (totalFindings === null) {
            statusEl.textContent = 'Unknown';
            statusEl.className = 'badge';
        } else if (criticalCount > 0 || totalFindings > 10) {
            statusEl.textContent = 'At Risk';
            statusEl.className = 'badge badge-danger';
        } else if (highCount > 0 || totalFindings > 0) {
            statusEl.textContent = 'Review';
            statusEl.className = 'badge badge-warning';
        } else {
            statusEl.textContent = 'Secure';
            statusEl.className = 'badge badge-success';
        }
    }
    clearCardError('securityCard');
}

// Update Container Status
async function updateContainerStatus() {
    try {
        // Derive real per-container state from cAdvisor instead of assuming it.
        // cAdvisor reports last seen; an empty label set means no recent data.
        const response = await fetch(`${PROMETHEUS_URL}/api/v1/query?query=${encodeURIComponent(
            'count by (name) (container_last_seen{name!=""})'
        )}`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        const live = new Map((data.data && data.data.result || [])
            .map(r => [r.metric.name, r.value[1]]));
        const expected = ['prometheus', 'grafana', 'alertmanager',
                          'node-exporter', 'cadvisor', 'redis-exporter',
                          'postgres-exporter', 'blackbox-exporter'];
        const containers = expected.map(name => ({
            name,
            status: live.has(name) ? 'running' : 'no-data'
        }));

        const grid = document.getElementById('containersGrid');
        grid.innerHTML = containers.map(container => `
            <div class="container-item">
                <div class="container-name">${container.name}</div>
                <span class="container-status ${container.status}">${container.status}</span>
            </div>
        `).join('');

        const containerStatus = document.getElementById('containerStatus');
        const allRunning = containers.every(c => c.status === 'running');
        containerStatus.textContent = allRunning ? 'All Running' : 'Issues';
        containerStatus.className = allRunning ? 'badge badge-success' : 'badge badge-warning';
        clearCardError('containersCard');
    } catch (error) {
        console.error('Error fetching container status:', error);
        setCardError('containersCard', 'Container data unavailable');
        document.getElementById('containersGrid').innerHTML = '<div class="no-alerts">Unable to fetch container status</div>';
    }
}

// Check Alerts
async function checkAlerts() {
    try {
        const response = await fetch(`${PROMETHEUS_URL}/api/v1/alerts`);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        if (data.status !== 'success' || !Array.isArray(data.data?.alerts)) {
            throw new Error('Invalid alerts response');
        }

        const activeAlerts = data.data.alerts.filter(alert => alert.state === 'firing');
        document.getElementById('alertCount').textContent = activeAlerts.length;

        const alertsList = document.getElementById('alertsList');
        if (activeAlerts.length === 0) {
            alertsList.innerHTML = '<div class="no-alerts">No active alerts</div>';
        } else {
            alertsList.innerHTML = activeAlerts.map(alert => {
                const severity = alert.labels?.severity || 'info';
                const name = alert.labels?.alertname || 'Unnamed alert';
                const description = alert.annotations?.description || '';
                const safeName = document.createElement('span');
                safeName.textContent = name;
                const safeDesc = document.createElement('span');
                safeDesc.textContent = description;
                return `
                <div class="alert-item ${severity}">
                    <div class="alert-title">${safeName.innerHTML}</div>
                    <div class="alert-description">${safeDesc.innerHTML}</div>
                    <div class="alert-time">${new Date(alert.startsAt * 1000).toLocaleString()}</div>
                </div>
            `;
            }).join('');
        }
        clearCardError('alertsCard');
    } catch (error) {
        console.error('Error checking alerts:', error);
        setCardError('alertsCard', 'Alerts unavailable');
        document.getElementById('alertsList').innerHTML = '<div class="no-alerts">Unable to fetch alerts</div>';
    }
}

// Check Prometheus Connection
async function checkPrometheusConnection() {
    const statusIndicator = document.getElementById('systemStatus');
    const statusText = document.getElementById('systemStatusText');
    try {
        const response = await fetch(`${PROMETHEUS_URL}/api/v1/status/buildinfo`);
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
                    tension: 0.4
                },
                {
                    label: 'Memory Usage (%)',
                    data: [],
                    borderColor: '#f5576c',
                    backgroundColor: 'rgba(245, 87, 108, 0.1)',
                    fill: true,
                    tension: 0.4
                },
                {
                    label: 'Disk Usage (%)',
                    data: [],
                    borderColor: '#4facfe',
                    backgroundColor: 'rgba(79, 172, 254, 0.1)',
                    fill: true,
                    tension: 0.4
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
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
                    min: 0,
                    max: 100,
                    grid: { color: theme.gridColor },
                    ticks: { color: theme.tickColor }
                }
            },
            plugins: {
                legend: { position: 'bottom', labels: { color: theme.legendColor } }
            }
        }
    });
}

async function updateChart(range) {
    const secondsMap = { '1h': 3600, '6h': 21600, '24h': 86400, '7d': 604800 };
    const seconds = secondsMap[range] || 3600;
    const step = range === '7d' ? 3600 : 60;
    const spansMultipleDays = seconds > 86400;

    const now = Math.floor(Date.now() / 1000);
    const start = now - seconds;

    const queries = [
        '100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))',
        '100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))',
        '100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))'
    ];

    // Bump the in-flight token; any in-progress fetch is now stale.
    const myToken = ++chartRequestToken;

    try {
        const responses = await Promise.all(queries.map(q =>
            fetch(`${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(q)}&start=${start}&end=${now}&step=${step}`)
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

        const firstSeries = results[0]?.data?.result?.[0]?.values;
        if (!Array.isArray(firstSeries) || firstSeries.length === 0) {
            chart.data.labels = [];
            chart.data.datasets.forEach(d => { d.data = []; });
            chart.update();
            setCardError('chartCard', 'No trend data available');
            return;
        }

        const timestamps = firstSeries.map(v => {
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
        clearCardError('chartCard');
    } catch (e) {
        if (myToken === chartRequestToken) {
            console.error('Error updating chart:', e);
            setCardError('chartCard', 'Chart update failed');
        }
    }
}

// Quick Actions
function runBackup() {
    if (confirm('This will run a system backup. Continue?')) {
        // In production, this would call an API endpoint
        showToast('Backup initiated. Check logs for progress.', 'info');
    }
}

function runMaintenance() {
    if (confirm('This will run system maintenance. Continue?')) {
        // In production, this would call an API endpoint
        showToast('Maintenance initiated. Check logs for progress.', 'info');
    }
}

function runSecurityScan() {
    if (confirm('This will run a security scan. Continue?')) {
        // In production, this would call an API endpoint
        showToast('Security scan initiated. Check logs for progress.', 'info');
    }
}

function viewLogs() {
    // Open logs in new tab or show modal
    showToast('Opening Grafana logs...', 'info');
    window.open('http://localhost:3002', '_blank');
}
