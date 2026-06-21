#!/bin/bash
# Multi-Project Backup Orchestration Script

BACKUP_LOG="/var/log/project-backups.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$BACKUP_LOG"
echo "Multi-Project Backup - $DATE" >> "$BACKUP_LOG"
echo "==========================================" >> "$BACKUP_LOG"

# Run Guardrail-AI backup
echo "Running Guardrail-AI backup..." >> "$BACKUP_LOG"
/home/deon/github/system-maintenance/scripts/backups/backup-projects.sh >> "$BACKUP_LOG" 2>&1
GUARDRAIL_STATUS=$?

# Run Modelink backup
echo "Running Modelink backup..." >> "$BACKUP_LOG"
/home/deon/github/system-maintenance/scripts/project-specific/backup-modelink.sh >> "$BACKUP_LOG" 2>&1
MODELINK_STATUS=$?

# Run PharmiQ backup  
echo "Running PharmiQ backup..." >> "$BACKUP_LOG"
/home/deon/github/system-maintenance/scripts/project-specific/backup-pharmiq.sh >> "$BACKUP_LOG" 2>&1
PHARMIQ_STATUS=$?

# Generate summary
echo "==========================================" >> "$BACKUP_LOG"
echo "Project Backup Summary - $DATE" >> "$BACKUP_LOG"
echo "Guardrail-AI: $([ $GUARDRAIL_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Modelink: $([ $MODELINK_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "PharmiQ: $([ $PHARMIQ_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Total disk usage:" >> "$BACKUP_LOG"
du -sh /backups/projects >> "$BACKUP_LOG"
echo "==========================================" >> "$BACKUP_LOG"

# Send notification if any backup failed
if [ $GUARDRAIL_STATUS -ne 0 ] || [ $MODELINK_STATUS -ne 0 ] || [ $PHARMIQ_STATUS -ne 0 ]; then
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
