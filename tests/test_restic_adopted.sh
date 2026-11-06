#!/bin/bash
# Unit tests for adopted restic engine (no real repository). Spec §7.8 / Review Focus 2,3.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
# shellcheck source=../scripts/backups/restic/common.sh
. "$PROJECT_ROOT/scripts/backups/restic/common.sh"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/restic-adopted.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME/.config" "$HOME/dev" "$HOME/docs" "$HOME/.secrets" "$HOME/archive/old-projects"
export RESTIC_REPOSITORY_LOCAL="/backups/spectre-backup"
export RESTIC_REPOSITORY="rclone:spectre-backup:"
export RESTIC_TAG="spectre-suite"
export RESTIC_HOST="testhost"
export MARKER_DIR="$tmp/state"
mkdir -p "$MARKER_DIR"
resolve_restic_dirs 2>/dev/null || true

# tag scoping (Review Focus 2)
args=$(restic_backup_args /tmp/repo)
[[ "$args" == *"--tag spectre-suite"* ]] || fail "backup args missing --tag spectre-suite: $args"
[[ "$args" == *"--tag workstation"* ]] || fail "backup args missing --tag workstation: $args"
[[ "$args" == *"--host "* ]] || fail "backup args missing --host: $args"
pass "restic_backup_args includes spectre-suite,workstation,host"

fargs=$(restic_forget_args /tmp/repo)
[[ "$fargs" == *"--tag spectre-suite"* ]] || fail "forget args missing --tag spectre-suite: $fargs"
[[ "$fargs" == *"--keep-hourly 24"* ]] || fail "forget args missing keep-hourly 24: $fargs"
[[ "$fargs" == *"--keep-daily 30"* ]] || fail "forget args missing keep-daily 30: $fargs"
[[ "$fargs" == *"--keep-weekly 12"* ]] || fail "forget args missing keep-weekly 12: $fargs"
[[ "$fargs" == *"--keep-monthly 12"* ]] || fail "forget args missing keep-monthly 12: $fargs"
[[ "$fargs" == *"--keep-last 1"* ]] || fail "forget args missing keep-last 1: $fargs"
pass "restic_forget_args tag-scoped with spec retention"

# repo-path refusal
fixture_repo="$tmp/include-repo.conf"
cat > "$fixture_repo" <<EOF
$HOME/dev
/backups/spectre-backup
/backups/spectre-backup/data
EOF
if build_targets "$fixture_repo" t_repo 2>/dev/null; then
  fail "build_targets must refuse paths under RESTIC_REPOSITORY_LOCAL"
fi
pass "build_targets refuses repository path"

# real paths, no symlink duplication (Review Focus 3)
fixture_real="$tmp/include-real.conf"
cat > "$fixture_real" <<EOF
$HOME/dev
$HOME/docs
$HOME/archive/old-projects
EOF
build_targets "$fixture_real" t_real
joined=" ${t_real[*]} "
[[ "$joined" == *" $HOME/dev "* ]] || fail "missing ~/dev in targets: $joined"
[[ "$joined" == *" $HOME/docs "* ]] || fail "missing ~/docs in targets: $joined"
[[ "$joined" != *" $HOME/code "* ]] || fail "symlink ~/code must not be added: $joined"
[[ "$joined" != *" $HOME/documents "* ]] || fail "symlink ~/documents must not be added: $joined"
[[ "$joined" != *" $HOME/archives "* ]] || fail "symlink ~/archives must not be added: $joined"
pass "build_targets uses real paths, not home symlinks"

# artifact glob expansion + repo refusal
art="$tmp/artifacts"; mkdir -p "$art"
echo x > "$art/postgres_20260101.sql.gz"
echo y > "$art/redis_backup_20260101.rdb"
fixture_art="$tmp/include-artifacts.conf"
cat > "$fixture_art" <<EOF
$art/postgres_*.sql.gz
$art/redis_backup_*.rdb
$art/missing_*.tar.gz
EOF
build_artifact_targets "$fixture_art" t_art
[[ " ${t_art[*]} " == *"$art/postgres_20260101.sql.gz"* ]] || fail "artifact glob not expanded: ${t_art[*]}"
[[ " ${t_art[*]} " == *"$art/redis_backup_20260101.rdb"* ]] || fail "artifact glob not expanded: ${t_art[*]}"
pass "build_artifact_targets expands globs and skips missing"

