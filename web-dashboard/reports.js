// Pure report logic (no DOM, no fetch). Testable in Node via the section
// before the browser-integration marker. Browser integration
// (initReports, generateReport, renderReport*) lives after the marker.

// Seconds per supported time range.
const RANGE_SECONDS = { "24h": 86400, "7d": 604800, "30d": 2592000, "90d": 7776000 };

// Chart step sizing mirrors updateChart() in dashboard.js: cap at ~400 points.
function rangeStep(seconds) {
    if (seconds === 604800) return 3600; // 7d -> 1h step
    return Math.max(60, Math.ceil(seconds / 400));
}

// Prometheus queries per report type, queried via query_range through the
// same-origin /api/ proxy (nginx rewrites /api/* -> /prometheus/api/*).
function queriesFor(reportType) {
    const core = [
        "100 * (1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])))",
        "100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))",
        "100 * (1 - (node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}))",
        "sum(rate(node_network_receive_bytes_total{device!~\"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*\"}[5m])) + sum(rate(node_network_transmit_bytes_total{device!~\"lo|veth.*|docker.*|br-.*|cni.*|flannel.*|cali.*\"}[5m]))",
    ];
    const byType = {
        backup: [
            "backup_last_success_timestamp",
            "restic_last_success_timestamp",
            "max(restic_health_ok)",
            "max(restic_verify_ok)",
        ],
        security: [
            "security_findings_unresolved",
            'security_findings_unresolved_by_severity{severity="critical"}',
            "security_last_scan_timestamp",
            "spectre_agent_up",
        ],
        alerts: ['ALERTS{alertname!=""}'],
        system: core,
    };
    return byType[reportType] || byType.system;
}

function labelsFor(reportType) {
    const byType = {
        backup: "Backup & Restic Health",
        security: "Security Findings",
        alerts: "Alert History",
        system: "System Health",
    };
    return byType[reportType] || byType.system;
}

// Build the query_range requests for a report type + range.
// Returns { queries: string[], label: string, seconds: number }.
function buildReportQueries(reportType, range) {
    const seconds = RANGE_SECONDS[range] || RANGE_SECONDS["7d"];
    return {
        queries: queriesFor(reportType),
        label: labelsFor(reportType),
        seconds,
    };
}

// Format a single gauge value for display. null/undefined -> null (rendered
// as "No data" by the caller).
function formatReportValue(value, _metric) {
    if (value === null || value === undefined) return null;
    if (typeof value === "number") return String(value);
    return String(value);
}

// CSV export: timestamp,value rows. Each series row contributes its first
// value (single-metric reports); multi-series can extend the header later.
function buildCSV(labels, series) {
    const lines = ["timestamp,value"];
    for (let i = 0; i < labels.length; i++) {
        const value = series && series[i] ? series[i][0] : "";
        lines.push(`${escapeCsv(labels[i])},${escapeCsv(String(value))}`);
    }
    return lines.join("\n");
}

