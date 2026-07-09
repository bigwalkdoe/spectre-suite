#!/bin/bash
set -euo pipefail

# Docker Volume Restore Script
# Restores Docker volumes from backup files

BACKUP_DIR="/backups/docker-volumes"
LOG_FILE="/var/log/docker-volume-restore.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" || true
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" || true >&2
}

# Find latest backup
find_latest_backup() {
    ls -t "$BACKUP_DIR"/guardrail-ai_*_data_*.tar.gz 2>/dev/null | head -1
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    if [[ "$backup_file" == *.tar.gz ]]; then
        tar -tzf "$backup_file" > /dev/null 2>&1 || {
            error "Backup file is corrupted: $backup_file"
            return 1
        }
    fi
    
    log "Backup integrity verified: $backup_file"
    return 0
}

# Restore Docker volumes
restore_volumes() {
    local backup_file="$1"
    local container_name="${2:-}"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Starting Docker volume restore from: $backup_file"
    
    # Verify backup
    if ! verify_backup "$backup_file"; then
        return 1
    fi
    
    # Extract backup to temp directory
    local temp_dir=$(mktemp -d)
    log "Extracting backup to: $temp_dir"
    
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Find volume directories
    local volume_dirs=$(find "$temp_dir" -maxdepth 1 -type d -name "*/data" | head -10)
    
    for volume_dir in $volume_dirs; do
        local volume_path=$(dirname "$volume_dir")
        local volume_name=$(basename "$volume_path")
        
        log "Restoring volume: $volume_name"
        
        # Check if container exists
        if docker ps -a | grep -q "$volume_name"; then
            # Container exists, stop and remove it
            log "Stopping and removing container: $volume_name"
            docker stop "$volume_name" 2>/dev/null || true
            docker rm "$volume_name" 2>/dev/null || true
        fi
        
        # Create new container with restored data
        docker run -d \
            --name "$volume_name" \
            -v "$volume_path:/data" \
            alpine:latest \
            sleep infinity &
        
        # Wait for container to start
        sleep 2
        
        # Copy data to actual volume mount
        if [[ -n "$container_name" ]]; then
            docker cp "$volume_path/." "$container_name":/tmp/restore 2>/dev/null || true
        fi
        
        log "Volume $volume_name restored"
    done
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "Docker volume restore completed successfully"
}

# Restore specific volume
restore_specific_volume() {
    local volume_name="$1"
    local backup_file="$2"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Restoring specific volume: $volume_name"
    
    # Find volume directory in backup
    local temp_dir=$(mktemp -d)
    tar -xzf "$backup_file" -C "$temp_dir"
    
    local volume_path=$(find "$temp_dir" -maxdepth 1 -type d -name "*$volume_name*" | head -1)
    
    if [[ -z "$volume_path" ]]; then
        error "Volume directory not found in backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log "Restoring volume from: $volume_path"
    
    # Stop and remove existing container
    docker stop "$volume_name" 2>/dev/null || true
    docker rm "$volume_name" 2>/dev/null || true
    
    # Create new container
    docker run -d \
        --name "$volume_name" \
        -v "$volume_path:/data" \
        alpine:latest \
        sleep infinity
    
    log "Volume $volume_name restored successfully"
    
    rm -rf "$temp_dir"
}

# Main restore function
main() {
    local restore_type="${1:-latest}"
    local container_name="${2:-}"
    
    log "=========================================="
    log "Docker Volume Restore Started"
    log "Restore type: $restore_type"
    log "=========================================="
    
    case "$restore_type" in
        latest)
            backup_file=$(find_latest_backup)
            if [[ -z "$backup_file" ]]; then
                error "No backup files found in $BACKUP_DIR"
                exit 1
            fi
            restore_volumes "$backup_file" "$container_name"
            ;;
        specific)
            backup_file="$2"
            if [[ ! -f "$backup_file" ]]; then
                error "Backup file not found: $backup_file"
                exit 1
            fi
            restore_volumes "$backup_file" "$container_name"
            ;;
        specific-volume)
            volume_name="$2"
            backup_file="$3"
            if [[ ! -f "$backup_file" ]]; then
                error "Backup file not found: $backup_file"
                exit 1
            fi
            restore_specific_volume "$volume_name" "$backup_file"
            ;;
        *)
            error "Unknown restore type: $restore_type"
            echo "Usage: $0 [latest|specific|specific-volume] [backup_file|volume_name] [container_name|backup_file]"
            exit 1
            ;;
    esac
    
    log "=========================================="
    log "Docker Volume Restore Completed"
    log "=========================================="
}

# Run main function
main "$@"