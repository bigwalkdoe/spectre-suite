#!/bin/bash
# backups/restore-all — operator-only disaster-recovery orchestrator.
#
# Restores every backup artifact: PostgreSQL databases, Docker volumes, and a
# restic snapshot, optionally fetching from an off-site source first.
#
# This is NOT scheduled. The individual restore scripts restore in place: a dump
# piped into the live database, and a named volume cleared and overwritten. A
# recurring restore would replace live data with the latest backup on every fire,
# so the default here is a dry-run and mutation needs --execute --yes.
#
# Usage: spectre run backups/restore-all -- [options]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Test seam: the component scripts normally sit beside this one, but tests point
# this at stubs so no real database or volume is touched.
ACTION_DIR="${RESTORE_ACTION_DIR:-$SCRIPT_DIR}"

BACKUP_DIR="${BACKUP_DIR:-/backups/databases}"
VOLUME_BACKUP_DIR="${VOLUME_BACKUP_DIR:-/backups/docker-volumes}"
BACKUP_STATE_DIR="${BACKUP_STATE_DIR:-/backups/backup-state}"

DB_SCRIPT="$ACTION_DIR/restore-databases.sh"
VOLUME_SCRIPT="$ACTION_DIR/restore-docker-volumes.sh"
RESTIC_SCRIPT="$ACTION_DIR/restic/restore.sh"
REMOTE_SCRIPT="$ACTION_DIR/restore-from-remote.sh"

if [[ -n "${LOG_FILE:-}" ]]; then
    :
elif [[ -w /var/log ]]; then
    LOG_FILE="/var/log/restore-all.log"
else
    LOG_FILE="${TMPDIR:-/tmp}/restore-all.log"
fi
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="${TMPDIR:-/tmp}/restore-all.log"

DEFAULT_SNAPSHOT="latest"

usage() {
    cat <<'EOF'
Usage: restore-all.sh [--dry-run] [--execute --yes] [--all]
                      [--databases [--database NAME]]
                      [--volumes]
                      [--restic [--snapshot ID] [--restic-target DIR]]
                      [--remote --remote-source rsync|s3|b2
                                [--remote-type databases|docker-volumes|configurations]
                                --remote-location SERVER|BUCKET]

Default: --dry-run. It prints the restore plan and changes nothing.

  --execute             Perform the selected restores. Requires --yes.
  --yes                 Confirm the in-place restores.
  --all                 Select databases, volumes, and restic.
  --databases           Restore the latest PostgreSQL dump.
  --database NAME       Restore into NAME instead of deriving it from the archive.
  --volumes             Restore every Docker volume from its latest archive.
  --restic              Restore a restic snapshot (requires --restic-target).
  --snapshot ID         Restic snapshot id (default: latest).
  --restic-target DIR   Restore destination; required, so restic never writes
                        back over the original paths by accident.
  --remote              Fetch from off-site; requires a source and location.
                        s3/b2 restore in place. rsync downloads to /tmp only,
                        so nothing is applied -- restore again from the
                        downloaded files.
  --remote-source SRC   rsync, s3, or b2.
  --remote-type TYPE    databases, docker-volumes, or configurations.
  --remote-location LOC Remote server or bucket name.

Exit: 0 success, 1 a restore failed, 2 usage error.
EOF
}

EXECUTE=0
CONFIRM=0
DRY_FLAG=0
ALL=0
SELECT_DB=0
SELECT_VOLUMES=0
SELECT_RESTIC=0
SELECT_REMOTE=0
DATABASE=""
SNAPSHOT="$DEFAULT_SNAPSHOT"
RESTIC_TARGET=""
REMOTE_SOURCE=""
REMOTE_TYPE="databases"
REMOTE_LOCATION=""

