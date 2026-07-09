#!/bin/bash
set -euo pipefail

# Compliance Report Script
# Generates compliance reports for security and operational standards

REPORT_DIR="/var/log/compliance"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TIMESTAMP_ISO=$(date -Iseconds)

log() {
    echo "[$TIMESTAMP_ISO] $1" | tee -a "$REPORT_DIR/compliance.log"
}

error() {
    echo "[$TIMESTAMP_ISO] ERROR: $1" | tee -a "$REPORT_DIR/compliance.log" >&2
}

# Initialize report directory
init_report() {
    mkdir -p "$REPORT_DIR"
    chmod 750 "$REPORT_DIR"
}

# Check system compliance
check_system_compliance() {
    log "Checking system compliance..."
    
    local score=0
    local total=0
    local passed=0
    
    # Check for outdated packages
    total=$((total + 1))
    if command -v apt &> /dev/null; then
        if apt list --upgradable > /dev/null 2>&1; then
            log "WARNING: Upgradable packages found"
        else
            log "OK: All packages up to date"
            passed=$((passed + 1))
            score=$((score + 10))
        fi
    elif command -v yum &> /dev/null; then
        if yum check-update > /dev/null 2>&1; then
            log "WARNING: Upgradable packages found"
        else
            log "OK: All packages up to date"
            passed=$((passed + 1))
            score=$((score + 10))
        fi
    fi
    
    # Check for root login
    total=$((total + 1))
    if grep -q "PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        log "WARNING: Root login enabled in SSH"
    else
        log "OK: Root login disabled in SSH"
        passed=$((passed + 1))
        score=$((score + 10))
    fi
    
    # Check for password authentication
    total=$((total + 1))
    if grep -q "PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
        log "WARNING: Password authentication enabled in SSH"
    else
        log "OK: Password authentication disabled in SSH"
        passed=$((passed + 1))
        score=$((score + 10))
    fi
    
    # Check firewall status
    total=$((total + 1))
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            log "OK: UFW firewall is active"
            passed=$((passed + 1))
            score=$((score + 10))
        else
            log "WARNING: UFW firewall is not active"
        fi
    elif command -v firewall-cmd &> /dev/null; then
        if firewall-cmd --state > /dev/null 2>&1; then
            log "OK: firewalld is active"
            passed=$((passed + 1))
            score=$((score + 10))
        else
            log "WARNING: firewalld is not active"
        fi
    else
        log "INFO: No firewall detected"
    fi
    
    # Check for audit logging
    total=$((total + 1))
    if [[ -f "/var/log/audit/audit.log" ]]; then
        log "OK: Audit logging is enabled"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "WARNING: Audit logging not enabled"
    fi
    
    # Check disk usage
    total=$((total + 1))
    local disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -lt 85 ]]; then
        log "OK: Disk usage within limits (${disk_usage}%)"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "WARNING: Disk usage high (${disk_usage}%)"
    fi
    
    return 0
}

# Check Docker compliance
check_docker_compliance() {
    log "Checking Docker compliance..."
    
    local score=0
    local total=0
    local passed=0
    
    # Check Docker security settings
    total=$((total + 1))
    if [[ -f /etc/docker/daemon.json ]]; then
        if grep -q '"no-new-privileges": true' /etc/docker/daemon.json 2>/dev/null; then
            log "OK: no-new-privileges enabled"
            passed=$((passed + 1))
            score=$((score + 10))
        else
            log "WARNING: no-new-privileges not enabled"
        fi
    else
        log "INFO: Docker daemon.json not found"
    fi
    
    # Check for privileged containers
    total=$((total + 1))
    local privileged_count=$(docker ps --format '{{.Name}} {{.Mode}}' 2>/dev/null | grep -c "privileged" || echo 0)
    if [[ $privileged_count -eq 0 ]]; then
        log "OK: No privileged containers running"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "WARNING: $privileged_count privileged container(s) running"
    fi
    
    # Check container resource limits
    total=$((total + 1))
    local unlimited_count=$(docker ps --format '{{.Name}} {{.NanoCpus}} {{.NanoMemory}}' 2>/dev/null | grep -cE "^[^ ]+ 0 " || echo 0)
    if [[ $unlimited_count -eq 0 ]]; then
        log "OK: All containers have resource limits"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "WARNING: $unlimited_count container(s) without resource limits"
    fi
    
    return 0
}

