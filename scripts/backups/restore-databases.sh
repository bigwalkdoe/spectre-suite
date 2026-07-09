#!/bin/bash
set -euo pipefail

# Database Restore Script
# Restores PostgreSQL databases from backup files

BACKUP_DIR="/backups/databases"
LOG_FILE="/var/log/database-restore.log"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" || true
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" || true >&2
}

# Find latest backup
find_latest_backup() {
    local backup_type="$1"
    local pattern

    case "$backup_type" in
        postgres)
            pattern="postgres_guardrail_*.sql.gz"
            ;;
        postgres_generic)
            pattern="postgres_*.sql.gz"
            ;;
        *)
            error "Unknown backup type: $backup_type"
            return 1
            ;;
    esac

    ls -t "$BACKUP_DIR"/$pattern 2>/dev/null | head -1
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    if [[ "$backup_file" == *.gz ]]; then
        gzip -t "$backup_file" 2>/dev/null || {
            error "Backup file is corrupted: $backup_file"
            return 1
        }
    fi
    
    log "Backup integrity verified: $backup_file"
    return 0
}

# Restore PostgreSQL database
restore_postgres() {
    local backup_file="$1"
    local database_name="${2:-guardrail}"
    local restore_target="${3:-}"
    
    if [[ ! -f "$backup_file" ]]; then
        error "Backup file not found: $backup_file"
        return 1
    fi
    
    log "Starting PostgreSQL restore from: $backup_file"
    
    # Verify backup
    if ! verify_backup "$backup_file"; then
        return 1
    fi
    
    # Determine restore method
    if [[ -n "$restore_target" && "$restore_target" == "docker" ]]; then
        # Restore to Docker container
        log "Restoring to Docker container..."
        
        # Check if container is running
        if ! docker ps | grep -q "$database_name"; then
            error "Database container '$database_name' not found. Starting container..."
            docker run -d \
                --name "$database_name" \
                -e POSTGRES_USER=postgres \
                -e POSTGRES_PASSWORD=postgres \
                -e POSTGRES_DB="$database_name" \
                -v "$database_name-data:/var/lib/postgresql/data" \
                postgres:latest
        fi
        
        # Restore data
        gunzip -c "$backup_file" | docker exec -i "$database_name" psql -U postgres -d "$database_name"
        
        log "PostgreSQL restore completed successfully"
    else
        # Restore to local PostgreSQL
        log "Restoring to local PostgreSQL..."
        
        # Check if PostgreSQL is running
        if ! pg_isready; then
            error "PostgreSQL is not running"
            return 1
        fi
        
        gunzip -c "$backup_file" | psql -U postgres -d "$database_name"
        
        log "PostgreSQL restore completed successfully"
    fi
}

# Main restore function
main() {
    local restore_type="${1:-latest}"
    local database_name="${2:-guardrail}"
    local restore_target="${3:-docker}"
    
    log "=========================================="
    log "Database Restore Started"
    log "Restore type: $restore_type"
    log "Database: $database_name"
    log "Target: $restore_target"
    log "=========================================="
    
    case "$restore_type" in
        latest)
            backup_file=$(find_latest_backup "postgres")
            if [[ -z "$backup_file" ]]; then
                error "No backup files found in $BACKUP_DIR"
                exit 1
            fi
            restore_postgres "$backup_file" "$database_name" "$restore_target"
            ;;
        specific)
            backup_file="$2"
            if [[ ! -f "$backup_file" ]]; then
                error "Backup file not found: $backup_file"
                exit 1
            fi
            restore_postgres "$backup_file" "$database_name" "$restore_target"
            ;;
        *)
            error "Unknown restore type: $restore_type"
            echo "Usage: $0 [latest|specific] [backup_file] [database_name] [target:docker|local]"
            exit 1
            ;;
    esac
    
    log "=========================================="
    log "Database Restore Completed"
    log "=========================================="
}

# Run main function
main "$@"