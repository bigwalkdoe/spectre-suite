#!/bin/bash
# End-to-end backup -> restore drill for PostgreSQL.
# Starts a throwaway Postgres container, writes data, backs it up, drops the
# data, restores from the backup, and verifies the data returned.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESTORE_SCRIPT="$PROJECT_ROOT/scripts/backups/restore-databases.sh"

echo "Running restore drill..."
echo "------------------------------------------"

if ! command -v docker >/dev/null 2>&1; then
    echo "SKIP: docker not installed"
    exit 0
fi
if ! docker info >/dev/null 2>&1; then
    echo "SKIP: docker daemon not running"
    exit 0
fi

CONTAINER="guardrail"
BACKUP_DIR="${BACKUP_DIR:-/backups/databases}"
mkdir -p "$BACKUP_DIR"

cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Use a locally available Postgres image to avoid pulling during the drill.
PG_IMAGE="postgres:15"
if ! docker image inspect "$PG_IMAGE" >/dev/null 2>&1; then
    PG_IMAGE="$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -i '^postgres:' | head -1)"
fi
if [ -z "$PG_IMAGE" ]; then
    echo "SKIP: no local postgres image available"
    exit 0
fi

# Start a throwaway Postgres container (name matches restore-databases.sh default).
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" \
    -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=guardrail \
    "$PG_IMAGE" >/dev/null

# Wait for it to accept connections.
ready=0
for i in $(seq 1 30); do
    if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 2
done
if [ "$ready" -ne 1 ]; then
    echo "FAIL: postgres did not become ready"
    exit 1
fi

# Seed data.
docker exec "$CONTAINER" psql -U postgres -d guardrail -c "CREATE TABLE drill(id int); INSERT INTO drill VALUES (42);" >/dev/null

# Back up (use the same naming scheme restore-databases.sh expects).
TS=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/postgres_guardrail_${TS}.sql"
docker exec "$CONTAINER" pg_dump -U postgres -d guardrail > "$BACKUP_FILE"
gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "FAIL: backup file not created"
    exit 1
fi

# Drop the data so we can prove the restore brings it back.
docker exec "$CONTAINER" psql -U postgres -d guardrail -c "DROP TABLE drill;" >/dev/null

# Restore from the specific backup file.
bash "$RESTORE_SCRIPT" specific "$BACKUP_FILE" guardrail docker
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: restore script exited with $rc"
    exit 1
fi

# Verify the data returned.
RESULT=$(docker exec "$CONTAINER" psql -U postgres -d guardrail -tAc "SELECT count(*) FROM drill;" 2>/dev/null)
if [ "$RESULT" = "1" ]; then
    echo "RESTORE DRILL PASSED (table restored, row count = 1)"
    exit 0
else
    echo "RESTORE DRILL FAILED (row count = '${RESULT}')"
    exit 1
fi
