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

# publish_down <reason> <detail> [identified_as]
#
# Writes the "agent not usable" state and stops. Finding counts are deliberately
# absent here rather than zero: a zero is indistinguishable from "the agent
# scanned and found nothing", which is the exact confusion this file exists to
# avoid.
#
# identified_as is emitted only when the identity check actually reached a
# service that is not the agent. Emitting it for every other failure would make
# SecurityAgentWrongServiceOnPort fire on a plain outage, which is the opposite
# of what that separate alert is for.
publish_down() {
    {
        echo "# HELP spectre_agent_up 1 if the Spectre agent answered the security summary request with a valid API key, 0 otherwise"
        echo "# TYPE spectre_agent_up gauge"
        echo "spectre_agent_up 0"
        echo "# HELP spectre_agent_up_reason 1 with a label describing why the agent could not be reached"
        echo "# TYPE spectre_agent_up_reason gauge"
        echo "spectre_agent_up_reason{reason=\"$1\"} 1"
        if [ -n "${3:-}" ]; then
            echo "# HELP spectre_agent_identifies_as 1 with a label naming what is actually listening on the configured port, when it is not the Spectre agent"
            echo "# TYPE spectre_agent_identifies_as gauge"
            echo "spectre_agent_identifies_as{identified_as=\"$3\"} 1"
        fi
    } > "$OUTPUT_DIR/security_metrics.prom"
    echo "spectre agent not usable ($1: $2); published agent_up 0 and no finding counts" >&2
    exit 0
}

# --- Identity check ------------------------------------------------------
#
# Before trusting anything on this port, confirm it is actually the Spectre
# agent. This is not defensive paranoia: when AGENT_URL pointed at a port held
# by an unrelated service, every scrape got that service's 404, which read as
# "the agent has no /api/security/summary" and sent the debugging at the agent
# instead of at the port. A port collision has to be distinguishable from the
# agent being down, in the metric, not just in a human reading the log.
#
# The check is ADVISORY in one direction only. /openapi.json is served by
# FastAPI ahead of the API-key guard, so a 200 naming a different application is
# conclusive and enough to refuse. But its absence proves nothing: an older
# agent, a reverse proxy that strips it, or a stub all legitimately answer 404
# while /api/security/summary works perfectly. So "no openapi.json" leaves
# identity UNKNOWN and the summary request below proceeds -- its own response
# shape is the fallback identity test. Treating a missing openapi.json as a
# collision would fail closed on a healthy agent.
#
#   confirmed -> 200 openapi.json whose info.title is "Spectre API"
#   refused   -> something conclusively else answered
#   unknown   -> not answerable; the summary response decides
IDENTITY="unknown"

