#!/bin/bash
# Conservative local backup artifact trimming tests (Task 3)
#
# Fixture-based tests against temp dirs; never touches real backup paths.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TRIMMER="$PROJECT_ROOT/spectre/actions/backups/trim-backup-artifacts.sh"

echo "Running backup artifact trimming tests..."

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

if [ ! -f "$TRIMMER" ]; then
    echo "❌ trim-backup-artifacts.sh does not exist (expected failure for RED)"
    exit 1
fi
if [ ! -x "$TRIMMER" ]; then
    chmod +x "$TRIMMER"
fi

make_good_sql() {
    local path="$1"
    { echo "--"; echo "-- PostgreSQL database dump"; echo "--"; echo "CREATE TABLE t();"; } | gzip > "$path"
}

make_hollow_sql() {
    local path="$1"
    printf '' | gzip > "$path"
}

make_good_rdb() {
    local path="$1"
    { printf 'REDIS0009\xfa\x09redis-ver\x0512.0.0\x00\x01'; printf '%0.s\x00' $(seq 1 180); } > "$path"
}

make_good_tar() {
    local path="$1" tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/tar-fixture.XXXXXX")
    printf 'data\n' > "$tmpdir/payload.txt"
    tar -czf "$path" -C "$tmpdir" payload.txt
    rm -rf "$tmpdir"
}

set_mtime_days_ago() {
    local file="$1" days="$2"
    touch -d "$days days ago" "$file"
}

new_fixture() {
    FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/trim-backup-test.XXXXXX")
    DB="$FIXTURE/databases"
    VOL="$FIXTURE/docker-volumes"
    STATE="$FIXTURE/state"
    DUMPS="$STATE/dumps"
    mkdir -p "$DB" "$VOL" "$DUMPS"
}

cleanup_fixture() {
    rm -rf "$FIXTURE"
}

run_trimmer() {
    BACKUP_DB_DIR="$DB" \
    BACKUP_VOLUME_DIR="$VOL" \
    BACKUP_TRIM_STATE_DIR="$STATE" \
    BACKUP_DUMPS_DIR="$DUMPS" \
    BACKUP_ARTIFACT_RETENTION_DAYS="${RETENTION_DAYS:-30}" \
    BACKUP_DUMP_STALE_HOURS="${DUMP_STALE_HOURS:-24}" \
        "$TRIMMER" "$@" 2>&1
}

# 1) --dry-run reports but does not delete candidates
test_dry_run() {
    local out
    RETENTION_DAYS=30
    new_fixture
    make_hollow_sql "$DB/postgres_app_20200101_000000.sql.gz"
    make_good_sql "$DB/postgres_app_20200102_000000.sql.gz"
    set_mtime_days_ago "$DB/postgres_app_20200102_000000.sql.gz" 40
    out=$(run_trimmer --dry-run)
    if [ -f "$DB/postgres_app_20200101_000000.sql.gz" ] && [ -f "$DB/postgres_app_20200102_000000.sql.gz" ]; then
        if printf '%s' "$out" | grep -qi "dry"; then
            pass "--dry-run reports candidates without deleting"
        else
            fail "--dry-run did not mention dry run in output"
            printf '%s\n' "$out" | sed 's/^/     /'
        fi
    else
        fail "--dry-run deleted files"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
    cleanup_fixture
}

# 2) Hollow/unusable removed while valid small backup preserved
test_hollow_and_valid_small() {
    local out
    RETENTION_DAYS=30
    new_fixture
    make_hollow_sql "$DB/postgres_app_20260101_000000.sql.gz"
    make_good_sql "$DB/postgres_small_20260101_000000.sql.gz" # valid small backup
    # also a valid small RDB should be preserved
    make_good_rdb "$DB/redis_backup_20260101_000000.rdb"
    printf 'notredis' > "$DB/redis_backup_bad_20260101_000000.rdb"
    out=$(run_trimmer)
    if [ ! -f "$DB/postgres_app_20260101_000000.sql.gz" ] \
       && [ -f "$DB/postgres_small_20260101_000000.sql.gz" ] \
       && [ -f "$DB/redis_backup_20260101_000000.rdb" ] \
       && [ ! -f "$DB/redis_backup_bad_20260101_000000.rdb" ]; then
        pass "hollow/unusable removed, valid small backups preserved"
    else
        fail "hollow/unusable vs valid small handling incorrect"
        printf '%s\n' "$out" | sed 's/^/     /'
        ls -la "$DB" | sed 's/^/     /'
    fi
    cleanup_fixture
}

