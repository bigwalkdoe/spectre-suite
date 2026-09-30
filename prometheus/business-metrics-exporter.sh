#!/bin/bash
# Business Metrics Exporter for Prometheus textfile collector
#
# Writes .prom files into prometheus/business-metrics/, which
# docker-compose.monitoring.yml bind-mounts at /textfile into node-exporter and
# prometheus.
#
# The default used to be /var/lib/node_exporter/textfile_collector, the
# conventional node_exporter textfile path. That is wrong twice over here: the
# directory is root-only, so an unprivileged cron run failed with "Permission
# denied" and wrote nothing, and nothing in this stack reads that path anyway --
# the metrics landed nowhere even if it had succeeded. Combined with the missing
# executable bit, the exporter had never produced a single file.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/business-metrics}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/backups/backup-state}"
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

# Verdict of scripts/backups/check-backup-health.sh, which inspects the backup
# archives themselves. Published so a failing health check can raise an alert
# rather than only writing to a cron log nobody reads: a cron job that just exits
# non-zero is still a silent failure, which is how 81 empty archives survived.
HEALTH_LINE=$(cat "$BACKUP_STATE_DIR/last-backup-health" 2>/dev/null || true)
case "$(printf '%s' "$HEALTH_LINE" | awk '{print $1}')" in
    ok) HEALTH_OK=1 ;;
    *) HEALTH_OK=0 ;;
esac
HEALTH_WHEN=$(printf '%s' "$HEALTH_LINE" | awk '{print $2}')
case "$HEALTH_WHEN" in
    ''|*[!0-9]*) HEALTH_WHEN=0 ;;
esac

cat > "$OUTPUT_DIR/backup_metrics.prom" << EOF
# HELP backup_last_success_timestamp Unix timestamp of the last database backup that completed successfully, 0 if none recorded
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp $LAST_BACKUP
# HELP backup_last_attempt_timestamp Unix timestamp of the last database backup run that started, 0 if none recorded
# TYPE backup_last_attempt_timestamp gauge
backup_last_attempt_timestamp $LAST_ATTEMPT
# HELP backup_health_check_ok 1 if the last check-backup-health.sh run found every backup usable, 0 if it failed or has never run
# TYPE backup_health_check_ok gauge
backup_health_check_ok $HEALTH_OK
# HELP backup_health_check_timestamp Unix timestamp of the last backup health check
# TYPE backup_health_check_timestamp gauge
backup_health_check_timestamp $HEALTH_WHEN
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
