#!/bin/bash
# Main Security Orchestration Script

SECURITY_LOG="/var/log/security-hardening.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$SECURITY_LOG"
echo "Security Hardening - $DATE" >> "$SECURITY_LOG"
echo "==========================================" >> "$SECURITY_LOG"

# Make scripts executable
chmod +x /home/deon/scripts/security/*.sh

# Run dependency vulnerability scanning
echo "Running dependency vulnerability scanning..." >> "$SECURITY_LOG"
/home/deon/scripts/security/scan-dependencies.sh >> "$SECURITY_LOG" 2>&1
DEP_STATUS=$?

# Run Docker security hardening
echo "Running Docker security hardening..." >> "$SECURITY_LOG"
sudo /home/deon/scripts/security/docker-security-hardening.sh >> "$SECURITY_LOG" 2>&1
DOCKER_STATUS=$?

# Run API security hardening
echo "Running API security hardening..." >> "$SECURITY_LOG"
/home/deon/scripts/security/api-security-hardening.sh >> "$SECURITY_LOG" 2>&1
API_STATUS=$?

# Run API security monitoring
echo "Running API security monitoring..." >> "$SECURITY_LOG"
/home/deon/scripts/security/monitor-api-security.sh >> "$SECURITY_LOG" 2>&1
MONITOR_STATUS=$?

# Generate summary
echo "==========================================" >> "$SECURITY_LOG"
echo "Security Hardening Summary - $DATE" >> "$SECURITY_LOG"
echo "Dependency scanning: $([ $DEP_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$SECURITY_LOG"
echo "Docker security: $([ $DOCKER_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$SECURITY_LOG"
echo "API security: $([ $API_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$SECURITY_LOG"
echo "API monitoring: $([ $MONITOR_STATUS -eq 0 ] && echo 'SUCCESS' || echo 'FAILED')" >> "$SECURITY_LOG"
echo "==========================================" >> "$SECURITY_LOG"

# Send notification if any security hardening failed
if [ $DEP_STATUS -ne 0 ] || [ $DOCKER_STATUS -ne 0 ] || [ $API_STATUS -ne 0 ] || [ $MONITOR_STATUS -ne 0 ]; then
    logger -p user.error "Security hardening completed with errors - check $SECURITY_LOG"
    if [ -n "$DISPLAY" ]; then
        notify-send "Security Hardening Error" "Some security tasks failed - check logs" -u critical
    fi
else
    logger -p user.info "Security hardening completed successfully"
    if [ -n "$DISPLAY" ]; then
        notify-send "Security Hardening Complete" "All security tasks completed successfully"
    fi
fi

echo "Security hardening orchestration completed: $DATE"
