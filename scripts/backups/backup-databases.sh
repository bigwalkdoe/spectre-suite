#!/bin/bash
set -euo pipefail

# Database Backup Script
# Backs up PostgreSQL, Redis, and Neo4j databases

BACKUP_DIR="${BACKUP_DIR:-/backups/databases}"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Container names are environment-specific; override per deployment.
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-guardrail-ai-postgres-1}"
REDIS_CONTAINER="${REDIS_CONTAINER:-guardrail-ai-redis-1}"
NEO4J_CONTAINER="${NEO4J_CONTAINER:-guardrail-ai-neo4j-1}"

mkdir -p "$BACKUP_DIR"

# PostgreSQL Backup
echo "Backing up PostgreSQL databases..."
docker exec $POSTGRES_CONTAINER pg_dump -U postgres -d guardrail > "$BACKUP_DIR/postgres_guardrail_$DATE.sql"
docker exec $POSTGRES_CONTAINER pg_dump -U postgres -d postgres > "$BACKUP_DIR/postgres_postgres_$DATE.sql"
gzip "$BACKUP_DIR/postgres_guardrail_$DATE.sql"
gzip "$BACKUP_DIR/postgres_postgres_$DATE.sql"

# Redis Backup
echo "Backing up Redis data..."
docker exec $REDIS_CONTAINER redis-cli --rdb /tmp/backup.rdb
docker cp $REDIS_CONTAINER:/tmp/backup.rdb "$BACKUP_DIR/redis_backup_$DATE.rdb"
docker exec $REDIS_CONTAINER rm /tmp/backup.rdb

# Neo4j Backup
echo "Backing up Neo4j data..."
docker exec $NEO4J_CONTAINER neo4j-admin database dump --to-path=/tmp/backup neo4j
docker cp $NEO4J_CONTAINER:/tmp/backup "$BACKUP_DIR/neo4j_backup_$DATE"
docker exec $NEO4J_CONTAINER rm -rf /tmp/backup
tar -czf "$BACKUP_DIR/neo4j_backup_$DATE.tar.gz" -C "$BACKUP_DIR" "neo4j_backup_$DATE"
rm -rf "$BACKUP_DIR/neo4j_backup_$DATE"

# Cleanup old backups
echo "Cleaning up old backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Database backup completed: $DATE"
logger -p user.info "Database backup completed successfully"
