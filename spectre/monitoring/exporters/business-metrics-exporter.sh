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
# Phase 1: impl lives in spectre/monitoring/exporters; output stays in repo's
# prometheus/business-metrics (docker-compose bind-mount). Prefer SPECTRE_REPO_ROOT.
_REPO_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
OUTPUT_DIR="${1:-$_REPO_ROOT/prometheus/business-metrics}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/backups/backup-state}"
BACKUP_REPO_DIR="${BACKUP_REPO_DIR:-/backups/fedora-back-up/data}"
RESTIC_MARKER_DIR="${RESTIC_MARKER_DIR:-${HOME:-/home/deon}/.local/state/spectre-suite/backups}"
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
# Sourced from markers that spectre/actions/backups/backup-databases.sh
# (`spectre run backups/backup-databases`) writes when a run starts and when it
# completes. The previous implementation reported the mtime of /backups/databases
# as "last successful backup", which was wrong twice over: the directory mtime
# also advances when retention deletes an old file, so a directory with no
# recent backup still looked fresh, and a failed backup could not be
# distinguished from a stale one.
LAST_BACKUP=$(read_marker "$BACKUP_STATE_DIR/last-db-backup-success")
LAST_ATTEMPT=$(read_marker "$BACKUP_STATE_DIR/last-db-backup-attempt")

# Verdict of spectre/actions/backups/check-backup-health.sh
# (`spectre run backups/check-backup-health`), which inspects the backup
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

# Restore verdict of spectre/actions/backups/restore-all.sh
# (`spectre run backups/restore-all --execute --yes ...`). It writes
# `$BACKUP_STATE_DIR/last-restore-health` as `ok <epoch>` or
# `failed <epoch> <detail>`, and appends `remote=rsync-download-only` when the
# offsite step was an rsync fetch that applied nothing. Nothing read this
# marker before: a restore that had failed or never run was invisible in
# Prometheus, and an operator finishing a disaster recovery had no signal at
# all -- the same class of silence that let 81 hollow backup archives ship.
#
# The rsync case exits 0, so it reads as healthy: it did what it was asked.
# `restore_rsync_download_only` is the separate signal that nothing was
# applied; `restore_health_ok` stays 1 so it does not trip a false failure.
RESTORE_LINE=$(cat "$BACKUP_STATE_DIR/last-restore-health" 2>/dev/null || true)
RESTORE_OK=0
RESTORE_WHEN=0
RESTORE_RSYNC=0
case "$(printf '%s' "$RESTORE_LINE" | awk '{print $1}')" in
    ok) RESTORE_OK=1 ;;
    *) RESTORE_OK=0 ;;
esac
RESTORE_WHEN=$(printf '%s' "$RESTORE_LINE" | awk '{print $2}')
case "$RESTORE_WHEN" in
    ''|*[!0-9]*) RESTORE_WHEN=0 ;;
esac
# A timestamp from a malformed verdict is not a real restore time. `maybe
# 1700000000` parses to ok=0 with a valid epoch, which would publish a
# timestamp for a restore that never happened. A `failed <epoch> ...` verdict
# is a real restore time and keeps it -- the failure is only useful if it is
# timestamped.
RESTORE_VERDICT=$(printf '%s' "$RESTORE_LINE" | awk '{print $1}')
case "$RESTORE_VERDICT" in
    ok|failed) ;;
    *) RESTORE_WHEN=0 ;;
esac
printf '%s' "$RESTORE_LINE" | grep -q 'remote=rsync-download-only' && RESTORE_RSYNC=1

# Restic snapshot markers (spectre-suite adopted engine). Missing/unparseable => 0.
read_marker_num() {
    local f="$1" n="${2:-1}" v=""
    [ -r "$f" ] || { printf '0\n'; return; }
    v=$(awk -v n="$n" '{print $n}' "$f" 2>/dev/null || true)
    case "$v" in
        ''|*[!0-9]*) [ -s "$f" ] && echo "business-metrics: restic marker parse failed: $f" >&2; printf '0\n' ;;
        *) printf '%s\n' "$v" ;;
    esac
}
RESTIC_LAST_ATTEMPT=$(read_marker_num "$RESTIC_MARKER_DIR/last-attempt" 1)
RESTIC_LAST_SUCCESS=$(read_marker_num "$RESTIC_MARKER_DIR/last-success" 1)
RESTIC_LAST_OFFSITE=$(read_marker_num "$RESTIC_MARKER_DIR/last-offsite-success" 1)
RESTIC_HEALTH_OK=$(read_marker_num "$RESTIC_MARKER_DIR/last-health" 1)
RESTIC_HEALTH_TS=$(read_marker_num "$RESTIC_MARKER_DIR/last-health" 2)
RESTIC_VERIFY_OK=$(read_marker_num "$RESTIC_MARKER_DIR/last-verify" 1)
RESTIC_VERIFY_TS=$(read_marker_num "$RESTIC_MARKER_DIR/last-verify" 2)

