#!/bin/bash
# Adopted restic engine library for spectre-suite.
# Source of behavior: ~//dev/github/spectre-backup/lib/spectre-backup-common.sh
# Suite adaptations: config/state under spectre-suite/backups, tag-scoped args, markers,
# build_targets/build_artifact_targets with dedup and repository-path refusal.

# --- Logging (quiet-safe) ---
if [ -z "${RED+x}" ]; then
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
  fi
fi
info()  { [ "${QUIET:-false}" = true ] || echo -e "$(date '+%H:%M:%S') ${GREEN}[INFO]${NC}  $*" >&2; }
warn()  { [ "${QUIET:-false}" = true ] || echo -e "$(date '+%H:%M:%S') ${YELLOW}[WARN]${NC}  $*" >&2; }
error() { echo -e "$(date '+%H:%M:%S') ${RED}[ERROR]${NC} $*" >&2; }
header(){ [ "${QUIET:-false}" = true ] || echo -e "\n${BLUE}${BOLD}=== $* ===${NC}\n" >&2; }

# --- Paths (suite-owned) ---
resolve_restic_dirs() {
  CONFIG_DIR="${CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/spectre-suite/backups}"
  STATE_DIR="${STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre-suite/backups}"
  BIN_DIR="${BIN_DIR:-${XDG_DATA_HOME:-$HOME/.local}/bin}"
  LOG_DIR="${LOG_DIR:-$STATE_DIR}"
  MARKER_DIR="${MARKER_DIR:-$STATE_DIR}"
  DUMPS_DIR="${DUMPS_DIR:-$STATE_DIR/dumps/$(date +%Y%m%d-%H%M%S)}"
  mkdir -p "$CONFIG_DIR" "$STATE_DIR" "$BIN_DIR" "$LOG_DIR" "$MARKER_DIR" 2>/dev/null || true
}

load_restic_env() {
  local env_file="${RESTIC_CONFIG:-$HOME/.secrets/spectre-suite-backups.env}"
  if [ -f "$env_file" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
    return 0
  fi
  # Legacy/fallback for tests or migration
  if [ -f "${CONFIG_DIR:-}/env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${CONFIG_DIR}/env"
    set +a
    return 0
  fi
  return 1
}

refuse_repo_path() {
  local path="$1" repo="${RESTIC_REPOSITORY_LOCAL:-}"
  [ -z "$repo" ] && return 0
  local rp rr
  rp="$(realpath -m "$path" 2>/dev/null || printf '%s' "$path")"
  rr="$(realpath -m "$repo" 2>/dev/null || printf '%s' "$repo")"
  case "$rp/" in
    "$rr"|"$rr"/*) error "Refusing to back up repository path: $path (under $repo)"; return 1 ;;
  esac
  return 0
}

# build_targets <include_file> <out_array_name>
build_targets() {
  local file="$1"
  # shellcheck disable=SC2178
  local -n out_ref="$2"
  out_ref=()
  [ -f "$file" ] && [ -s "$file" ] || return 1
  local line resolved seen=$'\n'
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line/#\~/$HOME}"
    line="${line//\$HOME/$HOME}"
    # trim leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line%/}"
    [ -z "$line" ] && continue
    refuse_repo_path "$line" || return 1
    resolved="$(realpath -m "$line" 2>/dev/null || printf '%s' "$line")"
    if [ -e "$resolved" ] || [ -e "$line" ]; then
      case "$seen" in *$'\n'"$resolved"$'\n'*) continue ;; esac
      seen="${seen}${resolved}"$'\n'
      out_ref+=("$resolved")
    else
      warn "Include path not found, skipping: $line"
    fi
  done < "$file"
  [ "${#out_ref[@]}" -gt 0 ]
}

# build_artifact_targets <glob_file> <out_array_name>
build_artifact_targets() {
  local file="$1"
  # shellcheck disable=SC2178
  local -n out_ref="$2"
  out_ref=()
  [ -f "$file" ] || return 1
  local line seen=$'\n' match resolved
  local -a matches
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line/#\~/$HOME}"
    line="${line//\$HOME/$HOME}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue
    refuse_repo_path "$line" || return 1
    shopt -s nullglob
    # shellcheck disable=SC2206
    matches=( $line )
    shopt -u nullglob
    for match in "${matches[@]:-}"; do
      [ -e "$match" ] || continue
      refuse_repo_path "$match" || return 1
      resolved="$(realpath -m "$match" 2>/dev/null || printf '%s' "$match")"
      case "$seen" in *$'\n'"$resolved"$'\n'*) continue ;; esac
      seen="${seen}${resolved}"$'\n'
      out_ref+=("$resolved")
    done
  done < "$file"
  [ "${#out_ref[@]}" -gt 0 ]
}

restic_backup_args() {
  local repo="${1:-${RESTIC_REPOSITORY_LOCAL:-}}"
  local host="${RESTIC_HOST:-$(hostname -s 2>/dev/null || hostname)}"
  printf '%s' "-r $(printf %q "$repo") --tag ${RESTIC_TAG:-spectre-suite} --tag workstation --host $(printf %q "$host")"
}

restic_forget_args() {
  printf '%s' "--tag ${RESTIC_TAG:-spectre-suite} --keep-hourly 24 --keep-daily 30 --keep-weekly 12 --keep-monthly 12 --keep-last 1"
}

write_marker() {
  local name="$1"; shift
  local dir="${MARKER_DIR:-${STATE_DIR:-$HOME/.local/state/spectre-suite/backups}}"
  mkdir -p "$dir"
  local tmp="$dir/.$name.tmp.$$"
  printf '%s\n' "$*" > "$tmp" && mv -f "$tmp" "$dir/$name"
}

read_marker_epoch() {
  local file="$1" v=""
  if [ -r "$file" ]; then v="$(awk '{print $1}' "$file" 2>/dev/null || true)"; fi
  case "$v" in ''|*[!0-9]*) printf '0\n' ;; *) printf '%s\n' "$v" ;; esac
}

read_marker_field() {
  local file="$1" n="${2:-1}" v=""
  if [ -r "$file" ]; then v="$(awk -v n="$n" '{print $n}' "$file" 2>/dev/null || true)"; fi
  printf '%s' "$v"
}
