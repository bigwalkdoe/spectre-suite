#!/bin/bash
# PharmiQ Project Health Check Script

PROJECT_DIR="/home/deon/projects/PharmiQ"
HEALTH_LOG="/var/log/pharmiq-health.log"
DATE=$(date +%Y%m%d_%H%M%S)

echo "==========================================" >> "$HEALTH_LOG"
echo "PharmiQ Health Check - $DATE" >> "$HEALTH_LOG"
echo "==========================================" >> "$HEALTH_LOG"

# Check if project directory exists
if [ ! -d "$PROJECT_DIR" ]; then
    echo "ERROR: PharmiQ project directory not found" >> "$HEALTH_LOG"
    exit 1
fi

# Check Docker containers
echo "Checking PharmiQ Docker containers..." >> "$HEALTH_LOG"
cd "$PROJECT_DIR"
docker-compose ps >> "$HEALTH_LOG" 2>&1

# Check for running services
echo "Running services:" >> "$HEALTH_LOG"
docker-compose ps --services --filter "status=running" >> "$HEALTH_LOG" 2>&1

# Check disk usage for project
echo "Project disk usage:" >> "$HEALTH_LOG"
du -sh "$PROJECT_DIR" >> "$HEALTH_LOG"

# Check database file
if [ -f "$PROJECT_DIR/pharmaiq.db" ]; then
    DB_SIZE=$(du -h "$PROJECT_DIR/pharmaiq.db" | cut -f1)
    echo "Database file size: $DB_SIZE" >> "$HEALTH_LOG"
else
    echo "WARNING: Database file not found" >> "$HEALTH_LOG"
fi

# Check recent errors in logs (if docker logs available)
echo "Recent container logs (last 20 lines):" >> "$HEALTH_LOG"
docker-compose logs --tail=20 >> "$HEALTH_LOG" 2>&1

# Check if environment file exists
if [ -f "$PROJECT_DIR/.env" ]; then
    echo "Environment file: OK" >> "$HEALTH_LOG"
else
    echo "WARNING: Environment file missing" >> "$HEALTH_LOG"
fi

# Check Python dependencies
if [ -f "$PROJECT_DIR/requirements.txt" ]; then
    echo "Requirements file: OK" >> "$HEALTH_LOG"
else
    echo "WARNING: Requirements file missing" >> "$HEALTH_LOG"
fi

echo "PharmiQ health check completed: $DATE" >> "$HEALTH_LOG"
echo "==========================================" >> "$HEALTH_LOG"

logger -p user.info "PharmiQ project health check completed"