# Repository growth. Nothing published the repo size, so an unbounded restic repo
# was invisible until HighDiskUsage fired on / at 93% -- which cannot tell a
# backup-repo problem from an ordinary full disk, and by then there was no
# warning left to act on. The repo did carry real unpruned garbage (a prune
# reclaimed 7.1 GiB, leaving `unused size after prune: 0 B`), but note that
# `restic forget`'s retained total is *logical* snapshot content, not physical
# blob storage, so the apparent 61G-on-disk vs ~30G-retained gap overstates the
# garbage badly. Do not infer reclaimable space that way; compare against an
# actual `restic prune`.
#
# These are plain du/df reads: no restic invocation, so no password is needed and
# the 5-minute cron stays cheap.
#
# Prints bytes for a du/df field, or 0 when the command fails. 0 is the safe
# direction for every alert built on these: a repo size of 0 makes growth
# negative (no page) and a free-space of 0 trips the low-space alert, so a
# broken du fails loudly instead of reading as healthy.
dir_bytes() {
    local v
    v=$(du -sb "$1" 2>/dev/null | awk '{print $1}') || v=""
    case "$v" in
        '' | *[!0-9]*) printf '0\n' ;;
        *) printf '%s\n' "$v" ;;
    esac
}

fs_field() {
    local v
    v=$(df -B1 --output="$2" "$1" 2>/dev/null | tail -1 | tr -d ' ') || v=""
    case "$v" in
        '' | *[!0-9]*) printf '0\n' ;;
        *) printf '%s\n' "$v" ;;
    esac
}

# If the configured repo path is missing, try common locations before falling
# back to filesystem-only metrics (avoids a false 0 free-space alert).
if [ ! -d "$BACKUP_REPO_DIR" ]; then
    for candidate in /backups/spectre-backup /backups/restic /var/lib/restic; do
        if [ -d "$candidate" ]; then BACKUP_REPO_DIR="$candidate"; break; fi
    done
fi
# Repo size is only meaningful when the repository directory exists.
if [ -d "$BACKUP_REPO_DIR" ]; then
    REPO_BYTES=$(dir_bytes "$BACKUP_REPO_DIR")
    REPO_FS_PATH="$BACKUP_REPO_DIR"
else
    REPO_BYTES=0
    # For filesystem free-space metrics, fall back to the nearest existing
    # ancestor (or /backups, then /) so a missing/unconfigured repo path does
    # not publish 0 and trigger a false low-space alert.
    REPO_FS_PATH="$BACKUP_REPO_DIR"
    while [ ! -e "$REPO_FS_PATH" ] && [ "$REPO_FS_PATH" != "/" ]; do
        REPO_FS_PATH=$(dirname "$REPO_FS_PATH")
    done
    [ -e "$REPO_FS_PATH" ] || REPO_FS_PATH="/"
fi
REPO_FS=$(df -P "$REPO_FS_PATH" 2>/dev/null | awk 'NR==2{print $6}' || true)
[ -n "$REPO_FS" ] || REPO_FS="$REPO_FS_PATH"
REPO_FS_SIZE=$(fs_field "$REPO_FS" size)
REPO_FS_FREE=$(fs_field "$REPO_FS" avail)

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
# HELP restore_health_ok 1 if the last backups/restore-all run completed, 0 if it failed or has never run
# TYPE restore_health_ok gauge
restore_health_ok $RESTORE_OK
# HELP restore_health_timestamp Unix timestamp of the last backups/restore-all run, 0 if none
# TYPE restore_health_timestamp gauge
restore_health_timestamp $RESTORE_WHEN
# HELP restore_rsync_download_only 1 if the last restore's offsite step was an rsync fetch that applied nothing, 0 otherwise
# TYPE restore_rsync_download_only gauge
restore_rsync_download_only $RESTORE_RSYNC
# HELP backup_repo_size_bytes Bytes on disk used by the restic repository data directory
# TYPE backup_repo_size_bytes gauge
backup_repo_size_bytes $REPO_BYTES
# HELP backup_repo_fs_size_bytes Total bytes of the filesystem holding the restic repository
# TYPE backup_repo_fs_size_bytes gauge
backup_repo_fs_size_bytes $REPO_FS_SIZE
# HELP backup_repo_fs_free_bytes Bytes available on the filesystem holding the restic repository
# TYPE backup_repo_fs_free_bytes gauge
backup_repo_fs_free_bytes $REPO_FS_FREE
# HELP restic_last_attempt_timestamp Unix timestamp of the last restic backup attempt, 0 if none
# TYPE restic_last_attempt_timestamp gauge
restic_last_attempt_timestamp $RESTIC_LAST_ATTEMPT
# HELP restic_last_success_timestamp Unix timestamp of the last successful local restic snapshot, 0 if none
# TYPE restic_last_success_timestamp gauge
restic_last_success_timestamp $RESTIC_LAST_SUCCESS
# HELP restic_last_offsite_success_timestamp Unix timestamp of the last successful offsite restic snapshot, 0 if none
# TYPE restic_last_offsite_success_timestamp gauge
restic_last_offsite_success_timestamp $RESTIC_LAST_OFFSITE
# HELP restic_health_ok 1 if last restic health verdict was ok (exit 0), 0 otherwise
# TYPE restic_health_ok gauge
restic_health_ok $RESTIC_HEALTH_OK
# HELP restic_health_timestamp Unix timestamp of the last restic health verdict, 0 if none
# TYPE restic_health_timestamp gauge
restic_health_timestamp $RESTIC_HEALTH_TS
# HELP restic_verify_ok 1 if last restic verify passed, 0 if failed or never run
# TYPE restic_verify_ok gauge
restic_verify_ok $RESTIC_VERIFY_OK
# HELP restic_verify_timestamp Unix timestamp of the last restic verify, 0 if never run
# TYPE restic_verify_timestamp gauge
restic_verify_timestamp $RESTIC_VERIFY_TS
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

# security_metrics.prom is owned by prometheus/security-metrics-exporter; do not delete it here.
rm -f "$OUTPUT_DIR/app_metrics.prom"

echo "Business metrics exported to $OUTPUT_DIR"
