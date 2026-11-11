#!/bin/bash
# Test configurable, tag-scoped restic retention args (backward-compatible defaults).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS=0
FAIL=0
pass() { echo "✅ $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ $1"; FAIL=$((FAIL + 1)); }

# shellcheck disable=SC1091
. "$PROJECT_ROOT/spectre/actions/backups/restic/common.sh"

default_out="$(restic_forget_args)"
expected_default="--tag spectre-suite --keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1"
if [ "$default_out" = "$expected_default" ]; then
  pass "default restic_forget_args uses tag-scoped defaults"
else
  fail "default restic_forget_args mismatch"
  echo "  expected: $expected_default"
  echo "  got:      $default_out"
fi

override_out="$(RESTIC_TAG=mytag RESTIC_KEEP_DAILY=14 RESTIC_KEEP_WEEKLY=8 restic_forget_args)"
case "$override_out" in
  *"--tag mytag"*) : ;;
  *) fail "override restic_forget_args missing --tag mytag"; echo "  got: $override_out" ;;
esac
case "$override_out" in
  *"--keep-daily 14"*) : ;;
  *) fail "override restic_forget_args missing --keep-daily 14"; echo "  got: $override_out" ;;
esac
case "$override_out" in
  *"--keep-weekly 8"*) : ;;
  *) fail "override restic_forget_args missing --keep-weekly 8"; echo "  got: $override_out" ;;
esac
# unchanged defaults still present
case "$override_out" in
  *"--keep-hourly 24"*|*"--keep-monthly 12"*|*"--keep-last 1"*) : ;;
  *) fail "override restic_forget_args lost unchanged defaults"; echo "  got: $override_out" ;;
esac
# still tag-scoped and no default tag leaked
case "$override_out" in
  *"--tag spectre-suite"*) fail "override restic_forget_args leaked default tag"; echo "  got: $override_out" ;;
  *) pass "override restic_forget_args is tag-scoped with env overrides" ;;
esac

echo ""
echo "restic retention config tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
