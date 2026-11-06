#!/bin/bash
# Test: exporter reads restic markers and emits restic_* gauges (spec §7.6).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPORTER="$PROJECT_ROOT/prometheus/business-metrics-exporter.sh"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/restic-exp.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/markers" "$tmp/out" "$tmp/repo" "$tmp/backup-state"
echo "1730000000 deadbeef" > "$tmp/markers/last-success"
echo "1730000001" > "$tmp/markers/last-attempt"
# last-offsite-success missing
echo "0 1730000100" > "$tmp/markers/last-health"
echo "garbage" > "$tmp/markers/last-verify"

env \
  RESTIC_MARKER_DIR="$tmp/markers" \
  OUTPUT_DIR="$tmp/out" \
  BACKUP_REPO_DIR="$tmp/repo" \
  BACKUP_STATE_DIR="$tmp/backup-state" \
  bash "$EXPORTER" "$tmp/out" >/dev/null 2>&1 || true

out="$tmp/out/backup_metrics.prom"
[ -f "$out" ] || fail "backup_metrics.prom not produced"
grep -qx 'restic_last_success_timestamp 1730000000' "$out" || fail "restic_last_success_timestamp wrong: $(grep restic_last_success_timestamp "$out" || true)"
grep -qx 'restic_last_offsite_success_timestamp 0' "$out" || fail "missing offsite must be 0: $(grep restic_last_offsite_timestamp "$out" || true)"
grep -qx 'restic_health_ok 0' "$out" || fail "restic_health_ok wrong: $(grep restic_health_ok "$out" || true)"
grep -qx 'restic_health_timestamp 1730000100' "$out" || fail "restic_health_timestamp wrong: $(grep restic_health_timestamp "$out" || true)"
grep -qx 'restic_verify_timestamp 0' "$out" || fail "unparseable verify timestamp must be 0: $(grep restic_verify_timestamp "$out" || true)"
grep -qx 'restic_last_attempt_timestamp 1730000001' "$out" || fail "restic_last_attempt_timestamp wrong"
grep -qx 'restic_verify_ok 0' "$out" || fail "restic_verify_ok wrong"
pass "restic marker metrics exported with missing/unparseable => 0"
