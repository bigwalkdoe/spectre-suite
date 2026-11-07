#!/bin/bash
# Integration tests for adopted restic backup flow (temp repo). Spec §7.8 / Review Focus 4.
set -euo pipefail

if ! command -v restic >/dev/null 2>&1; then
  echo "SKIP: restic not installed"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_ROOT/spectre/actions/backups/restic/backup.sh" ]; then BACKUP="$PROJECT_ROOT/spectre/actions/backups/restic/backup.sh"; else BACKUP="$PROJECT_ROOT/scripts/backups/restic/backup.sh"; fi
# shellcheck source=../spectre/actions/backups/restic/common.sh
if [ -f "$PROJECT_ROOT/spectre/actions/backups/restic/common.sh" ]; then . "$PROJECT_ROOT/spectre/actions/backups/restic/common.sh"; else . "$PROJECT_ROOT/scripts/backups/restic/common.sh"; fi

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/restic-int.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/dev" "$HOME/docs" "$HOME/.secrets"
printf 'dev-data\n' > "$HOME/dev/file.txt"
printf 'doc-data\n' > "$HOME/docs/file.txt"
printf 'sec-data\n' > "$HOME/.secrets/some-secret" # not the repo key; key excluded by path

repo="$tmp/repo"
pw="$tmp/password"
printf 'test-password' > "$pw"; chmod 600 "$pw"
export RESTIC_PASSWORD_FILE="$pw"
export RESTIC_REPOSITORY_LOCAL="$repo"
export RESTIC_REPOSITORY="rclone:nonexistent-remote-for-test:"
export RESTIC_TAG="spectre-suite"
export RESTIC_HOST="testhost"
export CONFIG_DIR="$tmp/config"
export STATE_DIR="$tmp/state"
export MARKER_DIR="$STATE_DIR"
export LOG_DIR="$STATE_DIR"
mkdir -p "$CONFIG_DIR" "$STATE_DIR"
cat > "$CONFIG_DIR/include.conf" <<EOF
$HOME/dev
$HOME/docs
$HOME/.secrets
EOF
cat > "$CONFIG_DIR/exclude.conf" <<EOF
$HOME/.secrets/spectre-restic-password
$HOME/.secrets/restic-repo-password
EOF
cat > "$CONFIG_DIR/include-remote.conf" <<EOF
$HOME/docs
EOF
: > "$CONFIG_DIR/include-artifacts.conf"
export INCLUDE_FILE="$CONFIG_DIR/include.conf"
export EXCLUDE_FILE="$CONFIG_DIR/exclude.conf"
export INCLUDE_FILE_REMOTE="$CONFIG_DIR/include-remote.conf"
export INCLUDE_FILE_ARTIFACTS="$CONFIG_DIR/include-artifacts.conf"
export RESTIC_SKIP_OFFSITE=1
export RESTIC_SKIP_PG=1
export RESTIC_SKIP_CONTAINERS=1
export RESTIC_SKIP_GIT_MIRROR=1
export NOTIFY_ENABLED=false
export PG_ENABLED=false
export CONTAINERS_ENABLED=false
export BACKUP_LOG_STDOUT=1
# Prevent load_restic_env from sourcing the real workstation env (it would override
# temp repo/password). Tests control all required vars explicitly.
export RESTIC_CONFIG="$CONFIG_DIR/restic.env.nonexistent"

# Local backup success
set +e
out=$(bash "$BACKUP" 2>&1); status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "$out"
  fail "backup.sh failed locally (status $status)"
fi
[ -f "$STATE_DIR/last-attempt" ] || fail "last-attempt marker missing"
[ -f "$STATE_DIR/last-success" ] || fail "last-success marker missing"
epoch=$(read_marker_epoch "$STATE_DIR/last-success")
[ "$epoch" -gt 0 ] 2>/dev/null || fail "last-success epoch invalid: $(cat "$STATE_DIR/last-success")"
snap_json=$(RESTIC_PASSWORD_FILE="$pw" restic -r "$repo" snapshots --latest 1 --json)
echo "$snap_json" | grep -q '"spectre-suite"' || fail "snapshot missing spectre-suite tag: $snap_json"
echo "$snap_json" | grep -q '"workstation"' || fail "snapshot missing workstation tag: $snap_json"
sid=$(echo "$snap_json" | jq -r '.[0].short_id // .[0].id')
pass "local backup creates tagged snapshot and success markers"

# verify + restore wrappers
export BACKUP_LOG_STDOUT=1
bash "$PROJECT_ROOT/spectre/actions/backups/restic/verify.sh" --local >/dev/null 2>&1 || fail "verify.sh failed on temp repo"
[ -f "$STATE_DIR/last-verify" ] || fail "verify.sh did not write last-verify"
bash "$PROJECT_ROOT/spectre/actions/backups/restic/restore.sh" --snapshot "$sid" --dry-run --target "$tmp/restore-target" --local >/dev/null 2>&1 || fail "restore.sh --dry-run failed"
pass "verify and restore wrappers work on tagged snapshot"

# Degraded offsite (local must still succeed) - Review Focus 4
export RESTIC_SKIP_OFFSITE=0
export RCLONE_CMD=false
export RESTIC_REPOSITORY="rclone:broken-remote:"
rm -f "$STATE_DIR/last-offsite-success"
set +e
out=$(bash "$BACKUP" 2>&1); status=$?
set -e
# local ok but offsite degraded => 0 or 2; must not be 1 and must keep local success
[ "$status" -eq 0 ] || [ "$status" -eq 2 ] || { echo "$out"; fail "offsite failure must not fail local backup (got $status)"; }
[ -f "$STATE_DIR/last-success" ] || fail "local success missing after offsite failure"
if [ -f "$STATE_DIR/last-offsite-success" ]; then
  off=$(read_marker_epoch "$STATE_DIR/last-offsite-success")
  [ "$off" -eq 0 ] 2>/dev/null || fail "last-offsite-success should not record a real success after offsite failure"
fi
[ -f "$STATE_DIR/last-health" ] || fail "last-health marker missing after degraded run"
pass "offsite failure is degraded; local success preserved"

pass "restic integration checks passed"
