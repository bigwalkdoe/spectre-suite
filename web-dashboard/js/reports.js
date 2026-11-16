import { PROMETHEUS_URL } from './config.js';
import { fetchWithTimeout, showToast, escapeHtml } from './dom.js';

// Pure report logic (exported for potential reuse/testing if imported as module).
export const RANGE_SECONDS = { "24h": 86400, "7d": 604800, "30d": 2592000, "90d": 7776000 };

export function rangeStep(seconds) {
    if (seconds === RANGE_SECONDS["7d"]) return 3600; // 7d -> 1h step
    return Math.max(60, Math.ceil(seconds / 400));
}

export function reportDefinition(reportType) {
    const core = [
        { query: "100 * (1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))", label: "CPU (%)" },
        { query: "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))", label: "Memory (%)" },
        { query: "100 * (1 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}))", label: "Disk (%)" },
        {
            query: "sum(rate(node_network_receive_bytes_total{device!~\"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*\"}[5m])) + sum(rate(node_network_transmit_bytes_total{device!~\"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*\"}[5m]))",
            label: "Network RX+TX (B/s)",
        },
    ];
    const byType = {
        backup: {
            label: "Backup & Restic Health",
            series: [
                { query: "backup_last_success_timestamp", label: "Backup last success (ts)" },
                { query: "restic_last_success_timestamp", label: "Restic last success (ts)" },
                { query: "max(restic_health_ok)", label: "Restic health ok" },
                { query: "max(restic_verify_ok)", label: "Restic verify ok" },
            ],
        },
        security: {
            label: "Security Findings",
            series: [
                { query: "security_findings_unresolved", label: "Unresolved findings" },
                { query: 'security_findings_unresolved_by_severity{severity="critical"}', label: "Critical findings" },
                { query: "security_last_scan_timestamp", label: "Last scan (ts)" },
                { query: "spectre_agent_up", label: "Agent up" },
            ],
        },
        alerts: {
            label: "Alert History",
            series: [{ query: 'ALERTS{alertname!=""}', label: "Firing alerts" }],
        },
        system: { label: "System Health", series: core },
    };
    return byType[reportType] || byType.system;
}

export function queriesFor(reportType) { return reportDefinition(reportType).series.map((s) => s.query); }
export function labelsFor(reportType) { return reportDefinition(reportType).label; }
export function seriesLabelsFor(reportType) { return reportDefinition(reportType).series.map((s) => s.label); }

export function buildReportQueries(reportType, range) {
    const seconds = RANGE_SECONDS[range] || RANGE_SECONDS["7d"];
    return { queries: queriesFor(reportType), label: labelsFor(reportType), seriesLabels: seriesLabelsFor(reportType), seconds };
}

export function formatReportValue(value, _metric) {
    if (value === null || value === undefined || Number.isNaN(value)) return "No data";
    if (typeof value === "number") return Number.isInteger(value) ? String(value) : value.toFixed(3).replace(/\.?0+$/, "");
    return String(value);
}

export function buildCSV(labels, series, seriesLabels) {
    const cols = Array.isArray(seriesLabels) && seriesLabels.length ? seriesLabels : (series || []).map((_, i) => `series_${i + 1}`);
    const header = ["timestamp", ...cols];
    const lines = [header.map(escapeCsv).join(",")];
    for (let i = 0; i < (labels || []).length; i++) {
        const row = [labels[i]];
        for (let s = 0; s < (series || []).length; s++) {
            const v = series[s] && series[s][i] !== undefined ? series[s][i] : "";
            row.push(v === null || Number.isNaN(v) ? "" : v);
        }
        lines.push(row.map((v) => escapeCsv(String(v))).join(","));
    }
    return lines.join("\n");
}