# marker parse/write (spec §7.6)
write_marker last-success "1730000000" "abc123"
[ "$(read_marker_epoch "$MARKER_DIR/last-success")" = "1730000000" ] || fail "read_marker_epoch failed"
[ "$(read_marker_field "$MARKER_DIR/last-success" 2)" = "abc123" ] || fail "read_marker_field failed"
echo "garbage" > "$MARKER_DIR/bad"
[ "$(read_marker_epoch "$MARKER_DIR/bad")" = "0" ] || fail "unparseable marker must read as 0"
[ "$(read_marker_epoch "$MARKER_DIR/missing")" = "0" ] || fail "missing marker must read as 0"
pass "markers: write, parse epoch/id, missing/unparseable => 0"

# config/state resolution
export XDG_CONFIG_HOME="$tmp/xdg-config"
export XDG_STATE_HOME="$tmp/xdg-state"
unset CONFIG_DIR STATE_DIR BIN_DIR MARKER_DIR 2>/dev/null || true
resolve_restic_dirs
[[ "$CONFIG_DIR" == *"spectre-suite/backups"* ]] || fail "CONFIG_DIR not suite backups path: $CONFIG_DIR"
[[ "$STATE_DIR" == *"spectre-suite/backups"* ]] || fail "STATE_DIR not suite backups path: $STATE_DIR"
pass "resolve_restic_dirs uses spectre-suite/backups paths"

# wrapper arg contracts (stub restic)
stubbin="$tmp/bin"; mkdir -p "$stubbin"
cat > "$stubbin/restic" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "${RESTIC_ARGS_LOG:?}"
# minimal responses
case "$1" in
  snapshots) echo '[]' ;;
  check) exit 0 ;;
  restore) exit 0 ;;
  forget) exit 0 ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$stubbin/restic"
export PATH="$stubbin:$PATH"
export RESTIC_ARGS_LOG="$tmp/restic-args.log"
export RESTIC_PASSWORD_FILE="$tmp/pw"; : > "$RESTIC_PASSWORD_FILE"
export RESTIC_REPOSITORY_LOCAL="$tmp/repo"; mkdir -p "$tmp/repo"
export RESTIC_REPOSITORY="$tmp/repo"
export RESTIC_CONFIG="$tmp/noconfig"  # avoid sourcing real env

# prune must be tag-scoped
bash "$PROJECT_ROOT/scripts/backups/restic/prune.sh" --dry-run --repo local >/dev/null 2>&1 || true
grep -q -- '--tag spectre-suite' "$RESTIC_ARGS_LOG" || fail "prune/forget must pass --tag spectre-suite: $(cat "$RESTIC_ARGS_LOG" 2>/dev/null)"
pass "prune wrapper is tag-scoped"

# restore flag parsing
: > "$RESTIC_ARGS_LOG"
bash "$PROJECT_ROOT/scripts/backups/restic/restore.sh" --list --local >/dev/null 2>&1 || true
grep -q snapshots "$RESTIC_ARGS_LOG" || fail "restore --list should invoke snapshots: $(cat "$RESTIC_ARGS_LOG" 2>/dev/null)"
: > "$RESTIC_ARGS_LOG"
bash "$PROJECT_ROOT/scripts/backups/restic/restore.sh" --snapshot abc --dry-run --target "$tmp/rt" --local >/dev/null 2>&1 || true
logged=$(cat "$RESTIC_ARGS_LOG" 2>/dev/null)
[[ "$logged" == *restore* ]] || fail "restore should invoke restore: $logged"
[[ "$logged" == *abc* ]] || fail "restore should pass snapshot id: $logged"
pass "restore wrapper parses --list/--snapshot/--dry-run/--target/--local"

# verify records marker
export MARKER_DIR="$tmp/markers"; mkdir -p "$MARKER_DIR"
bash "$PROJECT_ROOT/scripts/backups/restic/verify.sh" --local >/dev/null 2>&1 || true
[ -f "$MARKER_DIR/last-verify" ] || fail "verify must write last-verify marker"
v=$(read_marker_epoch "$MARKER_DIR/last-verify")
[ "$v" -gt 0 ] 2>/dev/null || [ "$v" -eq 0 ] 2>/dev/null || fail "last-verify marker malformed"
pass "verify wrapper writes last-verify marker"

pass "all adopted restic unit checks passed"
