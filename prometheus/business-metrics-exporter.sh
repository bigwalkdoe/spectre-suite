#!/bin/bash
# Business Metrics Exporter for Prometheus textfile collector
# Place metrics in /var/lib/node_exporter/textfile_collector/
#
# Only values measured on this host are exported. The previous version also
# emitted a dozen metrics that were hardcoded to 0 -- app_http_requests_total,
# app_active_users, app_error_rate, app_response_time_seconds,
# backup_duration_seconds and security_vulnerabilities_total -- which were
# indistinguishable from real readings in a graph, and a
# security_last_scan_timestamp set to the current time on every run, which
# asserted that a security scan had just completed. None of them were consumed by
# any alert rule or dashboard, so nothing depends on them.
set -euo pipefail

OUTPUT_DIR="${1:-/var/lib/node_exporter/textfile_collector}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/var/lib/backup-state}"
mkdir -p "$OUTPUT_DIR"

# Prints exactly one number: the count of non-empty lines on stdin, or 0.
#
# The previous `docker ps -q 2>/dev/null | wc -l || echo 0` is wrong under
# pipefail: when the producer fails, wc still prints its own 0 *and* the
# fallback prints a second 0, so the substitution becomes two lines and writes
# a bare "0" into the exposition file. That is not valid Prometheus format, so
# Prometheus rejects the whole textfile and every business metric disappears
# exactly when docker is unavailable. Reading the producer through process
# substitution keeps its exit status out of the pipeline.
count_nonempty() {
    local n
    n=$(grep -c . 2>/dev/null) || n=0
    [ -n "$n" ] || n=0
    printf '%s\n' "$n"
}

# Prints the epoch recorded in a marker file, or 0 when it is absent or
# unreadable. 0 keeps `time() - value > threshold` true, so a missing marker
# alerts rather than silently reading as healthy.
read_marker() {
    local v=""
    if [ -r "$1" ]; then
        v=$(head -1 "$1" 2>/dev/null | tr -cd '0-9' || true)
    fi
    case "$v" in
        '' | *[!0-9]*) printf '0\n' ;;
        *) printf '%s\n' "$v" ;;
    esac
}

# Backup metrics.
# Sourced from markers that scripts/backups/backup-databases.sh writes when a
# run starts and when it completes. The previous implementation reported the
# mtime of /backups/databases as "last successful backup", which was wrong
# twice over: the directory mtime also advances when retention deletes an old
# file, so a directory with no recent backup still looked fresh, and a failed
# backup could not be distinguished from a stale one.
LAST_BACKUP=$(read_marker "$BACKUP_STATE_DIR/last-db-backup-success")
LAST_ATTEMPT=$(read_marker "$BACKUP_STATE_DIR/last-db-backup-attempt")

cat > "$OUTPUT_DIR/backup_metrics.prom" << EOF
# HELP backup_last_success_timestamp Unix timestamp of the last database backup that completed successfully, 0 if none recorded
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp $LAST_BACKUP
# HELP backup_last_attempt_timestamp Unix timestamp of the last database backup run that started, 0 if none recorded
# TYPE backup_last_attempt_timestamp gauge
backup_last_attempt_timestamp $LAST_ATTEMPT
EOF

# System metrics
DOCKER_RUNNING=$(count_nonempty < <(docker ps -q 2>/dev/null))
DOCKER_STOPPED=$(count_nonempty < <(docker ps -aq --filter status=exited --filter status=created --filter status=dead 2>/dev/null))
UPTIME=$(awk '{print $1}' /proc/uptime 2>/dev/null || echo 0)
PROCESSES=$(count_nonempty < <(ps aux --no-headers 2>/dev/null))

cat > "$OUTPUT_DIR/system_metrics.prom" << EOF
# HELP system_uptime_seconds System uptime in seconds
# TYPE system_uptime_seconds gauge
system_uptime_seconds $UPTIME
# HELP system_processes_total Total running processes
# TYPE system_processes_total gauge
system_processes_total $PROCESSES
# HELP system_docker_containers_total Docker containers by state
# TYPE system_docker_containers_total gauge
system_docker_containers_total{state="running"} $DOCKER_RUNNING
# Only genuinely non-running containers. This previously listed all
# containers, running and stopped alike, so the "stopped" series held the total
# container count and double-counted everything also reported as running.
# (No backticks in this comment: this heredoc is unquoted so it expands
# variables, and backticks would be evaluated as a command.)
system_docker_containers_total{state="stopped"} $DOCKER_STOPPED
EOF

rm -f "$OUTPUT_DIR/app_metrics.prom" "$OUTPUT_DIR/security_metrics.prom"

echo "Business metrics exported to $OUTPUT_DIR"