# 3) Valid old artifacts beyond retention removed, recent kept
test_retention_age() {
    local out
    RETENTION_DAYS=30
    new_fixture
    make_good_sql "$DB/postgres_app_20200101_000000.sql.gz"
    set_mtime_days_ago "$DB/postgres_app_20200101_000000.sql.gz" 40
    make_good_sql "$DB/postgres_app_recent_20260101_000000.sql.gz"
    set_mtime_days_ago "$DB/postgres_app_recent_20260101_000000.sql.gz" 5
    make_good_tar "$VOL/spectre-suite_postgres-data_20200101_000000.tar.gz"
    set_mtime_days_ago "$VOL/spectre-suite_postgres-data_20200101_000000.tar.gz" 45
    make_good_tar "$VOL/spectre-suite_postgres-data_recent_20260101_000000.tar.gz"
    set_mtime_days_ago "$VOL/spectre-suite_postgres-data_recent_20260101_000000.tar.gz" 2
    out=$(run_trimmer)
    if [ ! -f "$DB/postgres_app_20200101_000000.sql.gz" ] \
       && [ -f "$DB/postgres_app_recent_20260101_000000.sql.gz" ] \
       && [ ! -f "$VOL/spectre-suite_postgres-data_20200101_000000.tar.gz" ] \
       && [ -f "$VOL/spectre-suite_postgres-data_recent_20260101_000000.tar.gz" ]; then
        pass "old valid artifacts removed and recent kept"
    else
        fail "retention age trimming incorrect"
        printf '%s\n' "$out" | sed 's/^/     /'
        ls -la "$DB" "$VOL" | sed 's/^/     /'
    fi
    cleanup_fixture
}

# 4) Files outside configured dirs/patterns untouched
test_outside_untouched() {
    local out OUTSIDE
    RETENTION_DAYS=30
    new_fixture
    OUTSIDE="$FIXTURE/outside"
    mkdir -p "$OUTSIDE"
    make_hollow_sql "$OUTSIDE/postgres_app_20200101_000000.sql.gz"
    set_mtime_days_ago "$OUTSIDE/postgres_app_20200101_000000.sql.gz" 40
    # non-owned pattern inside owned dir should be untouched
    printf 'keep me' > "$DB/random_notes.txt"
    set_mtime_days_ago "$DB/random_notes.txt" 40
    printf 'keep me' > "$DB/otherproject_20200101_000000.tar.gz"
    set_mtime_days_ago "$DB/otherproject_20200101_000000.tar.gz" 40
    out=$(run_trimmer)
    if [ -f "$OUTSIDE/postgres_app_20200101_000000.sql.gz" ] \
       && [ -f "$DB/random_notes.txt" ] \
       && [ -f "$DB/otherproject_20200101_000000.tar.gz" ]; then
        pass "files outside configured dirs/patterns untouched"
    else
        fail "trimmed files outside allowed scope"
        printf '%s\n' "$out" | sed 's/^/     /'
        ls -la "$OUTSIDE" "$DB" 2>/dev/null | sed 's/^/     /'
    fi
    cleanup_fixture
}

# 5) stale dump temp dirs cleaned (owned dumps path, beyond safe age)
test_stale_dumps() {
    local out
    RETENTION_DAYS=30
    DUMP_STALE_HOURS=24
    new_fixture
    mkdir -p "$DUMPS/oldrun" "$DUMPS/newrun"
    printf 'x' > "$DUMPS/oldrun/tmp.sql"
    printf 'y' > "$DUMPS/newrun/tmp.sql"
    touch -d "2 days ago" "$DUMPS/oldrun"
    touch -d "1 hour ago" "$DUMPS/newrun"
    out=$(run_trimmer)
    if [ ! -d "$DUMPS/oldrun" ] && [ -d "$DUMPS/newrun" ]; then
        pass "stale dump temp dirs cleaned, recent kept"
    else
        fail "stale dump temp dir cleanup incorrect"
        printf '%s\n' "$out" | sed 's/^/     /'
        ls -la "$DUMPS" 2>/dev/null | sed 's/^/     /'
    fi
    cleanup_fixture
}

test_dry_run
test_hollow_and_valid_small
test_retention_age
test_outside_untouched
test_stale_dumps

echo ""
echo "Backup artifact trimming tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
