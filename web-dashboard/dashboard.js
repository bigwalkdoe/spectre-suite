// Dashboard JavaScript
const PROMETHEUS_URL = 'http://localhost:9090';
const REFRESH_INTERVAL = 30000; // 30 seconds

let chart = null;
let chartRequestToken = 0; // Monotonic token to discard stale updateChart responses

// Initialize dashboard
document.addEventListener('DOMContentLoaded', () => {
    initializeDashboard();
    updateTimestamp();
    setInterval(updateTimestamp, 1000);
    setInterval(fetchAllMetrics, REFRESH_INTERVAL);
    
    // Event listeners
    document.getElementById('refreshBtn').addEventListener('click', fetchAllMetrics);
    
    // Chart range buttons
    document.querySelectorAll('.chart-controls .btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
            document.querySelectorAll('.chart-controls .btn').forEach(b => b.classList.remove('active'));
            e.target.classList.add('active');
            updateChart(e.target.dataset.range);
        });
    });
});

function initializeDashboard() {
    fetchAllMetrics();
    initializeChart();
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
    const metrics = await Promise.all([
        queryPrometheus('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))'),
        queryPrometheus('100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))'),
        queryPrometheus('100 * (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}))'),
        queryPrometheus('rate(node_network_receive_bytes_total[5m])'),
        queryPrometheus('rate(node_network_transmit_bytes_total[5m])'),
        queryPrometheus('node_load1'),
        queryPrometheus('node_boot_time_seconds')
    ]);

    updateCPUMetrics(metrics[0]);
    updateMemoryMetrics(metrics[1]);
    updateDiskMetrics(metrics[2]);
    updateNetworkMetrics(metrics[3], metrics[4]);
    updateSystemHealth(metrics[5], metrics[6]);
    updateContainerStatus();
    checkAlerts();
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
function updateSystemHealth(systemLoad, bootTime) {
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

    // Simulated values for demonstration
    document.getElementById('processes').textContent = Math.floor(Math.random() * 200 + 100);
    document.getElementById('temperature').textContent = Math.floor(Math.random() * 20 + 40) + '°C';
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

// Update Container Status
async function updateContainerStatus() {
    try {
        // This would typically come from cAdvisor or Docker API
        // For demo, we'll simulate container status
        const containers = [
            { name: 'prometheus', status: 'running' },
            { name: 'grafana', status: 'running' },
            { name: 'alertmanager', status: 'running' },
            { name: 'node-exporter', status: 'running' },
            { name: 'cadvisor', status: 'running' }
        ];

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

    } catch (error) {
        console.error('Error fetching container status:', error);
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
    } catch (error) {
        console.error('Error checking alerts:', error);
        document.getElementById('alertsList').innerHTML = '<div class="no-alerts">Unable to fetch alerts</div>';
    }
}

// Check Prometheus Connection
async function checkPrometheusConnection() {
    try {
        const response = await fetch(`${PROMETHEUS_URL}/api/v1/status/config`);
        const prometheusStatus = document.getElementById('prometheusStatus');
        if (response.ok) {
            prometheusStatus.textContent = 'Connected';
            prometheusStatus.style.color = '#10b981';
        } else {
            prometheusStatus.textContent = 'Disconnected';
            prometheusStatus.style.color = '#ef4444';
        }
    } catch (error) {
        document.getElementById('prometheusStatus').textContent = 'Disconnected';
        document.getElementById('prometheusStatus').style.color = '#ef4444';
    }
}

// Initialize Chart
function initializeChart() {
    const ctx = document.getElementById('resourceChart').getContext('2d');
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
                    grid: { display: false },
                    ticks: { maxTicksLimit: 10 }
                },
                y: {
                    min: 0,
                    max: 100,
                    grid: { color: 'rgba(0,0,0,0.05)' }
                }
            },
            plugins: {
                legend: { position: 'bottom' }
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
            return;
        }

        const results = await Promise.all(responses.map(r => r.json()));

        if (myToken !== chartRequestToken) return; // recheck after the second await

        if (results.some(d => d.status !== 'success')) {
            console.error('Chart range query returned non-success status');
            return;
        }

        const firstSeries = results[0]?.data?.result?.[0]?.values;
        if (!Array.isArray(firstSeries) || firstSeries.length === 0) {
            chart.data.labels = [];
            chart.data.datasets.forEach(d => { d.data = []; });
            chart.update();
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
    } catch (e) {
        if (myToken === chartRequestToken) {
            console.error('Error updating chart:', e);
        }
    }
}

// Quick Actions
function runBackup() {
    if (confirm('This will run a system backup. Continue?')) {
        // In production, this would call an API endpoint
        alert('Backup initiated. Check logs for progress.');
    }
}

function runMaintenance() {
    if (confirm('This will run system maintenance. Continue?')) {
        // In production, this would call an API endpoint
        alert('Maintenance initiated. Check logs for progress.');
    }
}

function runSecurityScan() {
    if (confirm('This will run a security scan. Continue?')) {
        // In production, this would call an API endpoint
        alert('Security scan initiated. Check logs for progress.');
    }
}

function viewLogs() {
    // Open logs in new tab or show modal
    window.open('http://localhost:3002', '_blank');
}
