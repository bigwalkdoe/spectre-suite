#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SPECTRE_REPO_ROOT:-"$(cd "$SCRIPT_DIR/../.." && pwd)"}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
# Multi-Project Backup Orchestration Script

BACKUP_LOG="/var/log/project-backups.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$BACKUP_LOG"
echo "Multi-Project Backup - $DATE" >> "$BACKUP_LOG"
echo "==========================================" >> "$BACKUP_LOG"

_run_action() { # $1 rel
  local a="$REPO_ROOT/spectre/actions/$1"
  [ -f "$a" ] || a="$REPO_ROOT/scripts/$1"
  "$a"
}
# Run Guardrail-AI backup
echo "Running Guardrail-AI backup..." >> "$BACKUP_LOG"
set +e
_run_action "backups/backup-projects.sh" >> "$BACKUP_LOG" 2>&1
GUARDRAIL_STATUS=$?
set -e

# Run Modelink backup
echo "Running Modelink backup..." >> "$BACKUP_LOG"
set +e
_run_action "project-specific/backup-modelink.sh" >> "$BACKUP_LOG" 2>&1
MODELINK_STATUS=$?
set -e

# Generate summary
echo "==========================================" >> "$BACKUP_LOG"
echo "Project Backup Summary - $DATE" >> "$BACKUP_LOG"
echo "Guardrail-AI: $([ $GUARDRAIL_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Modelink: $([ $MODELINK_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Total disk usage:" >> "$BACKUP_LOG"
du -sh /backups/projects >> "$BACKUP_LOG"
echo "==========================================" >> "$BACKUP_LOG"

# Send notification if any backup failed
if [ $GUARDRAIL_STATUS -ne 0 ] || [ $MODELINK_STATUS -ne 0 ]; then
    logger -p user.error "Project backup completed with errors - check $BACKUP_LOG"
    if [ -n "$DISPLAY" ]; then
        notify-send "Project Backup Error" "Some project backups failed - check logs" -u critical
    fi
else
    logger -p user.info "All project backups completed successfully"
    if [ -n "$DISPLAY" ]; then
        notify-send "Project Backup Complete" "All project backups completed successfully"
    fi
fi

echo "Multi-project backup completed: $DATE"
