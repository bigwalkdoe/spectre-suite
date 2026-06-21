#!/bin/bash
# Docker Volume Backup Script
# Backs up critical Docker volumes

BACKUP_DIR="/backups/docker-volumes"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

# Critical volumes to backup
VOLUMES=(
    "guardrail-ai_postgres_data"
    "guardrail-ai_redis_data"
    "guardrail-ai_neo4j_data"
    "guardrail-ai_neo4j_logs"
    "guardrail-ai_grafana_data"
    "guardrail-ai_prometheus_data"
    "guardrail-ai_rabbitmq_data"
    "server-layer_postgres_data"
    "server-layer_redis_data"
    "server-layer_ollama-data"
)

echo "Backing up Docker volumes..."

for volume in "${VOLUMES[@]}"; do
    echo "Backing up volume: $volume"
    volume_name=$(basename "$volume")
    
    # Check if volume exists
    if docker volume inspect "$volume" >/dev/null 2>&1; then
        # Create temporary container for backup
        docker run --rm \
            -v "$volume":/volume_data \
            -v "$BACKUP_DIR":/backup \
            alpine sh -c "tar czf /backup/${volume_name}_$DATE.tar.gz -C /volume_data . || true"
    else
        echo "Volume $volume does not exist, skipping..."
    fi
done

# Backup other project volumes
echo "Backing up additional project volumes..."
docker volume ls --format "{{.Name}}" | grep -E "(modelink|pharmaiq)" | while read volume; do
    volume_name=$(basename "$volume")
    echo "Backing up volume: $volume"
    docker run --rm \
        -v "$volume":/volume_data \
        -v "$BACKUP_DIR":/backup \
        alpine tar czf "/backup/${volume_name}_$DATE.tar.gz" -C /volume_data .
done

# Cleanup old backups
echo "Cleaning up old volume backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Docker volume backup completed: $DATE"
logger -p user.info "Docker volume backup completed successfully"
