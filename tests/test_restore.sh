#!/bin/bash
# End-to-end backup -> restore drill for PostgreSQL.
# Starts a throwaway Postgres container, writes data, backs it up, drops the
# data, restores from the backup, and verifies the data returned.

set -euo pipefail

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

# The container name and the database name are both derived from a unique token.
# restore-databases.sh resolves the container by exact name match on the database
# name, so the two must match -- but they must NOT be a fixed shared name like
# the previous "guardrail", because the script unconditionally ran
# `docker rm -f guardrail` first and would destroy a real container of that name.
# Backups go to a throwaway directory, not the real /backups/databases.
DRILL="spectre_drill_$$_$RANDOM"
CONTAINER="$DRILL"
DRILL_DIR="$(mktemp -d "${TMPDIR:-/tmp}/spectre-restore-drill.XXXXXX")"
BACKUP_DIR="${BACKUP_DIR:-$DRILL_DIR}"

# shellcheck disable=SC2329  # invoked via trap
cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    rm -rf "$DRILL_DIR"
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

# Start the throwaway Postgres container. Its name matches the database name so
# restore-databases.sh resolves it by exact match rather than falling back to
# "any container running postgres", which could target an unrelated database.
mkdir -p "$BACKUP_DIR"
docker run -d --name "$CONTAINER" \
    --label "spectre.test=restore-drill" \
    -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB="$DRILL" \
    "$PG_IMAGE" >/dev/null

# Wait for it to accept connections.
ready=0
for _ in $(seq 1 30); do
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
docker exec "$CONTAINER" psql -U postgres -d "$DRILL" -c "CREATE TABLE drill(id int); INSERT INTO drill VALUES (42);" >/dev/null

# Back up (use the same naming scheme restore-databases.sh expects).
TS=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/postgres_${DRILL}_${TS}.sql"
docker exec "$CONTAINER" pg_dump -U postgres -d "$DRILL" > "$BACKUP_FILE"
gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "FAIL: backup file not created"
    exit 1
fi

# Drop the data so we can prove the restore brings it back.
docker exec "$CONTAINER" psql -U postgres -d "$DRILL" -c "DROP TABLE drill;" >/dev/null

# Restore from the specific backup file.
rc=0
bash "$RESTORE_SCRIPT" specific "$BACKUP_FILE" "$DRILL" docker || rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: restore script exited with $rc"
    exit 1
fi

# Verify the data returned.
RESULT=$(docker exec "$CONTAINER" psql -U postgres -d "$DRILL" -tAc "SELECT count(*) FROM drill;" 2>/dev/null)
if [ "$RESULT" = "1" ]; then
    echo "RESTORE DRILL PASSED (table restored, row count = 1)"
    exit 0
else
    echo "RESTORE DRILL FAILED (row count = '${RESULT}')"
    exit 1
fi
