#!/bin/bash
# Test: backup-configurations.sh produces copied artifacts readable by the invoking user (restic).
# Review Focus 5 / spec §2.3: sudo cp left root:root 0600 files unreadable by a user-run restic backup.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_ROOT/spectre/actions/backups/backup-configurations.sh" ]; then TARGET="$PROJECT_ROOT/spectre/actions/backups/backup-configurations.sh"; else TARGET="$PROJECT_ROOT/scripts/backups/backup-configurations.sh"; fi

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/backup-config-perms.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# Fixtures for root-owned source files (readable in test).
mkdir -p "$tmp/etc/ssh" "$tmp/etc/fail2ban" "$tmp/etc/dnf"
printf 'sshd fixture\n' > "$tmp/etc/ssh/sshd_config"
printf 'jail fixture\n' > "$tmp/etc/fail2ban/jail.local"
printf 'dnf fixture\n' > "$tmp/etc/dnf/dnf5-automatic.conf"

BACKUP_DIR="$tmp/backups"
mkdir -p "$BACKUP_DIR"
DATE="20260101_000000"

# Run with seams: no real sudo, override source paths, stable date/dirs.
# The script may emit noise from system probes (firewall/docker/systemd tar); we
# only assert the three copied artifacts' existence, ownership/readability, and mode.
set +e
env \
  BACKUP_DIR="$BACKUP_DIR" \
  DATE="$DATE" \
  SUDO_CMD="" \
  SSHD_CONFIG_SRC="$tmp/etc/ssh/sshd_config" \
  FAIL2BAN_JAIL_SRC="$tmp/etc/fail2ban/jail.local" \
  DNF_AUTOMATIC_SRC="$tmp/etc/dnf/dnf5-automatic.conf" \
  PROJECTS_DIR="$tmp/no-projects" \
  PATH="$PATH" \
  bash "$TARGET" >"$tmp/out.log" 2>"$tmp/err.log"
status=$?
set -e
if [ "$status" -ne 0 ]; then
  echo "--- stdout ---"; cat "$tmp/out.log" || true
  echo "--- stderr ---"; cat "$tmp/err.log" || true
  fail "backup-configurations.sh exited $status under test seams"
fi

for name in "sshd_config_$DATE" "fail2ban_jail_$DATE" "dnf-automatic_$DATE"; do
  out="$BACKUP_DIR/$name"
  [ -e "$out" ] || fail "$name not created (restic artifact missing)"
  [ -r "$out" ] || fail "$name not readable by invoking user (restic would skip it)"
  mode=$(stat -c '%a' "$out")
  case "$mode" in
    600|640) ;;
    *) fail "$name mode $mode; expected 0600 or 0640 (readable by owner, not world-writable)" ;;
  esac
  # Must not be root-owned in a way that blocks the user; running as non-root, file should be owned by us.
  owner_uid=$(stat -c '%u' "$out")
  [ "$owner_uid" = "$(id -u)" ] || fail "$name owned by uid $owner_uid, expected $(id -u)"
  pass "$name readable (mode $mode, uid $owner_uid)"
done

pass "backup-configurations permissions"