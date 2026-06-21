#!/bin/bash
# Database Backup Script
# Backs up PostgreSQL, Redis, and Neo4j databases

BACKUP_DIR="/backups/databases"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

# PostgreSQL Backup
echo "Backing up PostgreSQL databases..."
docker exec guardrail-ai-postgres-1 pg_dump -U postgres -d guardrail > "$BACKUP_DIR/postgres_guardrail_$DATE.sql"
docker exec guardrail-ai-postgres-1 pg_dump -U postgres -d postgres > "$BACKUP_DIR/postgres_postgres_$DATE.sql"
gzip "$BACKUP_DIR/postgres_guardrail_$DATE.sql"
gzip "$BACKUP_DIR/postgres_postgres_$DATE.sql"

# Redis Backup
echo "Backing up Redis data..."
docker exec guardrail-ai-redis-1 redis-cli --rdb /tmp/backup.rdb
docker cp guardrail-ai-redis-1:/tmp/backup.rdb "$BACKUP_DIR/redis_backup_$DATE.rdb"
docker exec guardrail-ai-redis-1 rm /tmp/backup.rdb

# Neo4j Backup
echo "Backing up Neo4j data..."
docker exec guardrail-ai-neo4j-1 neo4j-admin database dump --to-path=/tmp/backup neo4j
docker cp guardrail-ai-neo4j-1:/tmp/backup "$BACKUP_DIR/neo4j_backup_$DATE"
docker exec guardrail-ai-neo4j-1 rm -rf /tmp/backup
tar -czf "$BACKUP_DIR/neo4j_backup_$DATE.tar.gz" -C "$BACKUP_DIR" "neo4j_backup_$DATE"
rm -rf "$BACKUP_DIR/neo4j_backup_$DATE"

# Cleanup old backups
echo "Cleaning up old backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete

echo "Database backup completed: $DATE"
logger -p user.info "Database backup completed successfully"
