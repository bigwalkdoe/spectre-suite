import { PROMETHEUS_URL } from './config.js';
import { state } from './state.js';
import { fetchWithTimeout, setCardError, clearCardError, setCardUpdated, formatBytesPerSec, showToast, escapeHtml } from './dom.js';

export function getChartTheme() {
    const isDark = document.documentElement.classList.contains('dark');
    return {
        gridColor: isDark ? 'rgba(148, 163, 184, 0.15)' : 'rgba(0,0,0,0.05)',
        tickColor: isDark ? '#94a3b8' : '#666',
        legendColor: isDark ? '#e2e8f0' : '#333',
        tooltipBg: isDark ? '#1e293b' : '#ffffff',
        tooltipText: isDark ? '#e2e8f0' : '#1e293b',
        tooltipBorder: isDark ? '#475569' : '#cbd5e1',
    };
}

export function applyChartTheme() {
    const chart = state.chart;
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

export function initializeChart() {
    const canvas = document.getElementById('resourceChart');
    if (!canvas || typeof canvas.getContext !== 'function' || typeof Chart === 'undefined') {
        setCardError('chartCard', 'Chart library unavailable');
        return;
    }
    const ctx = canvas.getContext('2d');
    const theme = getChartTheme();
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    state.chart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [
                { label: 'CPU Usage (%)', data: [], borderColor: '#667eea', backgroundColor: 'rgba(102, 126, 234, 0.1)', fill: true, tension: 0.4, pointRadius: 0, pointHoverRadius: 3, borderWidth: 1.5 },
                { label: 'Memory Usage (%)', data: [], borderColor: '#f5576c', backgroundColor: 'rgba(245, 87, 108, 0.1)', fill: true, tension: 0.4, pointRadius: 0, pointHoverRadius: 3, borderWidth: 1.5 },
                { label: 'Disk Usage (%)', data: [], borderColor: '#4facfe', backgroundColor: 'rgba(79, 172, 254, 0.1)', fill: true, tension: 0.4, pointRadius: 0, pointHoverRadius: 3, borderWidth: 1.5 },
                { label: 'Network I/O (RX+TX, 5m rate)', data: [], borderColor: '#f59e0b', backgroundColor: 'rgba(245, 158, 11, 0.1)', fill: true, tension: 0.4, pointRadius: 0, pointHoverRadius: 3, borderWidth: 1.5, yAxisID: 'y1' }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation: reduceMotion ? false : { duration: 150 },
            interaction: { intersect: false, mode: 'index' },
            scales: {
                x: { grid: { display: false, color: theme.gridColor }, ticks: { maxTicksLimit: 10, color: theme.tickColor } },
                y: { type: 'linear', position: 'left', min: 0, max: 100, grid: { color: theme.gridColor }, ticks: { color: theme.tickColor, callback: (v) => v + '%' }, title: { display: true, text: 'Usage', color: theme.tickColor } },
                y1: { type: 'linear', position: 'right', min: 0, beginAtZero: true, grid: { drawOnChartArea: false, color: theme.gridColor }, ticks: { color: theme.tickColor, callback: (v) => formatBytesPerSec(v) }, title: { display: true, text: 'Network', color: theme.tickColor } }
            },
            plugins: {
                legend: { position: 'bottom', labels: { color: theme.legendColor, usePointStyle: true, boxWidth: 8, boxHeight: 8, padding: 14 } },
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
                            if (ctx.dataset.yAxisID === 'y1') return ` ${ctx.dataset.label}: ${formatBytesPerSec(v)}`;
                            return ` ${ctx.dataset.label}: ${Number.isFinite(v) ? v.toFixed(1) : '—'}%`;
                        }
                    }
                }
            }
        }
    });
}

export async function updateChart(range) {
    const chart = state.chart;
    if (!chart) {
        setCardError('chartCard', 'Chart unavailable');
        return;
    }
    const secondsMap = { '1h': 3600, '6h': 21600, '24h': 86400, '7d': 604800 };
    const seconds = secondsMap[range] || 3600;
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

    const myToken = ++state.chartRequestToken;
    try {
        const responses = await Promise.all(queries.map(q =>
            fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(q)}&start=${start}&end=${now}&step=${step}`, {}, 20000)
        ));
        if (myToken !== state.chartRequestToken) return;
        if (responses.some(r => !r.ok)) {
            console.error('Chart range query failed:', responses.map((r, i) => `${i}: HTTP ${r.status}`).join(', '));
            setCardError('chartCard', 'Chart data unavailable');
            return;
        }
        const results = await Promise.all(responses.map(r => r.json()));
        if (myToken !== state.chartRequestToken) return;
        if (results.some(d => d.status !== 'success')) {
            console.error('Chart range query returned non-success status');
            setCardError('chartCard', 'Chart data unavailable');
            return;
        }

        const labelSeries = results.map(r => r?.data?.result?.[0]?.values).find(v => Array.isArray(v) && v.length > 0);
        if (!labelSeries) {
            chart.data.labels = [];
            chart.data.datasets.forEach(d => { d.data = []; });
            chart.update();
            state.lastChartRefreshAt = Date.now();
            setCardError('chartCard', 'No trend data available');
            return;
        }

        chart.data.labels = labelSeries.map(v => {
            const d = new Date(v[0] * 1000);
            return spansMultipleDays
                ? d.toLocaleString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
                : d.toLocaleTimeString();
        });
        chart.data.datasets.forEach((dataset, i) => {
            dataset.data = results[i]?.data?.result?.[0]?.values?.map(v => parseFloat(v[1])) || [];
        });
        chart.update();
        state.lastChartRefreshAt = Date.now();
        clearCardError('chartCard');
        setCardUpdated('chartCard');
    } catch (e) {
        if (myToken === state.chartRequestToken) {
            console.error('Error updating chart:', e);
            setCardError('chartCard', 'Chart update failed');
        }
    }
}

export function exportChartCSV() {
    const chart = state.chart;
    if (!chart || !chart.data || !chart.data.labels || chart.data.labels.length === 0) {
        showToast('No chart data to export', 'error');
        return;
    }
    const labels = chart.data.labels;
    const datasets = chart.data.datasets;
    const csvCell = (value) => {
        const text = String(value ?? '');
        return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
    };
    const headers = ['Timestamp', ...datasets.map(d => d.label || 'Series')];
    const rows = [headers.map(csvCell).join(',')];
    for (let i = 0; i < labels.length; i++) {
        const row = [labels[i]];
        for (let j = 0; j < datasets.length; j++) {
            const value = datasets[j].data[i];
            row.push(value !== undefined && value !== null ? Number(value).toFixed(2) : '');
        }
        rows.push(row.map(csvCell).join(','));
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
