#!/bin/bash
# Restore verdict exporter tests.
#
# spectre/actions/backups/restore-all.sh writes $BACKUP_STATE_DIR/last-restore-health
# as `ok <epoch>` or `failed <epoch> <detail>`, but nothing read it: the
# business-metrics exporter carried only the backup *health* verdict, so a restore
# that had failed (or never run) was invisible in Prometheus, and an operator who
# ran a disaster recovery had no signal at all. These cases assert that the
# exporter publishes the restore verdict and that a failed restore raises.
#
# The exporter is invoked with an output dir and reads marker files from env, so
# every case writes a marker into a temp dir and checks the .prom it produces.
# No restic, no docker, no network.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPORTER="$PROJECT_ROOT/spectre/monitoring/exporters/business-metrics-exporter.sh"

echo "Running restore verdict exporter tests..."

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

if [ ! -x "$EXPORTER" ]; then
    echo "❌ business-metrics-exporter.sh is missing or not executable"
    exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/restore-exporter-test.XXXXXX")
STATE="$WORK/state"
OUT="$WORK/out"
mkdir -p "$STATE" "$OUT"

metric() { grep "^$1 " "$OUT/backup_metrics.prom" 2>/dev/null | awk '{print $2}'; }
has_metric() { grep -q "^$1" "$OUT/backup_metrics.prom" 2>/dev/null; }

run_exporter() {
    BACKUP_STATE_DIR="$STATE" \
    BACKUP_REPO_DIR="$WORK/nonexistent-repo" \
    RESTIC_MARKER_DIR="$WORK/nonexistent-markers" \
    "$EXPORTER" "$OUT" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# 1. No restore has ever run: the verdict is absent, so the metrics read 0.
#    0 keeps `time() - value > threshold` true, so a never-run restore raises
#    rather than reading as healthy -- the same rule the backup health metrics
#    follow, and the reason 81 empty archives survived.
# ---------------------------------------------------------------------------
rm -f "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_health_ok)" = "0" ] \
   && [ "$(metric restore_health_timestamp)" = "0" ] \
   && [ "$(metric restore_rsync_download_only)" = "0" ]; then
    pass "no restore verdict published reads as 0, not healthy"
else
    fail "no restore verdict mishandled (ok=$(metric restore_health_ok) ts=$(metric restore_health_timestamp) rsync=$(metric restore_rsync_download_only))"
fi

# ---------------------------------------------------------------------------
# 2. A successful restore publishes ok=1 and the recorded epoch.
# ---------------------------------------------------------------------------
EPOCH=1700000000
printf 'ok %s\n' "$EPOCH" > "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_health_ok)" = "1" ] && [ "$(metric restore_health_timestamp)" = "$EPOCH" ]; then
    pass "a successful restore publishes ok=1 and its epoch"
else
    fail "successful restore not published (ok=$(metric restore_health_ok) ts=$(metric restore_health_timestamp))"
fi

# ---------------------------------------------------------------------------
# 3. A failed restore publishes ok=0 with the same epoch, so the failure is
#    timestamped and alertable.
# ---------------------------------------------------------------------------
printf 'failed %s databases=1 volumes=2\n' "$EPOCH" > "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_health_ok)" = "0" ] && [ "$(metric restore_health_timestamp)" = "$EPOCH" ]; then
    pass "a failed restore publishes ok=0 with its epoch"
else
    fail "failed restore not published (ok=$(metric restore_health_ok) ts=$(metric restore_health_timestamp))"
fi

# ---------------------------------------------------------------------------
# 4. An rsync download-only restore exits 0 and is NOT a completed restore.
#    restore-from-remote.sh's rsync path only downloads to /tmp, so it must
#    read as healthy (it did what it was asked) while a separate gauge says
#    nothing was applied -- otherwise a download reads as a restore in
#    Prometheus exactly the way it misread in the script summary.
# ---------------------------------------------------------------------------
printf 'ok %s remote=rsync-download-only\n' "$EPOCH" > "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_health_ok)" = "1" ] \
   && [ "$(metric restore_health_timestamp)" = "$EPOCH" ] \
   && [ "$(metric restore_rsync_download_only)" = "1" ]; then
    pass "an rsync download-only restore is healthy but flagged, not a completed restore"
else
    fail "rsync download-only not flagged (ok=$(metric restore_health_ok) rsync=$(metric restore_rsync_download_only))"
fi

# ---------------------------------------------------------------------------
# 5. A real s3/b2 restore has no download-only flag.
# ---------------------------------------------------------------------------
printf 'ok %s\n' "$EPOCH" > "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_rsync_download_only)" = "0" ]; then
    pass "a real in-place restore is not flagged as download-only"
else
    fail "a real restore was flagged download-only"
fi

# ---------------------------------------------------------------------------
# 6. The verdict marker is unreadable garbage: the exporter must not parse a
#    bogus first token as "ok". A malformed marker is a failed restore, not a
#    healthy one.
# ---------------------------------------------------------------------------
printf 'maybe %s\n' "$EPOCH" > "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_health_ok)" = "0" ] && [ "$(metric restore_health_timestamp)" = "0" ]; then
    pass "a malformed verdict is not parsed as healthy"
else
    fail "malformed verdict parsed as ok (ok=$(metric restore_health_ok) ts=$(metric restore_health_timestamp))"
fi

# ---------------------------------------------------------------------------
# 7. A dry-run verdict is a rehearsal, not a completed restore and not a
#    failure. It keeps its timestamp so the exporter can tell "rehearsed,
#    never executed" from "never touched at all", but restore_health_ok stays
#    0 and restore_dryrun is 1 -- so RestoreFailed, which requires
#    restore_dryrun == 0, does not fire after every dry-run. That would be the
#    opposite of the alert's purpose: it is meant to catch a restore that ran
#    and broke, not a plan that was reviewed.
# ---------------------------------------------------------------------------
printf 'dryrun %s\n' "$EPOCH" > "$STATE/last-restore-health"
run_exporter
if [ "$(metric restore_health_ok)" = "0" ] \
   && [ "$(metric restore_dryrun)" = "1" ] \
   && [ "$(metric restore_health_timestamp)" = "$EPOCH" ]; then
    pass "a dry-run verdict is published as dryrun, not ok and not failed"
else
    fail "dry-run verdict mishandled (ok=$(metric restore_health_ok) dryrun=$(metric restore_dryrun) ts=$(metric restore_health_timestamp))"
fi

rm -rf "$WORK"

echo ""
echo "Restore verdict exporter tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]