#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
# Main Security Orchestration Script

SECURITY_LOG="/var/log/security-hardening.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$SECURITY_LOG"
echo "Security Hardening - $DATE" >> "$SECURITY_LOG"
echo "==========================================" >> "$SECURITY_LOG"

# Make scripts executable
chmod +x $SCRIPT_DIR/*.sh

# Run dependency vulnerability scanning
echo "Running dependency vulnerability scanning..." >> "$SECURITY_LOG"
set +e
$SCRIPT_DIR/scan-dependencies.sh >> "$SECURITY_LOG" 2>&1
DEP_STATUS=$?
set -e

# Run Docker security hardening
echo "Running Docker security hardening..." >> "$SECURITY_LOG"
set +e
sudo $SCRIPT_DIR/docker-security-hardening.sh >> "$SECURITY_LOG" 2>&1
DOCKER_STATUS=$?
set -e

# Run API security hardening
echo "Running API security hardening..." >> "$SECURITY_LOG"
set +e
$SCRIPT_DIR/api-security-hardening.sh >> "$SECURITY_LOG" 2>&1
API_STATUS=$?
set -e

# Run API security monitoring
echo "Running API security monitoring..." >> "$SECURITY_LOG"
set +e
$SCRIPT_DIR/monitor-api-security.sh >> "$SECURITY_LOG" 2>&1
MONITOR_STATUS=$?
set -e

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
