#!/bin/bash
# Security Metrics Exporter Tests
#
# The metrics this exporter replaces were fabricated: hardcoded zeros plus a
# security_last_scan_timestamp set to the current time on every run, which
# reported a scan that never happened as having just completed. Nothing in the
# suite asserted where these numbers came from, so that shipped.
#
# Each case stands up a stub agent that returns one specific response and asserts
# on what the exporter publishes. The cases that matter most are the failures:
# an unreachable or lying agent must never turn into a count of zero that reads
# as "scanned, found nothing".

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EXPORTER="$PROJECT_ROOT/prometheus/security-metrics-exporter.sh"

echo "Running security metrics exporter tests..."

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

if [ ! -x "$EXPORTER" ]; then
    echo "❌ security-metrics-exporter.sh is missing or not executable"
    exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/security-exporter-test.XXXXXX")
KEY_FILE="$WORK/key"
OUT="$WORK/out"
mkdir -p "$OUT"
printf 'test-key' > "$KEY_FILE"
chmod 600 "$KEY_FILE"

STUB_PID_FILE="$WORK/stub.pid"
STUB_SCRIPT="$WORK/stub.py"

stop_stub() {
    if [ -f "$STUB_PID_FILE" ]; then
        kill "$(cat "$STUB_PID_FILE")" 2>/dev/null
        rm -f "$STUB_PID_FILE"
    fi
    sleep 0.4
}

cleanup() {
    stop_stub
    rm -rf "$WORK"
}
trap cleanup EXIT

# start_stub <mode> -- modes: good, never_scanned, naive_ts, garbage, empty,
#                           unauthorized, other_service, web_ui
start_stub() {
    local mode="$1" port
    port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')

    cat > "$STUB_SCRIPT" <<PYEOF
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

MODE = "$mode"

GOOD = {
    "unresolved_total": 3,
    "unresolved_by_severity": {"critical": 1, "high": 2},
    "oldest_unresolved_timestamp": "2026-09-24T10:00:00+00:00",
    "last_scan_timestamp": "2026-09-30T22:00:00+00:00",
    "has_ever_scanned": True,
}
NEVER = {
    "unresolved_total": 0,
    "unresolved_by_severity": {},
    "oldest_unresolved_timestamp": None,
    "last_scan_timestamp": None,
    "has_ever_scanned": False,
}
NAIVE = dict(GOOD, last_scan_timestamp="2026-09-30T22:00:00")

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if MODE == "unauthorized":
            self.send_response(401); self.end_headers(); return
        if MODE == "other_service":
            # The original failure: a different FastAPI app holds the port. It
            # serves a valid OpenAPI document under its own name, so it is only
            # distinguishable from the agent by what it says it is.
            if self.path == "/openapi.json":
                body = json.dumps({
                    "openapi": "3.1.0",
                    "info": {"title": "arcaden-labs-api-edge", "version": "1.0.0"},
                    "paths": {},
                }).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            self.send_response(404); self.end_headers(); return
        if MODE == "web_ui":
            # A browser-facing app squatting on the port: redirect, no JSON.
            self.send_response(302)
            self.send_header("Location", "/login")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if MODE == "garbage":
            body = b"this is not json"
        elif MODE == "empty":
            body = b""
        elif MODE == "naive_ts":
            body = json.dumps(NAIVE).encode()
        elif MODE == "never_scanned":
            body = json.dumps(NEVER).encode()
        else:
            body = json.dumps(GOOD).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a): pass

HTTPServer(("127.0.0.1", $port), H).serve_forever()
PYEOF

    /usr/bin/python3 "$STUB_SCRIPT" >/dev/null 2>&1 &
    echo $! > "$STUB_PID_FILE"
    for _ in $(seq 1 40); do
        if curl -sf --max-time 1 "http://127.0.0.1:$port/api/security/summary" >/dev/null 2>&1; then
            echo "$port"; return 0
        fi
        if curl -s --max-time 1 -o /dev/null "http://127.0.0.1:$port/api/security/summary" 2>/dev/null; then
            echo "$port"; return 0
        fi
        sleep 0.25
    done
    echo "0"
    return 1
}

run_exporter() {
    SPECTRE_AGENT_URL="http://127.0.0.1:$1" \
    SPECTRE_API_KEY_FILE="$KEY_FILE" \
    SPECTRE_TIMEOUT=5 \
        "$EXPORTER" "$OUT" >/dev/null 2>&1
}

