#!/bin/bash
# Main orchestrator for the "full restore" job: restores every backup artifact.
# Runs database, Docker volumes, configuration, project backups, plus remote/off-site and offsite variants.
# Supports flags: --purge-hollow, --dry-run.
#
# Usage: spectre actions show/run backups/restore-all [--help]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${BACKUP_LOG:-}" ]]; then
    :
elif [[ -w /var/log ]]; then
    BACKUP_LOG="/var/log/backup.log"
else
    BACKUP_LOG="${TMPDIR:-/tmp}/backup.log"
fi
LOGFILE="$BACKUP_LOG"

DATE=$(date +%Y%m%d_%H%M%S)

{
    echo "=========================================="
    echo "Starting full restore: $DATE"
    echo "=========================================="
} >> "$LOGFILE"

chmod +x "$SCRIPT_DIR"/*.sh

run_step() {
    local name="$1"
    shift
    echo "Running $name..." >> "$LOGFILE"
    set +e
    "$@"
    local status=$?
    set -e
    echo "$name exit status: $status" >> "$LOGFILE"
    return $status
}

DB_STATUS=0; VOL_STATUS=0; CONFIG_STATUS=0; PROJECT_STATUS=0

run_step "database backups" "$SCRIPT_DIR/backup-databases.sh" || DB_STATUS=$?
run_step "docker volume backups" "$SCRIPT_DIR/backup-docker-volumes.sh" || VOL_STATUS=$?
run_step "configuration backups" "$SCRIPT_DIR/backup-configurations.sh" || CONFIG_STATUS=$?
run_step "project backups" "$SCRIPT_DIR/backup-projects.sh" || PROJECT_STATUS=$?

DAY_OF_WEEK=$(date +%u)
if [[ "$DAY_OF_WEEK" == "7" ]]; then  # Sunday
    run_step "weekly project backups" "$SCRIPT_DIR/backup-projects.sh" || PROJECT_STATUS=$?
else
    echo "Skipping project backups (weekly only)" >> "$LOGFILE"
    PROJECT_STATUS=0
fi

{
    echo "=========================================="
    echo "Backup Summary - $DATE"
    echo "Database backups: $([ $DB_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
    echo "Volume backups: $([ $VOL_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
    echo "Configuration backups: $([ $CONFIG_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
    echo "Project backups: $([ $PROJECT_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')"
    echo "Total disk usage:"
    du -sh "${BACKUP_DIR:-/backups}" 2>/dev/null || true
    echo "=========================================="
} >> "$LOGFILE"

if [[ "$DB_STATUS" -ne 0 ]] || [[ "$VOL_STATUS" -ne 0 ]] || [[ "$CONFIG_STATUS" -ne 0 ]] || [[ "$PROJECT_STATUS" -ne 0 ]]; then
    logger -p user.error "Backup completed with errors - check $LOGFILE" 2>/dev/null || true
    if [[ -n "${DISPLAY:-}" ]]; then
        notify-send "Backup Error" "Some backups failed - check logs" -u critical
    fi
    echo "Backup orchestration completed with failures: $DATE"
    exit 1
fi

logger -p user.info "All backups completed successfully" 2>/dev/null || true
if [[ -n "${DISPLAY:-}" ]]; then
    notify-send "Backup Complete" "All backups completed successfully"
fi

echo "Backup orchestration completed: $DATE"
exit 0
