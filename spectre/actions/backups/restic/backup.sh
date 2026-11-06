#!/bin/bash
# Adopted restic backup engine for spectre-suite.
# Source of behavior: ~//dev/github/spectre-backup/scripts/spectre-backup.sh
# Suite contracts: spectre-suite config/state/markers, tags spectre-suite,workstation,
# tag-scoped forget, local-first, offsite degraded (never blocks local success).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

# --- Args ---
NO_PRUNE=false
JSON_OUTPUT=false
QUIET=false
DO_HEALTH=false
for arg in "${@:-}"; do
  case "$arg" in
    --no-prune) NO_PRUNE=true ;;
    --json) JSON_OUTPUT=true ;;
    --quiet|-q) QUIET=true ;;
    --health) DO_HEALTH=true ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--health] [--no-prune] [--json] [--quiet]
Adopted spectre-suite restic backup (local + offsite degraded).
EOF
      exit 0 ;;
    *) ;;
  esac
done

START_TS=$(date +%s)
resolve_restic_dirs
load_restic_env || true

# Defaults (preserve deployed values; env/config may override)
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:spectre-backup:}"
RESTIC_REPOSITORY_LOCAL="${RESTIC_REPOSITORY_LOCAL:-/backups/spectre-backup}"
RESTIC_PASSWORD_FILE="${RESTIC_PASSWORD_FILE:-$HOME/.secrets/spectre-restic-password}"
RESTIC_TAG="${RESTIC_TAG:-spectre-suite}"
RESTIC_HOST="${RESTIC_HOST:-$(hostname -s 2>/dev/null || hostname)}"
INCLUDE_FILE="${INCLUDE_FILE:-$CONFIG_DIR/include.conf}"
EXCLUDE_FILE="${EXCLUDE_FILE:-$CONFIG_DIR/exclude.conf}"
INCLUDE_FILE_REMOTE="${INCLUDE_FILE_REMOTE:-$CONFIG_DIR/include-remote.conf}"
INCLUDE_FILE_ARTIFACTS="${INCLUDE_FILE_ARTIFACTS:-$CONFIG_DIR/include-artifacts.conf}"
NOTIFY_ENABLED="${NOTIFY_ENABLED:-false}"
PG_ENABLED="${PG_ENABLED:-true}"
PG_HOST="${PG_HOST:-/var/run/postgresql}"
PG_PORT="${PG_PORT:-5432}"
PG_USER="${PG_USER:-$(id -un)}"
CONTAINERS_ENABLED="${CONTAINERS_ENABLED:-true}"
RESTIC_SKIP_OFFSITE="${RESTIC_SKIP_OFFSITE:-0}"
RESTIC_SKIP_PG="${RESTIC_SKIP_PG:-0}"
RESTIC_SKIP_CONTAINERS="${RESTIC_SKIP_CONTAINERS:-0}"
RESTIC_SKIP_GIT_MIRROR="${RESTIC_SKIP_GIT_MIRROR:-0}"

mkdir -p "$STATE_DIR" "$DUMPS_DIR" "$MARKER_DIR"
LOG_FILE="${LOG_FILE:-$LOG_DIR/backup.log}"
if [ "${BACKUP_LOG_STDOUT:-0}" != "1" ]; then
  exec >>"$LOG_FILE" 2>&1
fi

notify() {
  local title="$1" msg="$2" urgency="${3:-normal}"
  [ "$NOTIFY_ENABLED" = "true" ] || return 0
  command -v notify-send >/dev/null 2>&1 && notify-send -u "$urgency" "$title" "$msg" 2>/dev/null || true
}

if [ -n "${RESTIC_PASSWORD_FILE:-}" ] && [ -f "$RESTIC_PASSWORD_FILE" ]; then
  export RESTIC_PASSWORD_FILE
  unset RESTIC_PASSWORD_COMMAND RESTIC_PASSWORD 2>/dev/null || true
fi

header "spectre-suite restic backup"
write_marker last-attempt "$(date +%s)"

OVERALL_DEGRADED=0
LOCAL_OK=0
OFFSITE_OK=0
OFFSITE_ATTEMPTED=0

# --- Phase 1: git mirror ---
if [ "$RESTIC_SKIP_GIT_MIRROR" != "1" ] && [ -x "$SCRIPT_DIR/git-mirror.sh" ]; then
  info "Refreshing git mirrors..."
  "$SCRIPT_DIR/git-mirror.sh" || warn "Git mirror refresh failed (continuing)"
else
  info "Git mirror skipped"
fi