metric() { grep "^$1 " "$OUT/security_metrics.prom" 2>/dev/null | awk '{print $2}'; }
has_metric() { grep -q "^$1" "$OUT/security_metrics.prom" 2>/dev/null; }
# reason_value <label-name> -- the value inside reason="..." of a labelled series.
# `metric` cannot be reused here: a labelled series is
#   spectre_agent_up_reason{reason="wrong_service_on_port"} 1
# so field 2 is the whole {..} block, not the value.
reason_value() {
    grep "^$1{" "$OUT/security_metrics.prom" 2>/dev/null |
        sed -n 's/.*="\([^"]*\)".*/\1/p' | head -1
}

# ---------------------------------------------------------------------------
# 1. A healthy agent: values must come from the response, not from constants.
# ---------------------------------------------------------------------------
port=$(start_stub good)
if [ "$port" = "0" ]; then
    fail "stub agent did not start"
else
    run_exporter "$port"
    ok_up=$(metric spectre_agent_up)
    ok_total=$(metric security_findings_unresolved)
    ok_crit=$(grep 'severity="critical"' "$OUT/security_metrics.prom" | awk '{print $2}')
    ok_ts=$(metric security_last_scan_timestamp)
    want_ts=$(python3 -c "from datetime import datetime; print(int(datetime.fromisoformat('2026-09-30T22:00:00+00:00').timestamp()))")
    if [ "$ok_up" = "1" ] && [ "$ok_total" = "3" ] && [ "$ok_crit" = "1" ] && [ "$ok_ts" = "$want_ts" ]; then
        pass "a healthy agent publishes its reported findings"
    else
        fail "healthy agent mishandled (up=$ok_up total=$ok_total critical=$ok_crit ts=$ok_ts, want up=1 total=3 critical=1 ts=$want_ts)"
    fi
    # A severity the agent did not report must be present as 0 rather than absent,
    # or a dashboard silently loses the series.
    if grep -q 'severity="low"' "$OUT/security_metrics.prom"; then
        pass "unreported severities are published as 0, not omitted"
    else
        fail "unreported severity series is missing"
    fi
    stop_stub
fi

# ---------------------------------------------------------------------------
# 2. The critical property: an unreachable agent must not look like zero findings.
#    Emitting zeros here is the exact confusion this exporter exists to prevent.
# ---------------------------------------------------------------------------
port=$(start_stub good); stop_stub   # start then kill, so the port is closed
run_exporter "$port"
if [ "$(metric spectre_agent_up)" = "0" ] && ! has_metric security_findings_unresolved; then
    pass "an unreachable agent publishes agent_up 0 and no finding counts"
else
    fail "unreachable agent produced counts or a healthy reading (up=$(metric spectre_agent_up))"
fi

# ---------------------------------------------------------------------------
# 3. A 401 must be reported as down, not as zero findings. This is what a rotated
#    API key looks like, and it must not read as "all clear".
# ---------------------------------------------------------------------------
port=$(start_stub unauthorized)
run_exporter "$port"
if [ "$(metric spectre_agent_up)" = "0" ] && ! has_metric security_findings_unresolved; then
    pass "a 401 is reported as agent down, not as zero findings"
else
    fail "a 401 was not reported as agent down"
fi
stop_stub

# ---------------------------------------------------------------------------
# 4. A malformed body must abort rather than publish zeros. Parsing a broken
#    response as "no findings" is how fabricated metrics come back.
# ---------------------------------------------------------------------------
port=$(start_stub garbage)
run_exporter "$port"
if ! has_metric security_findings_unresolved; then
    pass "a malformed response publishes no finding counts"
else
    fail "a malformed response produced finding counts"
fi
stop_stub

# ---------------------------------------------------------------------------
# 5. A never-scanned agent must be distinguishable from a clean one.
# ---------------------------------------------------------------------------
port=$(start_stub never_scanned)
run_exporter "$port"
if [ "$(metric spectre_security_ever_scanned)" = "0" ] && [ "$(metric security_last_scan_timestamp)" = "0" ] \
   && [ "$(metric security_findings_unresolved)" = "0" ]; then
    pass "a never-scanned agent reports ever_scanned 0 and a zero scan time"
