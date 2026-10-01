#!/bin/bash
# Security Metrics Exporter
#
# Polls the Spectre agent's authenticated summary endpoint and publishes what it
# actually reports to Prometheus's textfile collector.
#
# The metrics this replaces were fabricated. The old exporter emitted
# security_last_scan_timestamp set to the current time on every run, which
# asserted that a security scan had just completed when none had, alongside
# hardcoded zero counts that were indistinguishable from real readings in a
# graph. Every value written here comes from a response body or from the failure
# to obtain one.
#
# Two rules this file follows to keep that from recurring:
#
#   1. If the agent cannot be reached, `spectre_agent_up` goes to 0 and the
#      finding counts are NOT emitted at all. Emitting zeros would be
#      indistinguishable from "the agent scanned and found nothing", which is the
#      exact confusion this file exists to remove.
#   2. `security_last_scan_timestamp` is the agent's recorded scan time, never the
#      moment this script polled.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${1:-$SCRIPT_DIR/business-metrics}"

# 8106, not the agent's shipped 8000. 8000 is held by arcaden-labs-api-edge-1,
# and that stack occupies 8001-8110 as well, so the agent runs on 8106 via
# spectre-api.service. Pointing this at 8000 produced a 404 from a completely
# unrelated service on every scrape, which read as "the agent has no such
# endpoint" rather than "you are talking to the wrong application".
AGENT_URL="${SPECTRE_AGENT_URL:-http://127.0.0.1:8106}"
API_KEY_FILE="${SPECTRE_API_KEY_FILE:-$SCRIPT_DIR/../.spectre-api-key}"
TIMEOUT="${SPECTRE_TIMEOUT:-10}"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: output directory does not exist: $OUTPUT_DIR" >&2
    exit 1
fi
mkdir -p "$OUTPUT_DIR"

if [ ! -r "$API_KEY_FILE" ]; then
    echo "ERROR: cannot read the agent API key at $API_KEY_FILE." >&2
    echo "  The agent's API is fail-closed, so the key is required. Create it with" >&2
    echo "  mode 0600, or set SPECTRE_API_KEY_FILE." >&2
    # Still publish agent_up=0 so the absence is visible rather than silent.
    cat > "$OUTPUT_DIR/security_metrics.prom" << EOF
# HELP spectre_agent_up 1 if the Spectre agent answered the security summary request with a valid API key, 0 otherwise
# TYPE spectre_agent_up gauge
spectre_agent_up 0
EOF
    exit 1
fi

api_key=$(head -c 4096 "$API_KEY_FILE" | tr -d '\n')

body=$(curl -fsS --max-time "$TIMEOUT" \
    -H "X-API-Key: $api_key" \
    -H 'Accept: application/json' \
    "$AGENT_URL/api/security/summary" 2>/dev/null)
curl_status=$?

if [ "$curl_status" -ne 0 ] || [ -z "$body" ]; then
    reason="request failed"
    [ "$curl_status" -eq 0 ] && reason="empty response"
    case "$curl_status" in
        22) reason="HTTP error (unauthorised or not found)" ;;
        28) reason="timed out after ${TIMEOUT}s" ;;
        7)  reason="connection refused" ;;
    esac
    cat > "$OUTPUT_DIR/security_metrics.prom" << EOF
# HELP spectre_agent_up 1 if the Spectre agent answered the security summary request with a valid API key, 0 otherwise
# TYPE spectre_agent_up gauge
spectre_agent_up 0
# HELP spectre_agent_up_reason 1 with a label describing why the agent could not be reached
# TYPE spectre_agent_up_reason gauge
spectre_agent_up_reason{reason="$reason"} 1
EOF
    echo "spectre agent unreachable ($reason); published agent_up 0 and no finding counts" >&2
    exit 0
fi

