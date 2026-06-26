#!/bin/bash
# Business Metrics Exporter for Prometheus textfile collector
# Place metrics in /var/lib/node_exporter/textfile_collector/
set -euo pipefail

OUTPUT_DIR="${1:-/var/lib/node_exporter/textfile_collector}"
mkdir -p "$OUTPUT_DIR"
DATE=$(date +%s)

# Backup metrics
LAST_BACKUP=$(stat -c %Y /backups/databases 2>/dev/null || echo 0)
cat > "$OUTPUT_DIR/backup_metrics.prom" << EOF
# HELP backup_last_success_timestamp Unix timestamp of last successful backup
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp $LAST_BACKUP
# HELP backup_duration_seconds Duration of last backup in seconds
# TYPE backup_duration_seconds gauge
backup_duration_seconds 0
EOF

# Application metrics
cat > "$OUTPUT_DIR/app_metrics.prom" << EOF
# HELP app_http_requests_total Total HTTP requests
# TYPE app_http_requests_total counter
app_http_requests_total 0
# HELP app_active_users Current active users
# TYPE app_active_users gauge
app_active_users 0
# HELP app_error_rate Current error rate
# TYPE app_error_rate gauge
app_error_rate 0
# HELP app_response_time_seconds Application response time
# TYPE app_response_time_seconds gauge
app_response_time_seconds{quantile="0.5"} 0
app_response_time_seconds{quantile="0.95"} 0
app_response_time_seconds{quantile="0.99"} 0
EOF

# Security metrics
cat > "$OUTPUT_DIR/security_metrics.prom" << EOF
# HELP security_vulnerabilities_total Total vulnerabilities found
# TYPE security_vulnerabilities_total gauge
security_vulnerabilities_total{severity="critical"} 0
security_vulnerabilities_total{severity="high"} 0
security_vulnerabilities_total{severity="medium"} 0
security_vulnerabilities_total{severity="low"} 0
# HELP security_last_scan_timestamp Last security scan timestamp
# TYPE security_last_scan_timestamp gauge
security_last_scan_timestamp $DATE
EOF

# System health metrics
cat > "$OUTPUT_DIR/system_metrics.prom" << EOF
# HELP system_uptime_seconds System uptime in seconds
# TYPE system_uptime_seconds gauge
system_uptime_seconds $(awk '{print $1}' /proc/uptime)
# HELP system_processes_total Total running processes
# TYPE system_processes_total gauge
system_processes_total $(ps aux --no-headers 2>/dev/null | wc -l || echo 0)
# HELP system_docker_containers_total Docker containers by state
# TYPE system_docker_containers_total gauge
system_docker_containers_total{state="running"} $(docker ps -q 2>/dev/null | wc -l || echo 0)
system_docker_containers_total{state="stopped"} $(docker ps -aq 2>/dev/null | wc -l || echo 0)
EOF

echo "Business metrics exported to $OUTPUT_DIR"