# --- Phase 2: host pg_dumpall (best effort; does not block container dumps) ---
if [ "$RESTIC_SKIP_PG" != "1" ] && [ "$PG_ENABLED" = "true" ] && command -v pg_dumpall >/dev/null 2>&1; then
  info "Dumping host PostgreSQL cluster..."
  if pg_dumpall -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" > "$DUMPS_DIR/host-pg_dumpall.sql" 2>"$DUMPS_DIR/host-pg_dumpall.err"; then
    gzip -f "$DUMPS_DIR/host-pg_dumpall.sql" 2>/dev/null || true
    info "Host pg_dumpall complete"
  else
    warn "Host pg_dumpall failed (see $DUMPS_DIR/host-pg_dumpall.err); continuing"
    OVERALL_DEGRADED=1
  fi
else
  info "Host PostgreSQL dump skipped"
fi

# --- Phase 3: container configs (best effort) ---
if [ "$RESTIC_SKIP_CONTAINERS" != "1" ] && [ "$CONTAINERS_ENABLED" = "true" ]; then
  info "Collecting container configuration..."
  cdir="$DUMPS_DIR/container-config"; mkdir -p "$cdir"
  if command -v docker >/dev/null 2>&1; then docker ps -a --format '{{json .}}' > "$cdir/docker-ps.json" 2>/dev/null || true; docker inspect $(docker ps -aq 2>/dev/null) > "$cdir/docker-inspect.json" 2>/dev/null || true; fi
  if command -v podman >/dev/null 2>&1; then podman ps -a --format json > "$cdir/podman-ps.json" 2>/dev/null || true; podman inspect --all > "$cdir/podman-inspect.json" 2>/dev/null || true; fi
  find /etc/containers "$HOME/.config/containers" -maxdepth 3 -type f 2>/dev/null | while IFS= read -r f; do
    rel="${f#/}"; mkdir -p "$cdir/$(dirname "$rel")"; cp "$f" "$cdir/$rel" 2>/dev/null || true
  done
fi

# --- Phase 4: build targets ---
BACKUP_TARGETS=()
if ! build_targets "$INCLUDE_FILE" BACKUP_TARGETS; then
  error "Include file missing or empty: $INCLUDE_FILE"; write_marker last-health "0" "$(date +%s)"; exit 1
fi
ART_TARGETS=()
build_artifact_targets "$INCLUDE_FILE_ARTIFACTS" ART_TARGETS 2>/dev/null || true
for p in ${ART_TARGETS[@]+"${ART_TARGETS[@]}"}; do BACKUP_TARGETS+=("$p"); done
[ -d "$DUMPS_DIR" ] && [ "$(ls -A "$DUMPS_DIR" 2>/dev/null)" ] && BACKUP_TARGETS+=("$DUMPS_DIR")

REMOTE_TARGETS=()
if build_targets "$INCLUDE_FILE_REMOTE" REMOTE_TARGETS 2>/dev/null; then :; else REMOTE_TARGETS=(); fi
[ -d "/backups/databases" ] && REMOTE_TARGETS+=("/backups/databases")
[ -d "$DUMPS_DIR" ] && [ "$(ls -A "$DUMPS_DIR" 2>/dev/null)" ] && REMOTE_TARGETS+=("$DUMPS_DIR")

# dedup
dedup_arr() {
  # shellcheck disable=SC2178
  local -n a="$1"; local seen=$'\n' x; local -a o=()
  for x in ${a[@]+"${a[@]}"}; do
    case "$seen" in *$'\n'"$x"$'\n'*) continue ;; esac
    seen="${seen}${x}"$'\n'; o+=("$x")
  done
  a=(${o[@]+"${o[@]}"})
}
dedup_arr BACKUP_TARGETS; dedup_arr REMOTE_TARGETS

# refuse repo in final lists
for p in "${BACKUP_TARGETS[@]}" "${REMOTE_TARGETS[@]}"; do refuse_repo_path "$p" || { write_marker last-health "0" "$(date +%s)"; exit 1; }; done

RESTIC_ARGS=(backup)
# shellcheck disable=SC2206
RESTIC_ARGS+=( $(restic_backup_args "$RESTIC_REPOSITORY_LOCAL") )
# restic_backup_args already includes -r; we need repo-specific runs. Override -r per call.
if [ -f "$EXCLUDE_FILE" ] && [ -s "$EXCLUDE_FILE" ]; then RESTIC_ARGS+=(--exclude-file "$EXCLUDE_FILE"); fi

