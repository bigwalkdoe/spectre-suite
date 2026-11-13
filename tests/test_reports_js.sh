#!/bin/bash
# Tests for pure report logic in web-dashboard/reports.js
# Runs under Node (no browser/DOM needed). Exits non-zero on any failure.
set -euo pipefail

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

if [ ! -f web-dashboard/reports.js ]; then
    fail "web-dashboard/reports.js does not exist"
    exit 1
fi

node << 'NODEEOF'
const fs = require("fs");
const code = fs.readFileSync("web-dashboard/reports.js", "utf8");
// Pure section is everything before the browser-integration marker.
const marker = "// ==== BROWSER-INTEGRATION ====";
const pure = code.split(marker)[0];
const sandbox = {};
new Function("sandbox", pure + `
sandbox.buildReportQueries = buildReportQueries;
sandbox.formatReportValue = formatReportValue;
sandbox.buildCSV = buildCSV;
sandbox.buildJSON = buildJSON;
`)(sandbox);

const {
    buildReportQueries,
    formatReportValue,
    buildCSV,
    buildJSON,
} = sandbox;

let ok = true;
function assert(name, actual, expected) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) {
        console.log("PASS:", name);
    } else {
        console.log("FAIL:", name, "expected", e, "got", a);
        ok = false;
    }
}

// ---- buildReportQueries ----
const bq = buildReportQueries("backup", "7d");
assert("backup 7d is object", typeof bq, "object");
assert("backup 7d has queries array", Array.isArray(bq.queries), true);
const bj = bq.queries.join("|");
assert("backup includes backup_last_success_timestamp", bj.includes("backup_last_success_timestamp"), true);
assert("backup includes restic_last_success_timestamp", bj.includes("restic_last_success_timestamp"), true);
assert("backup includes restic_health_ok", bj.includes("restic_health_ok"), true);
assert("backup includes restic_verify_ok", bj.includes("restic_verify_ok"), true);
assert("backup label", bq.label, "Backup & Restic Health");
assert("backup 7d seconds", bq.seconds, 604800);
assert("backup queries are raw (no start param)", !bj.includes("&start="), true);

const sq = buildReportQueries("security", "24h");
const sj = sq.queries.join("|");
assert("security includes security_findings_unresolved", sj.includes("security_findings_unresolved"), true);
assert("security includes security_last_scan_timestamp", sj.includes("security_last_scan_timestamp"), true);
assert("security includes spectre_agent_up", sj.includes("spectre_agent_up"), true);
assert("security label", sq.label, "Security Findings");
assert("security 24h seconds", sq.seconds, 86400);

const sysq = buildReportQueries("system", "30d");
const sysj = sysq.queries.join("|");
assert("system includes node_cpu_seconds_total", sysj.includes("node_cpu_seconds_total"), true);
assert("system includes node_memory_MemAvailable_bytes", sysj.includes("node_memory_MemAvailable_bytes"), true);
assert("system includes node_filesystem_avail_bytes", sysj.includes("node_filesystem_avail_bytes"), true);
assert("system label", sysq.label, "System Health");
assert("system 30d seconds", sysq.seconds, 2592000);

const aq = buildReportQueries("alerts", "7d");
assert("alerts label", aq.label, "Alert History");
assert("alerts 7d seconds", aq.seconds, 604800);

// range table
assert("range 24h seconds", buildReportQueries("system", "24h").seconds, 86400);
assert("range 7d seconds", buildReportQueries("system", "7d").seconds, 604800);
assert("range 30d seconds", buildReportQueries("system", "30d").seconds, 2592000);
assert("range 90d seconds", buildReportQueries("system", "90d").seconds, 7776000);

// unknown report type falls back to system health
const uq = buildReportQueries("nope", "24h");
assert("unknown falls back to system label", uq.label, "System Health");

// ---- formatReportValue ----
assert("format null", formatReportValue(null, "x"), null);
assert("format undefined", formatReportValue(undefined, "x"), null);
assert("format number", formatReportValue(0.85, "x"), "0.85");
assert("format integer", formatReportValue(42, "x"), "42");

// ---- buildCSV ----
const csv = buildCSV(["t1", "t2"], [[1, 2], [3, 4]]);
const csvLines = csv.split("\n");
assert("CSV header", csvLines[0], "timestamp,value");
assert("CSV row count", csvLines.length, 3);
assert("CSV row 1", csvLines[1], "t1,1");
assert("CSV row 2", csvLines[2], "t2,3");

// ---- buildJSON ----
const json = buildJSON({ exportedAt: "2026-01-01T00:00:00.000Z" });
const parsed = JSON.parse(json);
assert("JSON exportedAt", parsed.exportedAt, "2026-01-01T00:00:00.000Z");

if (!ok) {
    console.log("\nSOME TESTS FAILED");
    process.exit(1);
}
console.log("\nALL PURE-FUNCTION TESTS PASSED");
NODEEOF

if [ $FAIL -ne 0 ]; then exit 1; fi
