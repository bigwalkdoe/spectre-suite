#!/bin/bash
# Main Backup Orchestration Script
# Runs all backup scripts and generates a summary report

BACKUP_LOG="/var/log/backup.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$BACKUP_LOG"
echo "Starting comprehensive backup: $DATE" >> "$BACKUP_LOG"
echo "==========================================" >> "$BACKUP_LOG"

# Make scripts executable
chmod +x /home/deon/scripts/backups/*.sh

# Run database backups
echo "Running database backups..." >> "$BACKUP_LOG"
/home/deon/scripts/backups/backup-databases.sh >> "$BACKUP_LOG" 2>&1
DB_STATUS=$?

# Run Docker volume backups
echo "Running Docker volume backups..." >> "$BACKUP_LOG"
/home/deon/scripts/backups/backup-docker-volumes.sh >> "$BACKUP_LOG" 2>&1
VOL_STATUS=$?

# Run configuration backups
echo "Running configuration backups..." >> "$BACKUP_LOG"
/home/deon/scripts/backups/backup-configurations.sh >> "$BACKUP_LOG" 2>&1
CONFIG_STATUS=$?

# Run project backups (daily only)
DAY_OF_WEEK=$(date +%u)
if [ "$DAY_OF_WEEK" = "7" ]; then  # Sunday
    echo "Running weekly project backups..." >> "$BACKUP_LOG"
    /home/deon/scripts/backups/backup-projects.sh >> "$BACKUP_LOG" 2>&1
    PROJECT_STATUS=$?
else
    echo "Skipping project backups (weekly only)" >> "$BACKUP_LOG"
    PROJECT_STATUS=0
fi

# Generate summary
echo "==========================================" >> "$BACKUP_LOG"
echo "Backup Summary - $DATE" >> "$BACKUP_LOG"
echo "Database backups: $([ $DB_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Volume backups: $([ $VOL_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Configuration backups: $([ $CONFIG_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Project backups: $([ $PROJECT_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$BACKUP_LOG"
echo "Total disk usage:" >> "$BACKUP_LOG"
du -sh /backups >> "$BACKUP_LOG"
echo "==========================================" >> "$BACKUP_LOG"

# Send notification if any backup failed
if [ $DB_STATUS -ne 0 ] || [ $VOL_STATUS -ne 0 ] || [ $CONFIG_STATUS -ne 0 ] || [ $PROJECT_STATUS -ne 0 ]; then
    logger -p user.error "Backup completed with errors - check $BACKUP_LOG"
    if [ -n "$DISPLAY" ]; then
        notify-send "Backup Error" "Some backups failed - check logs" -u critical
    fi
else
    logger -p user.info "All backups completed successfully"
    if [ -n "$DISPLAY" ]; then
        notify-send "Backup Complete" "All backups completed successfully"
    fi
fi

echo "Backup orchestration completed: $DATE"
