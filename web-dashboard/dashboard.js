// Dashboard JavaScript
const PROMETHEUS_URL = 'http://localhost:9090';
const REFRESH_INTERVAL = 30000; // 30 seconds

let chart = null;

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
        const data = await response.json();
        if (data.status === 'success' && data.data.result.length > 0) {
            return parseFloat(data.data.result[0].value[1]);
        }
        return null;
    } catch (error) {
        console.error('Error querying Prometheus:', error);
        return null;
    }
}

// Range query for charts
async function queryPrometheusRange(query, range = '1h') {
    try {
        const response = await fetch(`${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(query)}&start=${Date.now()/1000 - 3600}&end=${Date.now()/1000}&step=60`);
        const data = await response.json();
        if (data.status === 'success' && data.data.result.length > 0) {
            return data.data.result[0].values.map(v => ({
                timestamp: v[0] * 1000,
                value: parseFloat(v[1])
            }));
        }
        return [];
    } catch (error) {
        console.error('Error querying Prometheus range:', error);
        return [];
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
        const data = await response.json();
        
        const activeAlerts = data.data.alerts.filter(alert => alert.state === 'firing');
        document.getElementById('alertCount').textContent = activeAlerts.length;

        const alertsList = document.getElementById('alertsList');
        if (activeAlerts.length === 0) {
            alertsList.innerHTML = '<div class="no-alerts">No active alerts</div>';
        } else {
            alertsList.innerHTML = activeAlerts.map(alert => `
                <div class="alert-item ${alert.labels.severity}">
                    <div class="alert-title">${alert.labels.alertname}</div>
                    <div class="alert-description">${alert.annotations.description}</div>
                    <div class="alert-time">${new Date(alert.startsAt * 1000).toLocaleString()}</div>
                </div>
            `).join('');
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
    
    // Simple chart implementation (would use Chart.js in production)
    // For demo, we'll create a placeholder
    chart = {
        update: function(data) {
            // Chart update logic
        }
    };
}

async function updateChart(range) {
    // Fetch range data and update chart
    const cpuData = await queryPrometheusRange('100 * (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])))', range);
    // Update chart with data
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
