#!/bin/bash
# PharmiQ Project Backup Script
# Custom backup configuration for PharmiQ project

BACKUP_DIR="/backups/projects/pharmiq"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=14
PROJECT_DIR="/home/deon/projects/PharmiQ"

mkdir -p "$BACKUP_DIR"

echo "Starting PharmiQ project backup..."

# Backup project code (excluding unnecessary files)
echo "Backing up PharmiQ project code..."
tar czf "$BACKUP_DIR/pharmiq-code_$DATE.tar.gz" \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='.venv' \
    --exclude='.venv-*' \
    --exclude='dist' \
    --exclude='build' \
    --exclude='.next' \
    --exclude='.cache' \
    --exclude='.pytest_cache' \
    --exclude='.ruff_cache' \
    --exclude='.playwright-cli' \
    -C "$HOME" "projects/PharmiQ"

# Backup PharmiQ Docker volumes if they exist
echo "Backing up PharmiQ Docker volumes..."
if docker volume inspect pharmaiq_postgres_data >/dev/null 2>&1; then
    docker run --rm \
        -v pharmaiq_postgres_data:/volume_data \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf "/backup/pharmiq-postgres_$DATE.tar.gz" -C /volume_data . || true
fi

if docker volume inspect pharmaiq_redis_data >/dev/null 2>&1; then
    docker run --rm \
        -v pharmaiq_redis_data:/volume_data \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf "/backup/pharmiq-redis_$DATE.tar.gz" -C /volume_data . || true
fi

# Backup database file if it exists
echo "Backing up PharmiQ database file..."
if [ -f "$PROJECT_DIR/pharmaiq.db" ]; then
    cp "$PROJECT_DIR/pharmaiq.db" "$BACKUP_DIR/pharmiq-db_$DATE.db"
fi

# Backup configuration files
echo "Backing up PharmiQ configuration files..."
tar czf "$BACKUP_DIR/pharmiq-config_$DATE.tar.gz" \
    -C "$PROJECT_DIR" \
    .env \
    docker-compose.yml \
    nginx/ \
    k8s/ \
    requirements.txt 2>/dev/null || true

# Cleanup old backups
echo "Cleaning up old PharmiQ backups..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "PharmiQ project backup completed: $DATE"
logger -p user.info "PharmiQ project backup completed"