# Check backup compliance
check_backup_compliance() {
    log "Checking backup compliance..."
    
    local score=0
    local total=0
    local passed=0
    
    # Check backup directory exists
    total=$((total + 1))
    if [[ -d "/backups" ]]; then
        log "OK: Backup directory exists"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "WARNING: Backup directory not found"
    fi
    
    # Check for recent backups
    total=$((total + 1))
    local backup_age=$(find /backups -name "*.gz" -o -name "*.tar.gz" 2>/dev/null | xargs stat -c %Y 2>/dev/null | sort -rn | head -1)
    if [[ -n "$backup_age" ]]; then
        local current_time=$(date +%s)
        local age_hours=$(( (current_time - backup_age) / 3600 ))
        if [[ $age_hours -lt 24 ]]; then
            log "OK: Recent backup exists (${age_hours}h old)"
            passed=$((passed + 1))
            score=$((score + 10))
        else
            log "WARNING: No backup in last 24 hours (${age_hours}h)"
        fi
    else
        log "WARNING: No backups found"
    fi
    
    return 0
}

# Check security tools
check_security_tools() {
    log "Checking security tools..."
    
    local score=0
    local total=0
    local passed=0
    
    # Check Fail2Ban
    total=$((total + 1))
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        log "OK: Fail2Ban is running"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "WARNING: Fail2Ban is not running"
    fi
    
    # Check AIDE
    total=$((total + 1))
    if command -v aide-check &> /dev/null; then
        log "OK: AIDE is installed"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "INFO: AIDE not installed"
    fi
    
    # Check Trivy
    total=$((total + 1))
    if command -v trivy &> /dev/null; then
        log "OK: Trivy is installed"
        passed=$((passed + 1))
        score=$((score + 10))
    else
        log "INFO: Trivy not installed"
    fi
    
    return 0
}

# Generate compliance report
generate_report() {
    local report_file="$REPORT_DIR/compliance_report_$(date +%Y%m%d_%H%M%S).txt"
    
    log "=========================================="
    log "Compliance Report Generated"
    log "File: $report_file"
    log "=========================================="
    
    {
        echo "=========================================="
        echo "COMPLIANCE REPORT"
        echo "Generated: $(date)"
        echo "=========================================="
        echo ""
        
        echo "## System Compliance"
        check_system_compliance
        echo ""
        
        echo "## Docker Compliance"
        check_docker_compliance
        echo ""
        
        echo "## Backup Compliance"
        check_backup_compliance
        echo ""
        
        echo "## Security Tools"
        check_security_tools
        echo ""
        
        echo "=========================================="
        echo "END OF REPORT"
        echo "=========================================="
    } > "$report_file"
    
    log "Report saved to: $report_file"
    
    cat "$report_file"
}

# Main function
main() {
    local action="${1:-generate}"
    
    init_report
    
    log "=========================================="
    log "Compliance Report Started"
    log "Action: $action"
    log "=========================================="
    
    case "$action" in
        generate)
            generate_report
            ;;
        check-system)
            check_system_compliance
            ;;
        check-docker)
            check_docker_compliance
            ;;
        check-backup)
            check_backup_compliance
            ;;
        check-security)
            check_security_tools
            ;;
        *)
            error "Unknown action: $action"
            echo "Usage: $0 [generate|check-system|check-docker|check-backup|check-security]"
            exit 1
            ;;
    esac
    
    log "=========================================="
    log "Compliance Report Completed"
    log "=========================================="
    
    exit 0
}

# Run main function
main "$@"