require_value() {
    local flag="$1" value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "missing value for $flag" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_FLAG=1 ;;
        --execute) EXECUTE=1 ;;
        --yes) CONFIRM=1 ;;
        --all) ALL=1 ;;
        --databases) SELECT_DB=1 ;;
        --database)
            require_value "--database" "${2:-}"
            DATABASE="$2"; shift ;;
        --database=*)
            require_value "--database" "${1#*=}"
            DATABASE="${1#*=}" ;;
        --volumes) SELECT_VOLUMES=1 ;;
        --restic) SELECT_RESTIC=1 ;;
        --snapshot)
            require_value "--snapshot" "${2:-}"
            SNAPSHOT="$2"; shift ;;
        --snapshot=*)
            require_value "--snapshot" "${1#*=}"
            SNAPSHOT="${1#*=}" ;;
        --restic-target)
            require_value "--restic-target" "${2:-}"
            RESTIC_TARGET="$2"; shift ;;
        --restic-target=*)
            require_value "--restic-target" "${1#*=}"
            RESTIC_TARGET="${1#*=}" ;;
        --remote) SELECT_REMOTE=1 ;;
        --remote-source)
            require_value "--remote-source" "${2:-}"
            REMOTE_SOURCE="$2"; shift ;;
        --remote-source=*)
            require_value "--remote-source" "${1#*=}"
            REMOTE_SOURCE="${1#*=}" ;;
        --remote-type)
            require_value "--remote-type" "${2:-}"
            REMOTE_TYPE="$2"; shift ;;
        --remote-type=*)
            require_value "--remote-type" "${1#*=}"
            REMOTE_TYPE="${1#*=}" ;;
        --remote-location)
            require_value "--remote-location" "${2:-}"
            REMOTE_LOCATION="$2"; shift ;;
        --remote-location=*)
            require_value "--remote-location" "${1#*=}"
            REMOTE_LOCATION="${1#*=}" ;;
        -h|--help)
            usage
            exit 0 ;;
        *)
            echo "unknown argument: $1" >&2
            usage >&2
            exit 2 ;;
    esac
    shift
done

if [[ "$DRY_FLAG" -eq 1 && "$EXECUTE" -eq 1 ]]; then
    echo "--dry-run and --execute are mutually exclusive" >&2
    exit 2
fi

if [[ "$ALL" -eq 1 ]]; then
    SELECT_DB=1
    SELECT_VOLUMES=1
    SELECT_RESTIC=1
fi

if [[ "$EXECUTE" -eq 1 ]]; then
    if [[ "$CONFIRM" -ne 1 ]]; then
        echo "refusing to restore in place without --yes; re-run with --execute --yes" >&2
        exit 2
    fi
    if [[ "$SELECT_DB" -eq 0 && "$SELECT_VOLUMES" -eq 0 && "$SELECT_RESTIC" -eq 0 && "$SELECT_REMOTE" -eq 0 ]]; then
        echo "--execute needs at least one component (--all, --databases, --volumes, --restic, --remote)" >&2
        exit 2
    fi
fi

if [[ "$SELECT_RESTIC" -eq 1 && "$EXECUTE" -eq 1 && -z "$RESTIC_TARGET" ]]; then
    echo "--restic with --execute requires --restic-target DIR (no in-place restic restore)" >&2
    exit 2
fi

if [[ "$SELECT_REMOTE" -eq 1 ]]; then
    case "$REMOTE_SOURCE" in
        rsync|s3|b2) ;;
        "") echo "--remote requires --remote-source rsync|s3|b2 and --remote-location" >&2; exit 2 ;;
        *) echo "unknown --remote-source: $REMOTE_SOURCE (expected rsync, s3, or b2)" >&2; exit 2 ;;
    esac
    case "$REMOTE_TYPE" in
        databases|docker-volumes|configurations) ;;
        *) echo "unknown --remote-type: $REMOTE_TYPE" >&2; exit 2 ;;
    esac
    if [[ -z "$REMOTE_LOCATION" ]]; then
        echo "--remote requires --remote-location SERVER|BUCKET" >&2
        exit 2
    fi
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE" || true
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2 || true
}

require_script() {
    local path="$1" component="$2"
    if [[ ! -f "$path" ]]; then
        error "$component restore script not found: $path"
        return 1
    fi
    return 0
}

