#!/bin/bash
# Projects Backup Script
# Backs up critical project directories

BACKUP_DIR="/backups/projects"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=14

mkdir -p "$BACKUP_DIR"

echo "Backing up project directories..."

# Critical projects to backup
PROJECTS=(
    "/home/deon/projects/Guardrail-AI"
    "/home/deon/projects/Modelink"
    "/home/deon/projects/PharmiQ"
)

for project in "${PROJECTS[@]}"; do
    project_name=$(basename "$project")
    echo "Backing up project: $project_name"
    
    # Exclude node_modules, .git, and other build artifacts
    tar czf "$BACKUP_DIR/${project_name}_$DATE.tar.gz" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.venv' \
        --exclude='venv' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.next' \
        --exclude='.cache' \
        -C "/home/deon" "projects/$(basename "$project")"
done

# Backup scripts directory
echo "Backing up scripts directory..."
tar czf "$BACKUP_DIR/scripts_$DATE.tar.gz" -C /home/deon scripts

# Cleanup old backups
echo "Cleaning up old project backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Project backup completed: $DATE"
logger -p user.info "Project backup completed successfully"