function escapeCsv(s) {
    const str = String(s);
    if (/[",\n]/.test(str)) return `"${str.replace(/"/g, '""')}"`;
    return str;
}

export function buildJSON(payload) { return JSON.stringify(payload, null, 2); }

// ==== Browser integration ====
let currentReport = null;
let reportRequestId = 0;

function getReportChart() {
    const ctx = document.getElementById("reportChart")?.getContext("2d");
    if (!ctx) return null;
    if (ctx.chart) return ctx.chart;
    if (typeof Chart === "undefined") return null;
    const chart = new Chart(ctx, {
        type: "line",
        data: { labels: [], datasets: [] },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { display: true }, title: { display: true, text: "" } },
            scales: { x: { display: true }, y: { display: true } },
        },
    });
    ctx.chart = chart;
    return chart;
}

function clearReportChart() {
    const chart = getReportChart();
    if (!chart) return;
    chart.data.labels = [];
    chart.data.datasets = [];
    if (chart.options?.plugins?.title) chart.options.plugins.title.text = "";
    chart.update();
}

function showReportTable() {
    const empty = document.getElementById("reportEmpty");
    const table = document.getElementById("reportTable");
    if (empty) empty.hidden = true;
    if (table) table.hidden = false;
}

function showReportEmpty() {
    const empty = document.getElementById("reportEmpty");
    const table = document.getElementById("reportTable");
    if (empty) empty.hidden = false;
    if (table) table.hidden = true;
}

function setReportLoading(isLoading) {
    const card = document.getElementById("reportsCard");
    if (!card) return;
    card.classList.toggle("card--loading", isLoading);
    card.setAttribute("aria-busy", isLoading ? "true" : "false");
}

function clearReportError() {
    const card = document.getElementById("reportsCard");
    if (!card) return;
    card.classList.remove("card--error", "card--loading");
    card.setAttribute("aria-busy", "false");
    const el = card.querySelector(".error-message");
    if (el) el.remove();
}

function showReportError(message) {
    const card = document.getElementById("reportsCard");
    if (card) {
        card.classList.add("card--error");
        card.setAttribute("aria-busy", "false");
        let el = card.querySelector(".error-message");
        if (!el) {
            el = document.createElement("div");
            el.className = "error-message";
            el.setAttribute("role", "alert");
            const body = card.querySelector(".card-body") || card;
            body.appendChild(el);
        }
        el.innerHTML = `<i class="fas fa-exclamation-circle" aria-hidden="true"></i> ${escapeHtml(message)}`;
    }
    showReportTable();
    showToast(message, "error");
}

function renderReportChart(timestamps, series, label, seriesLabels) {
    const chart = getReportChart();
    if (!chart) return;
    const colors = ["#2563eb", "#dc2626", "#16a34a", "#d97706", "#7c3aed", "#0891b2"];
    chart.data.labels = timestamps;
    chart.data.datasets = series.map((vals, i) => ({
        label: (seriesLabels && seriesLabels[i]) || `Series ${i + 1}`,
        data: vals,
        borderColor: colors[i % colors.length],
        backgroundColor: colors[i % colors.length],
        borderWidth: 2,
        pointRadius: 0,
        fill: false,
        spanGaps: true,
        tension: 0.15,
    }));
    if (chart.options?.plugins?.title) chart.options.plugins.title.text = label || "";
    if (chart.options?.plugins?.legend) chart.options.plugins.legend.display = series.length > 1;
    chart.update();
}

function renderReportTable(timestamps, series, seriesLabels) {
    const table = document.getElementById("reportTable");
    const theadRow = table?.querySelector("thead tr");
    const tbody = table?.querySelector("tbody");
    if (!table || !theadRow || !tbody) return;
    const cols = Array.isArray(seriesLabels) && seriesLabels.length ? seriesLabels : (series || []).map((_, i) => `Series ${i + 1}`);
    theadRow.innerHTML = "";
    ["Timestamp", ...cols].forEach((h) => { const th = document.createElement("th"); th.textContent = h; theadRow.appendChild(th); });
    tbody.innerHTML = "";
    const limit = Math.min(timestamps.length, 500);
    for (let i = timestamps.length - limit; i < timestamps.length; i++) {
        const row = document.createElement("tr");
        const tsCell = document.createElement("td");
        tsCell.textContent = timestamps[i];
        row.appendChild(tsCell);
        for (let s = 0; s < cols.length; s++) {
            const td = document.createElement("td");
            const value = series && series[s] ? series[s][i] : null;
            td.textContent = formatReportValue(value, cols[s]);
            row.appendChild(td);
        }
        tbody.appendChild(row);
    }
}

async function generateReport(reportType, range) {
    localStorage.setItem("spectre-report-type", reportType);
    localStorage.setItem("spectre-report-range", range);
    const table = document.getElementById("reportTable");
    const tbody = table?.querySelector("tbody");
    if (!table || !tbody) return;

    const { queries, label, seriesLabels, seconds } = buildReportQueries(reportType, range);
    document.getElementById("reportChart")?.setAttribute("aria-label", `${label} trend (${range})`);

    const requestId = ++reportRequestId;
    setReportLoading(true);
    clearReportError();
    showReportTable();
    tbody.innerHTML = "";

    const now = Math.floor(Date.now() / 1000);
    const start = now - seconds;
    try {
        const results = await Promise.all(queries.map((q) => fetchWithTimeout(`${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(q)}&start=${start}&end=${now}&step=${rangeStep(seconds)}`, {}, 20000)));
        if (requestId !== reportRequestId) return;
        if (results.some((r) => !r.ok)) {
            currentReport = null; clearReportChart();
            showReportError("Prometheus returned an error while generating the report.");
            return;
        }
        const parsed = await Promise.all(results.map((r) => r.json()));
        if (requestId !== reportRequestId) return;
        if (parsed.some((d) => d.status !== "success")) {
            currentReport = null; clearReportChart();
            showReportError("Prometheus returned no usable data for this report.");
            return;
        }
        const series = parsed.map((d) => {
            const vals = d.data?.result?.[0]?.values;
            return Array.isArray(vals) ? vals.map((v) => { const n = parseFloat(v[1]); return Number.isFinite(n) ? n : null; }) : [];
        });
        const labelSeries = parsed.find((d) => Array.isArray(d.data?.result?.[0]?.values) && d.data.result[0].values.length > 0);
        const timestamps = labelSeries ? labelSeries.data.result[0].values.map((v) => new Date(v[0] * 1000).toISOString()) : [];
        if (timestamps.length === 0) {
            currentReport = null; clearReportChart();
            showReportEmpty();
            return;
        }
        currentReport = { reportType, range, label, seriesLabels, timestamps, series, exportedAt: new Date().toISOString() };
        renderReportChart(timestamps, series, label, seriesLabels);
        renderReportTable(timestamps, series, seriesLabels);
    } catch (e) {
        if (requestId !== reportRequestId) return;
        currentReport = null; clearReportChart();
        showReportError("Failed to generate report.");
    } finally {
        if (requestId === reportRequestId) setReportLoading(false);
    }
}

function downloadBlob(content, mime, filename) {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = filename;
    document.body.appendChild(a); a.click(); a.remove();
    URL.revokeObjectURL(url);
}

function exportReport(format) {
    const type = document.getElementById("reportType")?.value || "report";
    const range = document.getElementById("reportRange")?.value || "range";
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    if (!currentReport || !currentReport.timestamps || currentReport.timestamps.length === 0) {
        showToast("No report data to export", "error");
        return;
    }
    const { timestamps, series, seriesLabels } = currentReport;
    if (format === "csv") {
        downloadBlob(buildCSV(timestamps, series, seriesLabels), "text/csv", `spectre-report-${type}-${range}-${stamp}.csv`);
        showToast("Report exported (CSV)", "success");
    } else {
        const payload = { exportedAt: new Date().toISOString(), reportType: type, reportRange: range, labels: timestamps, seriesLabels, series };
        const json = buildJSON(payload);
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(json).then(
                () => showToast("Report JSON copied to clipboard", "success"),
                () => { downloadBlob(json, "application/json", `spectre-report-${type}-${range}-${stamp}.json`); showToast("Report downloaded (clipboard unavailable)", "info"); }
            );
        } else {
            downloadBlob(json, "application/json", `spectre-report-${type}-${range}-${stamp}.json`);
            showToast("Report downloaded (clipboard unavailable)", "info");
        }
    }
}

export function initReports() {
    const generate = document.getElementById("reportGenerate");
    const typeSel = document.getElementById("reportType");
    const rangeSel = document.getElementById("reportRange");
    if (!generate || !typeSel || !rangeSel) return;

    const savedType = localStorage.getItem("spectre-report-type");
    const savedRange = localStorage.getItem("spectre-report-range");
    if (savedType && typeSel.querySelector(`option[value="${CSS.escape(savedType)}"]`)) typeSel.value = savedType;
    if (savedRange && rangeSel.querySelector(`option[value="${CSS.escape(savedRange)}"]`)) rangeSel.value = savedRange;

    generate.addEventListener("click", () => generateReport(typeSel.value, rangeSel.value));
    document.getElementById("reportExportJson")?.addEventListener("click", () => exportReport("json"));
    document.getElementById("reportExportCsv")?.addEventListener("click", () => exportReport("csv"));

    generateReport(typeSel.value, rangeSel.value);
}

if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initReports);
} else {
    initReports();
}