function escapeCsv(s) {
    const str = String(s);
    if (/[",\n]/.test(str)) return `"${str.replace(/"/g, '""')}"`;
    return str;
}

// JSON export: pretty-printed payload.
function buildJSON(payload) {
    return JSON.stringify(payload, null, 2);
}

// ==== BROWSER-INTEGRATION ====

// Initializes the Reports page: wires pickers, Generate, and Export buttons.
function initReports() {
    const generate = document.getElementById("reportGenerate");
    const typeSel = document.getElementById("reportType");
    const rangeSel = document.getElementById("reportRange");
    if (!generate || !typeSel || !rangeSel) return;

    // Restore last selection.
    const savedType = localStorage.getItem("spectre-report-type");
    const savedRange = localStorage.getItem("spectre-report-range");
    if (savedType) typeSel.value = savedType;
    if (savedRange) rangeSel.value = savedRange;

    generate.addEventListener("click", () => {
        generateReport(typeSel.value, rangeSel.value);
    });

    document.getElementById("reportExportJson")?.addEventListener("click", () =>
        exportReport("json")
    );
    document.getElementById("reportExportCsv")?.addEventListener("click", () =>
        exportReport("csv")
    );

    // Auto-generate on load with restored/ default selection.
    generateReport(typeSel.value, rangeSel.value);
}

// Fetch historical data from Prometheus (query_range via /api/ proxy) and
// render chart + table. Degrades gracefully on error / no data.
async function generateReport(reportType, range) {
    localStorage.setItem("spectre-report-type", reportType);
    localStorage.setItem("spectre-report-range", range);

    const card = document.getElementById("reportsCard");
    const chartBody = document.getElementById("reportChartBody");
    const table = document.getElementById("reportTable");
    const empty = document.getElementById("reportEmpty");
    const tbody = table.querySelector("tbody");

    const { queries, label, seconds } = buildReportQueries(reportType, range);
    document.getElementById("reportChart")?.setAttribute(
        "aria-label",
        `${label} trend (${range})`
    );

    setReportLoading(true);
    clearReportError();
    empty.hidden = true;
    table.hidden = false;
    tbody.innerHTML = "";

    const now = Math.floor(Date.now() / 1000);
    const start = now - seconds;

    try {
        const results = await Promise.all(
            queries.map((q) =>
                fetchWithTimeout(
                    `${PROMETHEUS_URL}/api/v1/query_range?query=${encodeURIComponent(q)}&start=${start}&end=${now}&step=${rangeStep(seconds)}`,
                    {},
                    20000
                )
            )
        );

        if (results.some((r) => !r.ok)) {
            showReportError("Prometheus returned an error while generating the report.");
            return;
        }

        const parsed = await Promise.all(results.map((r) => r.json()));
        if (parsed.some((d) => d.status !== "success")) {
            showReportError("Prometheus returned no usable data for this report.");
            return;
        }

        const series = parsed.map((d) => {
            const vals = d.data?.result?.[0]?.values;
            return Array.isArray(vals) ? vals.map((v) => parseFloat(v[1])) : [];
        });
        const labelSeries = parsed.find(
            (d) => Array.isArray(d.data?.result?.[0]?.values) && d.data.result[0].values.length > 0
        );
        const timestamps = labelSeries
            ? labelSeries.data.result[0].values.map((v) => new Date(v[0] * 1000).toISOString())
            : [];

        if (timestamps.length === 0) {
            showReportEmpty();
            return;
        }

        renderReportChart(timestamps, series, label);
        renderReportTable(timestamps, series);
    } catch (e) {
        showReportError("Failed to generate report.");
    } finally {
        setReportLoading(false);
    }
}

function renderReportChart(timestamps, series, label) {
    const ctx = document.getElementById("reportChart")?.getContext("2d");
    if (!ctx) return;
    // Reuse the existing Chart.js global if a chart already exists on this canvas.
    let chart = ctx.chart;
    if (!chart) {
        chart = new Chart(ctx, {
            type: "line",
            data: { labels: timestamps, datasets: [] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: true }, title: { display: true, text: label } },
                scales: { x: { display: true }, y: { display: true } },
            },
        });
        ctx.chart = chart;
    }
    chart.data.labels = timestamps;
    chart.data.datasets = series.map((vals, i) => ({
        label: `Series ${i + 1}`,
        data: vals,
        borderWidth: 2,
        pointRadius: 0,
        fill: false,
    }));
    chart.update();
}

function renderReportTable(timestamps, series) {
    const table = document.getElementById("reportTable");
    const tbody = table.querySelector("tbody");
    tbody.innerHTML = "";
    for (let i = 0; i < timestamps.length; i++) {
        const row = document.createElement("tr");
        const tsCell = document.createElement("td");
        tsCell.textContent = timestamps[i];
        row.appendChild(tsCell);
        const valCell = document.createElement("td");
        const value = series && series[0] ? series[0][i] : "";
        valCell.textContent = formatReportValue(value, "");
        row.appendChild(valCell);
        tbody.appendChild(row);
    }
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
    showToast(message, "error");
}

function clearReportError() {
    const card = document.getElementById("reportsCard");
    if (!card) return;
    card.classList.remove("card--error", "card--loading");
    card.setAttribute("aria-busy", "false");
    const el = card.querySelector(".error-message");
    if (el) el.remove();
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

function exportReport(format) {
    const table = document.getElementById("reportTable");
    const tbody = table.querySelector("tbody");
    const rows = Array.from(tbody.querySelectorAll("tr")).map((tr) => {
        const cells = tr.querySelectorAll("td");
        return [cells[0]?.textContent || "", cells[1]?.textContent || ""];
    });
    const labels = rows.map((r) => r[0]);
    const series = [rows.map((r) => parseFloat(r[1]) || 0)];

    const type = document.getElementById("reportType")?.value || "report";
    const range = document.getElementById("reportRange")?.value || "range";
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");

    if (format === "csv") {
        const csv = buildCSV(labels, series);
        downloadBlob(csv, `text/csv`, `spectre-report-${type}-${range}-${stamp}.csv`);
        showToast("Report exported (CSV)", "success");
    } else {
        const payload = {
            exportedAt: new Date().toISOString(),
            reportType: type,
            reportRange: range,
            labels,
            series,
        };
        const json = buildJSON(payload);
        try {
            void navigator.clipboard.writeText(json);
            showToast("Report JSON copied to clipboard", "success");
        } catch (e) {
            downloadBlob(json, "application/json", `spectre-report-${type}-${range}-${stamp}.json`);
            showToast("Report downloaded (clipboard unavailable)", "info");
        }
    }
}

function downloadBlob(content, mime, filename) {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
}

// Boot when the DOM is ready.
if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initReports);
} else {
    initReports();
}
