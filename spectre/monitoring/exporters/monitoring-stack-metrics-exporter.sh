#!/bin/bash
# Monitoring Stack Metrics Exporter for Prometheus textfile collector.
# Runs spectre/actions/monitoring/check-monitoring-stack.sh in prom format and
# publishes gauges for Prometheus route-prefix health and Grafana datasource
# reachability/config drift. Never prints Grafana credentials.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
export SPECTRE_REPO_ROOT="$_REPO_ROOT"
OUTPUT_DIR="${1:-$_REPO_ROOT/prometheus/business-metrics}"
CHECK="$_REPO_ROOT/spectre/actions/monitoring/check-monitoring-stack.sh"
mkdir -p "$OUTPUT_DIR"

# Run check in prom format; capture output even if it exits non-zero (failures
# are represented in metrics like *_ok 0 / *_healthy 0).
out=""
rc=0
if [ -x "$CHECK" ]; then
  out="$(MONITORING_CHECK_FORMAT=prom SPECTRE_REPO_ROOT="$_REPO_ROOT" "$CHECK" 2>/dev/null)" || rc=$?
else
  ts="$(date +%s)"
  out="# HELP spectre_monitoring_check_timestamp_seconds Unix time this monitoring stack check ran
# TYPE spectre_monitoring_check_timestamp_seconds gauge
spectre_monitoring_check_timestamp_seconds $ts
# HELP spectre_monitoring_check_ok 1 if the monitoring stack check found no failures, 0 otherwise
# TYPE spectre_monitoring_check_ok gauge
spectre_monitoring_check_ok 0"
  rc=1
fi

tmp="$OUTPUT_DIR/.monitoring_stack_metrics.prom.$$"
printf '%s\n' "$out" > "$tmp"
mv "$tmp" "$OUTPUT_DIR/monitoring_stack_metrics.prom"
echo "monitoring stack metrics exported to $OUTPUT_DIR (check_rc=$rc)"
exit 0