latest_archive() {
    local dir="$1" pattern="$2"
    find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2- || true
}

print_plan() {
    local selected=0

    echo "DRY RUN: no restores will be performed (use --execute --yes)"
    echo "Plan:"

    if [[ "$SELECT_DB" -eq 1 ]]; then
        # Deliberately does not name the archive. The component script picks its
        # own, and the two can disagree -- a plan that promises
        # `postgres_20261113.sql.gz` while the script restores a different file
        # is worse than no name at all, because it invites the operator to
        # verify the wrong artifact. Say what is being restored, not a filename.
        echo "  databases: restore the latest PostgreSQL dump from $BACKUP_DIR"
        if [[ -n "$DATABASE" ]]; then
            echo "             into database $DATABASE"
        fi
        selected=1
    fi

    if [[ "$SELECT_VOLUMES" -eq 1 ]]; then
        echo "  docker volumes: restore the latest archive per volume from $VOLUME_BACKUP_DIR"
        selected=1
    fi

    if [[ "$SELECT_RESTIC" -eq 1 ]]; then
        echo "  restic: apply snapshot $SNAPSHOT to ${RESTIC_TARGET:-<choose --restic-target>}"
        selected=1
    fi

    if [[ "$SELECT_REMOTE" -eq 1 ]]; then
        if [[ "$REMOTE_SOURCE" == "rsync" ]]; then
            echo "  remote: download $REMOTE_TYPE from rsync:$REMOTE_LOCATION (downloads only; nothing applied)"
        else
            echo "  remote: restore $REMOTE_TYPE from $REMOTE_SOURCE:$REMOTE_LOCATION"
        fi
        selected=1
    fi

    if [[ "$selected" -eq 0 ]]; then
        echo "  nothing selected; choose --all or name components"
    fi
    echo "Nothing was changed."
}

run_step() {
    local name="$1"
    shift
    log "Restoring $name..."
    set +e
    "$@"
    local status=$?
    set -e
    log "$name exit status: $status"
    return "$status"
}

write_verdict() {
    local verdict="$1" detail="${2:-}"
    mkdir -p "$BACKUP_STATE_DIR"
    if [[ -n "$detail" ]]; then
        printf '%s %s %s\n' "$verdict" "$(date +%s)" "$detail" > "$BACKUP_STATE_DIR/last-restore-health"
    else
        printf '%s %s\n' "$verdict" "$(date +%s)" > "$BACKUP_STATE_DIR/last-restore-health"
    fi
}

# A missing component script aborts before any restore runs. It must write a
# failed verdict: otherwise the marker keeps the previous run's value, and a
# restore that died before touching anything would report the stale `ok` from
# the last successful run -- reporting a failed disaster recovery as
# successful.
abort_missing() {
    local component="$1" path="$2"
    error "$component restore script not found: $path"
    write_verdict failed "missing-script $component"
    exit 1
}

# Declared before the component checks so `set -u` does not trip on the first
# `DETAIL=...` reference below. It is empty until a component fails.
DETAIL=""
if [[ "$SELECT_DB" -eq 1 ]]; then require_script "$DB_SCRIPT" databases || abort_missing databases "$DB_SCRIPT"; fi
if [[ "$SELECT_VOLUMES" -eq 1 ]]; then require_script "$VOLUME_SCRIPT" "docker volume" || abort_missing "docker volume" "$VOLUME_SCRIPT"; fi
if [[ "$SELECT_RESTIC" -eq 1 ]]; then require_script "$RESTIC_SCRIPT" restic || abort_missing restic "$RESTIC_SCRIPT"; fi
if [[ "$SELECT_REMOTE" -eq 1 ]]; then require_script "$REMOTE_SCRIPT" remote || abort_missing remote "$REMOTE_SCRIPT"; fi

if [[ "$EXECUTE" -ne 1 ]]; then
    print_plan
    exit 0
fi

DB_STATUS=0
VOLUME_STATUS=0
RESTIC_STATUS=0
REMOTE_STATUS=0