openapi=$(curl -sS --max-time "$TIMEOUT" -w $'\n%{http_code}' "$AGENT_URL/openapi.json" 2>/dev/null || true)
if [ -n "$openapi" ]; then
    openapi_status=$(printf '%s' "$openapi" | tail -n1)
    openapi_body=$(printf '%s' "$openapi" | sed '$d')

    # 000 means the TCP connection never completed: no service to identify, so
    # this is an outage rather than a collision. Fall through to the summary
    # request, which reports the precise transport reason.
    if [ "$openapi_status" != "000" ]; then
        # A 3xx is conclusive in the same way a 200 is: a browser-facing UI
        # cannot be the API. So are a 200 whose title is wrong, and a 401/403
        # (a gated service is not this fail-closed local API).
        case "$openapi_status" in
            3*)
                identified_as="HTTP $openapi_status redirect (a web UI, not the agent)"
                publish_down "wrong_service_on_port" "$AGENT_URL answered $identified_as" "$identified_as"
                ;;
            401|403)
                identified_as="HTTP $openapi_status on /openapi.json (a gated service, not the agent)"
                publish_down "wrong_service_on_port" "$AGENT_URL answered $identified_as" "$identified_as"
                ;;
            200)
                # Only a document that actually identifies itself is evidence.
                # A 200 with no info.title is what a proxy, a stripped path, or
                # a stub that answers every route produces -- it names nothing,
                # so it cannot implicate or exonerate the agent. Concluding
                # "wrong service" from it would refuse a perfectly healthy one.
                #
                # Verdict and title come back on separate lines rather than
                # tab-joined: the title is attacker-influenced text (it comes
                # from whatever happens to hold the port) and may contain any
                # character, so it must not be recovered by delimiter surgery.
                verdict_and_title=$(printf '%s' "$openapi_body" | python3 -c '
import json, sys
try:
    doc = json.load(sys.stdin)
except Exception:
    print("UNKNOWN"); raise SystemExit
if not isinstance(doc, dict):
    print("UNKNOWN"); raise SystemExit
title = (doc.get("info") or {}).get("title")
if not title:
    # Names nothing, so it proves nothing either way.
    print("UNKNOWN"); raise SystemExit
# Newlines would forge extra exposition lines, so they cannot survive into a
# label value at all.
if "\n" in title or "\r" in title:
    print("MULTILINE"); raise SystemExit
print("CONFIRMED" if title == "Spectre API" else "OTHER")
if title != "Spectre API":
    print(title)
' 2>/dev/null)

                identity_verdict=$(printf '%s' "$verdict_and_title" | head -1)
                case "$identity_verdict" in
                    CONFIRMED)
                        IDENTITY="confirmed"
                        ;;
                    OTHER)
                        identified_as=$(printf '%s' "$verdict_and_title" | sed -n '2p')
                        # Escape for the exposition format: an unescaped quote or
                        # backslash from an untrusted service would otherwise
                        # corrupt the .prom file and take the scrape with it.
                        identified_as=$(printf '%s' "$identified_as" |
                            sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
                        publish_down "wrong_service_on_port" \
                            "$AGENT_URL is serving \"$identified_as\", not the Spectre agent" \
                            "$identified_as"
                        ;;
                    *)
                        : # UNKNOWN or MULTILINE -- fall through to the summary
                          # request, whose response shape is the real test
                        ;;
                esac
                ;;
            *)
                # 404/5xx on openapi.json proves nothing either way. Stay unknown.
                ;;
        esac
    fi
fi

# --- Summary request -----------------------------------------------------
#
# -f is deliberately dropped: it collapses every 4xx/5xx into curl exit 22,
# which cannot distinguish a rejected key (401, fix the key) from a missing
# route (404, wrong port or wrong service) from a broken agent (5xx).
status=$(curl -sS --max-time "$TIMEOUT" \
    -o "$OUTPUT_DIR/.security_summary.json" \
    -w '%{http_code}' \
    -H "X-API-Key: $api_key" \
    -H 'Accept: application/json' \
    "$AGENT_URL/api/security/summary" 2>/dev/null)
curl_status=$?

if [ "$curl_status" -ne 0 ]; then
    reason="transport_error"
    case "$curl_status" in
        28) reason="timed_out" ;;
        7)  reason="connection_refused" ;;
    esac
    rm -f "$OUTPUT_DIR/.security_summary.json"
    publish_down "$reason" "curl exit $curl_status contacting $AGENT_URL"
fi

case "$status" in
    200) ;;
    401|403)
        rm -f "$OUTPUT_DIR/.security_summary.json"
        publish_down "api_key_rejected" \
            "HTTP $status from $AGENT_URL -- the key in $API_KEY_FILE is wrong or revoked, not a port problem"
        ;;
    404)
        rm -f "$OUTPUT_DIR/.security_summary.json"
        # The two cases need opposite remedies, so they must not share a reason.
        if [ "$IDENTITY" = "confirmed" ]; then
            publish_down "endpoint_not_found" \
                "HTTP 404 from $AGENT_URL -- identity confirmed as Spectre API, so this agent predates this exporter's expected route"
        else
            publish_down "wrong_service_on_port" \
                "HTTP 404 from $AGENT_URL and identity could not be confirmed (no openapi.json on this port) -- almost certainly the wrong tenant on this port" \
                "service returning 404 with no OpenAPI document"
        fi
        ;;
    503)
        rm -f "$OUTPUT_DIR/.security_summary.json"
        publish_down "agent_serving_unauthenticated" \
            "HTTP 503 from $AGENT_URL -- SPECTRE_API_KEY is unset in the agent, so it refuses to serve"
        ;;
    *)
        rm -f "$OUTPUT_DIR/.security_summary.json"
        publish_down "http_error" "HTTP $status from $AGENT_URL"
        ;;
esac

body=$(cat "$OUTPUT_DIR/.security_summary.json")
rm -f "$OUTPUT_DIR/.security_summary.json"

if [ -z "$body" ]; then
    publish_down "empty_response" "HTTP 200 with an empty body from $AGENT_URL"
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