ensure_repo_initialized() {
  local repo="$1" label="$2"
  timeout 120 restic -r "$repo" cat config >/dev/null 2>&1 && return 0
  info "[$label] Initializing repository at $repo"
  restic -r "$repo" init >/dev/null 2>&1 || timeout 120 restic -r "$repo" cat config >/dev/null 2>&1
}

run_repo_backup() {
  local repo="$1" label="$2"; shift 2
  local -a targets=("$@")
  local host="${RESTIC_HOST:-$(hostname -s)}" tag="${RESTIC_TAG:-spectre-suite}"
  local -a args=(-r "$repo" backup --tag "$tag" --tag workstation --host "$host")
  [ -f "$EXCLUDE_FILE" ] && [ -s "$EXCLUDE_FILE" ] && args+=(--exclude-file "$EXCLUDE_FILE")
  local exit_code=1 attempt
  for attempt in 1 2 3; do
    info "[$label] backup attempt $attempt/3 -> $repo (${#targets[@]} paths)"
    if restic "${args[@]}" "${targets[@]}"; then exit_code=0; break; fi
    exit_code=$?
    [ "$attempt" -lt 3 ] && sleep $((attempt * 30))
  done
  return $exit_code
}

get_latest_snapshot_id() {
  local repo="$1"
  RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE" restic -r "$repo" snapshots --latest 1 --json --tag "${RESTIC_TAG:-spectre-suite}" --host "${RESTIC_HOST:-$(hostname -s)}" 2>/dev/null \
    | jq -r '.[0].short_id // .[0].id // "unknown"' 2>/dev/null || echo "unknown"
}

# --- Phase 5: local backup ---
if [ -n "$RESTIC_REPOSITORY_LOCAL" ]; then
  ensure_repo_initialized "$RESTIC_REPOSITORY_LOCAL" "local" || true
  if run_repo_backup "$RESTIC_REPOSITORY_LOCAL" "local" "${BACKUP_TARGETS[@]}"; then
    LOCAL_OK=1
    sid=$(get_latest_snapshot_id "$RESTIC_REPOSITORY_LOCAL")
    write_marker last-success "$(date +%s) $sid"
    info "Local backup OK (snapshot $sid)"
  else
    error "Local backup failed"
    write_marker last-health "0" "$(date +%s)"
    notify "Backup Failed" "Local restic backup failed" "critical"
    exit 1
  fi
else
  error "RESTIC_REPOSITORY_LOCAL is required"; write_marker last-health "0" "$(date +%s)"; exit 1
fi

# --- Phase 6: offsite backup (degraded, never blocks local success) ---
if [ "$RESTIC_SKIP_OFFSITE" = "1" ]; then
  info "Offsite backup skipped (RESTIC_SKIP_OFFSITE=1)"
else
  OFFSITE_ATTEMPTED=1
  if [ "${#REMOTE_TARGETS[@]}" -eq 0 ]; then
    warn "No offsite targets; skipping offsite leg"
    OVERALL_DEGRADED=1
  elif ensure_repo_initialized "$RESTIC_REPOSITORY" "offsite" && run_repo_backup "$RESTIC_REPOSITORY" "offsite" "${REMOTE_TARGETS[@]}"; then
    OFFSITE_OK=1
    sid=$(get_latest_snapshot_id "$RESTIC_REPOSITORY")
    write_marker last-offsite-success "$(date +%s) $sid"
    info "Offsite backup OK (snapshot $sid)"
  else
    warn "Offsite backup failed; local backup remains valid (degraded)"
    OVERALL_DEGRADED=1
    notify "Backup Degraded" "Local OK; offsite backup failed" "normal"
  fi
fi

# --- Phase 7: tag-scoped retention ---
if [ "$NO_PRUNE" != "true" ]; then
  # shellcheck disable=SC2046
  FORGET=(forget $(restic_forget_args) --prune)
  if [ "$LOCAL_OK" = "1" ]; then restic -r "$RESTIC_REPOSITORY_LOCAL" "${FORGET[@]}" || warn "Local forget/prune reported issues"; fi
  if [ "$OFFSITE_OK" = "1" ]; then restic -r "$RESTIC_REPOSITORY" "${FORGET[@]}" || warn "Offsite forget/prune reported issues"; fi
else
  info "Prune skipped (--no-prune)"
fi

# --- Phase 8: health marker / exit ---
if [ "$OVERALL_DEGRADED" = "1" ]; then
  write_marker last-health "0" "$(date +%s)"
  info "Backup complete (degraded)"
  exit 2
fi
write_marker last-health "1" "$(date +%s)"
info "Backup complete (ok)"
exit 0