if [[ "$SELECT_DB" -eq 1 ]]; then
    if [[ -n "$DATABASE" ]]; then
        run_step "databases" bash "$DB_SCRIPT" latest "$DATABASE" || DB_STATUS=$?
    else
        run_step "databases" bash "$DB_SCRIPT" latest || DB_STATUS=$?
    fi
fi

if [[ "$SELECT_VOLUMES" -eq 1 ]]; then
    run_step "docker volumes" bash "$VOLUME_SCRIPT" latest || VOLUME_STATUS=$?
fi

if [[ "$SELECT_RESTIC" -eq 1 ]]; then
    run_step "restic snapshot $SNAPSHOT" bash "$RESTIC_SCRIPT" --snapshot "$SNAPSHOT" --target "$RESTIC_TARGET" || RESTIC_STATUS=$?
fi

if [[ "$SELECT_REMOTE" -eq 1 ]]; then
    run_step "remote $REMOTE_TYPE" bash "$REMOTE_SCRIPT" "$REMOTE_SOURCE" "$REMOTE_TYPE" "$REMOTE_LOCATION" || REMOTE_STATUS=$?
fi

echo "=========================================="
echo "Restore summary"
echo "  databases:      $([[ "$DB_STATUS" -eq 0 ]] && echo SUCCESS || echo "FAILED ($DB_STATUS)")"
echo "  docker volumes: $([[ "$VOLUME_STATUS" -eq 0 ]] && echo SUCCESS || echo "FAILED ($VOLUME_STATUS)")"
echo "  restic:         $([[ "$RESTIC_STATUS" -eq 0 ]] && echo SUCCESS || echo "FAILED ($RESTIC_STATUS)")"
if [[ "$SELECT_REMOTE" -eq 1 && "$REMOTE_SOURCE" == "rsync" && "$REMOTE_STATUS" -eq 0 ]]; then
    echo "  remote:         FETCHED ONLY (rsync downloads to /tmp; nothing applied)"
else
    echo "  remote:         $([[ "$REMOTE_STATUS" -eq 0 ]] && echo SUCCESS || echo "FAILED ($REMOTE_STATUS)")"
fi
echo "  log:            $LOG_FILE"
echo "=========================================="

if [[ "$DB_STATUS" -ne 0 ]]; then DETAIL="$DETAIL databases=$DB_STATUS"; fi
if [[ "$VOLUME_STATUS" -ne 0 ]]; then DETAIL="$DETAIL volumes=$VOLUME_STATUS"; fi
if [[ "$RESTIC_STATUS" -ne 0 ]]; then DETAIL="$DETAIL restic=$RESTIC_STATUS"; fi
if [[ "$REMOTE_STATUS" -ne 0 ]]; then DETAIL="$DETAIL remote=$REMOTE_STATUS"; fi

if [[ -n "$DETAIL" ]]; then
    write_verdict failed "${DETAIL# }"
    logger -p user.error "restore-all completed with failures:$DETAIL - check $LOG_FILE" 2>/dev/null || true
    if [[ -n "${DISPLAY:-}" ]]; then
        notify-send "Restore Failed" "Some restores failed - check $LOG_FILE" -u critical || true
    fi
    exit 1
fi

NOTE=""
if [[ "$SELECT_REMOTE" -eq 1 && "$REMOTE_SOURCE" == "rsync" ]]; then
    NOTE="remote=rsync-download-only"
fi

write_verdict ok "$NOTE"
if [[ -n "$NOTE" ]]; then
    logger -p user.warning "restore-all: rsync downloaded artifacts to /tmp only; nothing was applied" 2>/dev/null || true
    if [[ -n "${DISPLAY:-}" ]]; then
        notify-send "Restore Fetch Complete" "rsync downloaded the artifacts; nothing was applied" -u normal || true
    fi
else
    logger -p user.info "restore-all completed successfully" 2>/dev/null || true
    if [[ -n "${DISPLAY:-}" ]]; then
        notify-send "Restore Complete" "All selected restores completed successfully" || true
    fi
fi
exit 0
