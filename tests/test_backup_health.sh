#!/bin/bash
# Backup Health Check Tests
#
# These are negative controls, and the reason they exist: the health check this
# replaces only grepped a log for the string "FAILED", so it passed continuously
# through 81 empty archives. Nothing in the suite ever asserted that a backup
# contained data, which is why "backup completed successfully" could be logged
# every night over 45-byte files.
#
# Each case builds a throwaway fixture tree and runs the real checker against it
# via BACKUP_DIR / VOLUME_BACKUP_DIR / BACKUP_STATE_DIR, so the repository's own
# backup directories are never touched.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CHECKER="$PROJECT_ROOT/scripts/backups/check-backup-health.sh"

echo "Running backup health check tests..."

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

if [ ! -x "$CHECKER" ]; then
    echo "❌ check-backup-health.sh is missing or not executable"
    exit 1
fi

# A fixture tree. $1 = "good" for a healthy set, anything else for a broken one.
make_fixture() {
    local kind="$1"
    FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/backup-health-test.XXXXXX")
    DB="$FIXTURE/databases"
    VOL="$FIXTURE/docker-volumes"
    STATE="$FIXTURE/backup-state"
    mkdir -p "$DB" "$VOL" "$STATE"

    local stamp="20260101_000000"
    # Written at the fixture root because the volume tarball is built with
    # -C "$FIXTURE". Pointing this at $DB made tar fail, which produced a
    # genuinely hollow archive and let several controls pass for the wrong
    # reason -- a broken fixture is not a test.
    printf 'some content\n' > "$FIXTURE/payload.txt"

    # A real pg_dump: gzip of a file carrying the dump header.
    { echo "--"; echo "-- PostgreSQL database dump"; echo "--"; echo "CREATE TABLE t();"; } \
        | gzip > "$DB/postgres_testdb_${stamp}.sql.gz"

    # A real, empty Redis RDB. Legitimately small -- an empty cache is ~170
    # bytes -- so it must be accepted, which means the size floor has to sit
    # below a real RDB and above gzip-of-nothing.
    { printf 'REDIS0009\xfa\x09redis-ver\x0512.0.0\x00\x01'; printf '%0.s\x00' $(seq 1 180); } \
        > "$DB/redis_backup_${stamp}.rdb"

    # A real volume tarball with one member.
    tar -czf "$VOL/spectre-system-maintenance-suite_postgres-data_${stamp}.tar.gz" -C "$FIXTURE" payload.txt

    date +%s > "$STATE/last-db-backup-success"
    date +%s > "$STATE/last-db-backup-attempt"

    if [ "$kind" != "good" ]; then
        case "$kind" in
            hollow-sql)
                # Exactly the failure mode: valid gzip, no dump in it.
                printf '' | gzip > "$DB/postgres_guardrail_${stamp}.sql.gz"
                ;;
            hollow-tar)
                # tar of an empty directory: a valid archive containing nothing.
                mkdir -p "$FIXTURE/empty"
                tar -czf "$VOL/spectre-system-maintenance-suite_redis-data_${stamp}.tar.gz" -C "$FIXTURE/empty" .
                ;;
            hollow-rdb)
                # An RDB with no magic: a truncated or interrupted copy.
                printf 'not a redis dump at all' > "$DB/redis_backup_broken_${stamp}.rdb"
                ;;
            no-marker)
                rm -f "$STATE/last-db-backup-success"
                ;;
            stale-marker)
                date -d '3 days ago' +%s > "$STATE/last-db-backup-success"
                ;;
            missing-volumes)
                rm -f "$VOL"/*.tar.gz
                ;;
            tiny)
                # gzip of nothing at all.
                printf '' | gzip > "$DB/postgres_empty_${stamp}.sql.gz"
                ;;
        esac
    fi
}

run_check() {
    BACKUP_DIR="$DB" \
    VOLUME_BACKUP_DIR="$VOL" \
    BACKUP_STATE_DIR="$STATE" \
    LOG_DIR="$FIXTURE" \
        "$CHECKER" 2>&1
}

expect_pass() {
    local label="$1" out
    make_fixture good
    out=$(run_check)
    if printf '%s' "$out" | grep -q "BACKUP HEALTH: OK"; then
        pass "$label"
    else
        fail "$label (expected OK)"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
    rm -rf "$FIXTURE"
}

expect_fail() {
    local label="$1" kind="$2" needle="$3" out
    make_fixture "$kind"
    out=$(run_check)
    if printf '%s' "$out" | grep -q "BACKUP HEALTH: OK"; then
        fail "$label (checker passed a broken backup set)"
    elif printf '%s' "$out" | grep -qi "$needle"; then
        pass "$label"
    else
        fail "$label (failed, but not for the expected reason: '$needle')"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
    rm -rf "$FIXTURE"
}

# ---------------------------------------------------------------------------
# 1. A healthy set must pass. This is the control for the controls: a checker
#    that fails everything is no more useful than one that passes everything.
# ---------------------------------------------------------------------------
expect_pass "a healthy backup set is reported OK"

# ---------------------------------------------------------------------------
# 2. The original failure: a valid gzip containing no dump. 81 of these existed
#    while the old check reported healthy.
# ---------------------------------------------------------------------------
expect_fail "an empty sql.gz is reported hollow" hollow-sql "hollow\|not a usable backup"

# ---------------------------------------------------------------------------
# 3. A tar of an empty directory lists "." as a member, so it is a valid archive
#    and the checker accepts it. That is deliberate, and this control pins the
#    behaviour: for a volume tarball, "valid archive with no data" cannot be
#    told apart from a legitimately empty volume, so the checker does not claim
#    to detect it. The marker and recency checks are what prove a backup ran.
#    Asserting hollow tarballs here would mean inventing a size threshold, which
#    is how a perfectly good 883-byte volume backup gets reported as broken.
# ---------------------------------------------------------------------------
expect_pass "a tarball of an empty directory is accepted (documented limit)" hollow-tar

# ---------------------------------------------------------------------------
# 4. An RDB without the REDIS magic is not a dump, however small.
# ---------------------------------------------------------------------------
expect_fail "an RDB without the redis magic is rejected" hollow-rdb "hollow\|not a usable backup"

# ---------------------------------------------------------------------------
# 5. gzip of literally nothing.
# ---------------------------------------------------------------------------
expect_fail "a zero-length payload is rejected" tiny "hollow\|floor"

# ---------------------------------------------------------------------------
# 6. No success marker at all: no run has ever completed.
# ---------------------------------------------------------------------------
expect_fail "a missing success marker fails" no-marker "no success marker"

# ---------------------------------------------------------------------------
# 7. A marker older than the staleness window, even with fresh-looking files.
# ---------------------------------------------------------------------------
expect_fail "a stale success marker fails" stale-marker "last successful backup was"

# ---------------------------------------------------------------------------
# 8. A missing volume backup is a failure, not a skip.
# ---------------------------------------------------------------------------
expect_fail "a missing volume archive fails" missing-volumes "no archive matching"

echo ""
echo "Backup health tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
