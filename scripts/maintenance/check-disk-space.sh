#!/bin/bash
set -euo pipefail

# Disk Space Check Script
# Monitors disk usage and alerts on low space

LOG_FILE="/var/log/disk-space-check.log"
CRITICAL_THRESHOLD=90
WARNING_THRESHOLD=80
LOG_FILE="/var/log/disk-space-check.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"
}

# Get disk usage for a mount point
get_disk_usage() {
    local mount_point="$1"
    df "$mount_point" | tail -1 | awk '{print $5}' | sed 's/%//g'
}

# Get disk usage in human readable format
get_disk_usage_human() {
    local mount_point="$1"
    df -h "$mount_point" | tail -1 | awk '{print $4}'
}

# Get available space
get_available_space() {
    local mount_point="$1"
    df "$mount_point" | tail -1 | awk '{print $4}'
}

# Get inode usage
get_inode_usage() {
    local mount_point="$1"
    df -i "$mount_point" | tail -1 | awk '{print $5}' | sed 's/%//g'
}

# Find large files
find_large_files() {
    local size="${1:-100M}"
    log "Finding files larger than $size..."
    
    find /var/log -type f -size +$size -exec ls -lh {} \; 2>/dev/null | sort -k5 -r | head -10 || true
}

# Find large directories
find_large_directories() {
    local size="${1:-100M}"
    log "Finding directories larger than $size..."
    
    du -sh /* 2>/dev/null | sort -rh | head -10 || true
}

# Clean old logs
clean_old_logs() {
    log "Cleaning logs older than 7 days..."
    
    find /var/log -name "*.log.*" -type f -mtime +7 -delete 2>/dev/null || true
    log "Log cleanup completed"
}

# Check Docker disk usage
check_docker_disk() {
    log "Checking Docker disk usage..."
    
    if command -v docker &> /dev/null; then
        local docker_usage=$(docker system df 2>/dev/null | tail -5)
        log "$docker_usage"
        
        # Check for unused images
        local unused_images=$(docker images -f "dangling=true" -q 2>/dev/null)
        if [[ -n "$unused_images" ]]; then
            log "WARNING: Found unused Docker images:"
            echo "$unused_images" | while read img; do
                log "  - $img"
            done
        fi
    else
        log "INFO: Docker not installed"
    fi
}

# Main disk space check
main() {
    log "=========================================="
    log "Disk Space Check Started"
    log "=========================================="
    
    # Check root filesystem
    local root_usage=$(get_disk_usage "/")
    local root_available=$(get_available_space "/")
    local root_human=$(get_disk_usage_human "/")
    
    log "Root filesystem: ${root_human} (${root_usage}% used, ${root_available} available)"
    
    if [[ "$root_usage" -ge "$CRITICAL_THRESHOLD" ]]; then
        log "CRITICAL: Root filesystem is ${root_usage}% full"
        exit 2
    elif [[ "$root_usage" -ge "$WARNING_THRESHOLD" ]]; then
        log "WARNING: Root filesystem is ${root_usage}% full"
    else
        log "OK: Root filesystem usage is normal"
    fi
    
    # Check other mount points
    log ""
    log "Checking other filesystems..."
    
    for mount_point in /boot /var /home /tmp; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            local usage=$(get_disk_usage "$mount_point")
            local available=$(get_available_space "$mount_point")
            local human=$(get_disk_usage_human "$mount_point")
            
            log "  $mount_point: ${human} (${usage}% used, ${available} available)"
            
            if [[ "$usage" -ge "$CRITICAL_THRESHOLD" ]]; then
                log "  CRITICAL: $mount_point is ${usage}% full"
            elif [[ "$usage" -ge "$WARNING_THRESHOLD" ]]; then
                log "  WARNING: $mount_point is ${usage}% full"
            fi
        fi
    done
    
    # Check inode usage
    local root_inodes=$(get_inode_usage "/")
    log ""
    log "Root inode usage: ${root_inodes}%"
    
    if [[ "$root_inodes" -ge "$CRITICAL_THRESHOLD" ]]; then
        log "CRITICAL: Root inode table is ${root_inodes}% full"
        exit 2
    elif [[ "$root_inodes" -ge "$WARNING_THRESHOLD" ]]; then
        log "WARNING: Root inode table is ${root_inodes}% full"
    fi
    
    # Find large files
    log ""
    log "Large files (>100M) in /var/log:"
    find_large_files "100M"
    
    # Find large directories
    log ""
    log "Largest directories:"
    find_large_directories "100M"
    
    # Check Docker
    check_docker_disk
    
    log "=========================================="
    log "Disk Space Check Completed"
    log "=========================================="
    
    exit 0
}

# Run main function
main "$@"