# Parse in python rather than with grep so a malformed or unexpected body cannot
# silently produce zeros. Anything unparseable is an error, not "no findings".
if ! parsed=$(printf '%s' "$body" | python3 -c '
import json, sys

try:
    data = json.load(sys.stdin)
except Exception as exc:
    print("PARSE_ERROR: %s" % exc, file=sys.stderr)
    raise SystemExit(2)

if not isinstance(data, dict):
    print("PARSE_ERROR: expected an object", file=sys.stderr)
    raise SystemExit(2)

total = data.get("unresolved_total")
by_sev = data.get("unresolved_by_severity")
scanned = data.get("has_ever_scanned")
scan_ts = data.get("last_scan_timestamp")

if not isinstance(total, int) or not isinstance(by_sev, dict) or not isinstance(scanned, bool):
    print("PARSE_ERROR: unexpected field types: %r" % data, file=sys.stderr)
    raise SystemExit(2)

# Escape a label value for the exposition format.
def esc(value):
    return str(value).replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", " ")

print("TOTAL\t%d" % total)
print("SCANNED\t%d" % (1 if scanned else 0))
# A missing timestamp is reported as 0 and never as "now". A consumer can tell
# the difference between "never scanned" and "scanned at epoch 0" via
# spectre_security_ever_scanned.
print("SCAN_TS\t%s" % (scan_ts if isinstance(scan_ts, str) else ""))
for severity in ("critical", "high", "medium", "low"):
    print("SEV\t%s\t%d" % (severity, int(by_sev.get(severity, 0))))
oldest = data.get("oldest_unresolved_timestamp")
print("OLDEST\t%s" % (oldest if isinstance(oldest, str) else ""))
'); then
    cat > "$OUTPUT_DIR/security_metrics.prom" << EOF
# HELP spectre_agent_up 1 if the Spectre agent answered the security summary request with a valid API key, 0 otherwise
# TYPE spectre_agent_up gauge
spectre_agent_up 0
EOF
    echo "ERROR: could not parse the agent's security summary; refusing to publish zeros" >&2
    exit 1
fi

# ISO-8601 -> epoch seconds. Empty stays 0, which is honest: no scan has been
# recorded, and spectre_security_ever_scanned says so explicitly.
to_epoch() {
    [ -n "$1" ] || { echo 0; return; }
    python3 -c '
import sys
from datetime import datetime
raw = sys.argv[1].strip()
if not raw:
    print(0); raise SystemExit
try:
    stamp = datetime.fromisoformat(raw)
except ValueError:
    print(0); raise SystemExit
if stamp.tzinfo is None:
    # The agent returns aware UTC, but a naive stamp would be ambiguous rather
    # than merely imprecise, so it is rejected instead of assumed.
    print(0); raise SystemExit
print(int(stamp.timestamp()))
' "$1"
}

total=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="TOTAL"{print $2}')
scanned=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="SCANNED"{print $2}')
scan_ts_raw=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="SCAN_TS"{print $2}')
oldest_raw=$(printf '%s\n' "$parsed" | awk -F'\t' '$1=="OLDEST"{print $2}')
scan_ts=$(to_epoch "$scan_ts_raw")
oldest_ts=$(to_epoch "$oldest_raw")

{
    echo "# HELP spectre_agent_up 1 if the Spectre agent answered the security summary request with a valid API key, 0 otherwise"
    echo "# TYPE spectre_agent_up gauge"
    echo "spectre_agent_up 1"
    echo "# HELP spectre_security_ever_scanned 1 if the security agent has recorded at least one scan, 0 if it never has"
    echo "# TYPE spectre_security_ever_scanned gauge"
    echo "spectre_security_ever_scanned $scanned"
    echo "# HELP security_last_scan_timestamp Unix time of the last scan the agent recorded, 0 if it never has. This is the agent's scan time, not the time this exporter polled"
    echo "# TYPE security_last_scan_timestamp gauge"
    echo "security_last_scan_timestamp $scan_ts"
    echo "# HELP security_findings_unresolved Number of unresolved security findings the agent has recorded"
    echo "# TYPE security_findings_unresolved gauge"
    echo "security_findings_unresolved $total"
    echo "# HELP security_findings_unresolved_by_severity Unresolved security findings the agent has recorded, by severity"
    echo "# TYPE security_findings_unresolved_by_severity gauge"
    for severity in critical high medium low; do
        count=$(printf '%s\n' "$parsed" | awk -F'\t' -v s="$severity" '$1=="SEV" && $2==s {print $3}')
        echo "security_findings_unresolved_by_severity{severity=\"$severity\"} ${count:-0}"
    done
    if [ "$oldest_ts" -gt 0 ] 2>/dev/null; then
        echo "# HELP security_oldest_unresolved_timestamp Unix time of the oldest unresolved finding, 0 if there are none"
        echo "# TYPE security_oldest_unresolved_timestamp gauge"
        echo "security_oldest_unresolved_timestamp $oldest_ts"
    fi
} > "$OUTPUT_DIR/security_metrics.prom"

echo "security metrics exported: $total unresolved finding(s), last scan $([ "$scanned" -eq 1 ] && date -d "@$scan_ts" '+%Y-%m-%d %H:%M:%S' || echo never)"