else
    fail "never-scanned state was not reported distinctly"
fi
stop_stub

# ---------------------------------------------------------------------------
# 6. A naive timestamp must be rejected, not assumed to be UTC. Guessing here
#    would put the scan time hours off, and the agent returns aware UTC.
# ---------------------------------------------------------------------------
port=$(start_stub naive_ts)
run_exporter "$port"
if [ "$(metric security_last_scan_timestamp)" = "0" ] && [ "$(metric spectre_agent_up)" = "1" ]; then
    pass "a naive timestamp is rejected to 0 rather than assumed UTC"
else
    fail "a naive timestamp was not rejected (ts=$(metric security_last_scan_timestamp))"
fi
stop_stub

# ---------------------------------------------------------------------------
# 7. A missing key file must fail loudly and still publish agent_up 0, so the
#    failure is visible in Prometheus rather than being a silent cron error.
# ---------------------------------------------------------------------------
rm -f "$OUT/security_metrics.prom"
SPECTRE_API_KEY_FILE="$WORK/nonexistent" "$EXPORTER" "$OUT" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ "$(metric spectre_agent_up)" = "0" ] && ! has_metric security_findings_unresolved; then
    pass "a missing API key file fails loudly and publishes agent_up 0"
else
    fail "a missing API key file was not handled (exit=$rc)"
fi

# ---------------------------------------------------------------------------
# 8. A port collision must be reported as a collision, not as the agent being
#    down. This is the case that shipped: SPECTRE_AGENT_URL was left on a port
#    another stack already held, every scrape got that service's 404, and the
#    result read as "the agent has no such endpoint" -- pointing the debugging at
#    the agent instead of at the port. A different FastAPI app is the hardest
#    variant to catch, because it answers 200 to openapi.json and only a wrong
#    info.title separates it from the agent.
# ---------------------------------------------------------------------------
port=$(start_stub other_service)
run_exporter "$port"
if [ "$(metric spectre_agent_up)" = "0" ] \
   && [ "$(reason_value spectre_agent_up_reason)" = "wrong_service_on_port" ] \
   && [ "$(reason_value spectre_agent_identifies_as)" = "arcaden-labs-api-edge" ] \
   && ! has_metric security_findings_unresolved; then
    pass "a different app on the port is refused and named, not reported as the agent being down"
else
    fail "port collision was not distinguished (up=$(metric spectre_agent_up) reason=$(reason_value spectre_agent_up_reason) identified=$(reason_value spectre_agent_identifies_as))"
fi
stop_stub

# ---------------------------------------------------------------------------
# 9. A web UI squatting on the port is the same class of error, and is caught by
#    the redirect rather than by any JSON inspection.
# ---------------------------------------------------------------------------
port=$(start_stub web_ui)
run_exporter "$port"
if [ "$(metric spectre_agent_up)" = "0" ] \
   && [ "$(reason_value spectre_agent_up_reason)" = "wrong_service_on_port" ] \
   && ! has_metric security_findings_unresolved; then
    pass "a web UI redirect on the port is refused as a collision"
else
    fail "web UI on the port was not distinguished (up=$(metric spectre_agent_up) reason=$(reason_value spectre_agent_up_reason))"
fi
stop_stub

# ---------------------------------------------------------------------------
# 10. A refused connection is an outage, not a collision, so it must NOT publish
#     spectre_agent_identifies_as. If it did, SecurityAgentWrongServiceOnPort
#     would fire on every time the agent is merely stopped, which is the exact
#     confusion the split exists to prevent.
# ---------------------------------------------------------------------------
SPECTRE_AGENT_URL="http://127.0.0.1:1" \
SPECTRE_API_KEY_FILE="$KEY_FILE" \
SPECTRE_TIMEOUT=3 \
    "$EXPORTER" "$OUT" >/dev/null 2>&1
if [ "$(metric spectre_agent_up)" = "0" ] \
   && [ "$(reason_value spectre_agent_up_reason)" = "connection_refused" ] \
   && ! has_metric spectre_agent_identifies_as; then
    pass "an unreachable agent is an outage, not a collision, and publishes no identifies_as"
else
    fail "an outage was misreported as a collision (reason=$(reason_value spectre_agent_up_reason) identifies_as=$(reason_value spectre_agent_identifies_as))"
fi

echo ""
echo "Security exporter tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]

