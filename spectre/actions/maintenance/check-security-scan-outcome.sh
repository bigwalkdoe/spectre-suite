#!/usr/bin/env bash
# Recheck security-scan timer outcome (A2/A3). Read-only by default.
# Usage: ./check-security-scan-outcome.sh [--since "2026-11-14 03:55"] [--until "2026-11-14 04:15"] [--append-runbook <path>]
set -euo pipefail
SINCE="2026-11-14 03:55"
UNTIL="2026-11-14 04:15"
APPEND=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:?}"; shift 2 ;;
    --until) UNTIL="${2:?}"; shift 2 ;;
    --append-runbook) APPEND="${2:?}"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--since ...] [--until ...] [--append-runbook <path>]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Capture all output so it can be printed to stdout and, when --append-runbook
# is given, appended to the runbook file with a timestamped header.
CAPTURE="$(mktemp)"
trap 'rm -f "$CAPTURE"' EXIT

{
  echo "== security-scan timer/service =="
  systemctl list-timers --all --no-pager 2>&1 | grep -E 'security-scan|NEXT' || true
  echo; systemctl status security-scan.service --no-pager -l 2>&1 || true
  echo "== journal $SINCE .. $UNTIL =="
  journalctl -u security-scan.service --since "$SINCE" --until "$UNTIL" --no-pager 2>&1 || true
  echo "== actions verify =="
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd)}"
  if [ ! -d "$ROOT/spectre/dispatch" ]; then
    ROOT="$SCRIPT_DIR/../../.."
  fi
  (cd "$ROOT" && python3 -m spectre.cli.main actions verify) 2>&1 | tail -12 || true
} > "$CAPTURE"

cat "$CAPTURE"

if [ -n "$APPEND" ]; then
  {
    echo
    echo "## security-scan outcome $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    cat "$CAPTURE"
  } >> "$APPEND"
fi
