#!/bin/bash
# Main Maintenance Orchestration Script
# Runs all maintenance tasks and generates reports

MAINTENANCE_LOG="/var/log/maintenance.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$MAINTENANCE_LOG"
echo "Starting System Maintenance: $DATE" >> "$MAINTENANCE_LOG"
echo "==========================================" >> "$MAINTENANCE_LOG"

# Make scripts executable
chmod +x /home/deon/scripts/maintenance/*.sh

# Run system cleanup
echo "Running system cleanup..." >> "$MAINTENANCE_LOG"
/home/deon/scripts/maintenance/cleanup-system.sh >> "$MAINTENANCE_LOG" 2>&1
CLEANUP_STATUS=$?

# Run log cleanup
echo "Running log cleanup..." >> "$MAINTENANCE_LOG"
sudo /home/deon/scripts/maintenance/cleanup-logs.sh >> "$MAINTENANCE_LOG" 2>&1
LOG_STATUS=$?

# Run health check
echo "Running system health check..." >> "$MAINTENANCE_LOG"
/home/deon/scripts/maintenance/system-health-check.sh >> "$MAINTENANCE_LOG" 2>&1
HEALTH_STATUS=$?

# Generate summary
echo "==========================================" >> "$MAINTENANCE_LOG"
echo "Maintenance Summary - $DATE" >> "$MAINTENANCE_LOG"
echo "System cleanup: $([ $CLEANUP_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$MAINTENANCE_LOG"
echo "Log cleanup: $([ $LOG_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$MAINTENANCE_LOG"
echo "Health check: $([ $HEALTH_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$MAINTENANCE_LOG"
echo "Current disk usage:" >> "$MAINTENANCE_LOG"
df -h / >> "$MAINTENANCE_LOG"
echo "==========================================" >> "$MAINTENANCE_LOG"

# Send notification if any maintenance failed
if [ $CLEANUP_STATUS -ne 0 ] || [ $LOG_STATUS -ne 0 ] || [ $HEALTH_STATUS -ne 0 ]; then
    logger -p user.error "System maintenance completed with errors - check $MAINTENANCE_LOG"
    if [ -n "$DISPLAY" ]; then
        notify-send "Maintenance Error" "Some maintenance tasks failed - check logs" -u critical
    fi
else
    logger -p user.info "System maintenance completed successfully"
    if [ -n "$DISPLAY" ]; then
        notify-send "Maintenance Complete" "All maintenance tasks completed successfully"
    fi
fi

echo "System maintenance completed: $DATE"
