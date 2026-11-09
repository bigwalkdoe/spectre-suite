#!/usr/bin/env bash
# Tests for spectre/actions/monitoring/check-monitoring-stack.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET="$PROJECT_ROOT/spectre/actions/monitoring/check-monitoring-stack.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass=0; fail=0
assert_contains() {
  local hay="$1" needle="$2" msg="$3"
  if printf '%s' "$hay" | grep -Fq "$needle"; then echo -e "${GREEN}PASS${NC} $msg"; pass=$((pass+1));
  else echo -e "${RED}FAIL${NC} $msg (missing: $needle)"; echo "$hay"; fail=$((fail+1)); fi
}
assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" = "$want" ]; then echo -e "${GREEN}PASS${NC} $msg"; pass=$((pass+1));
  else echo -e "${RED}FAIL${NC} $msg (got=$got want=$want)"; fail=$((fail+1)); fi
}

echo "== monitoring stack check tests =="

# Syntax
bash -n "$TARGET" && echo -e "${GREEN}PASS${NC} syntax" && pass=$((pass+1)) || { echo -e "${RED}FAIL${NC} syntax"; fail=$((fail+1)); }

# Mock Prometheus + temp repo
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null || true' EXIT
mkdir -p "$TMP/grafana-provisioning/datasources" "$TMP/spectre/actions/monitoring"
cat > "$TMP/grafana-provisioning/datasources/prometheus.yml" <<'YML'
apiVersion: 1
datasources:
  - name: Prometheus
    url: http://prometheus:9090/prometheus
YML
cp "$TARGET" "$TMP/spectre/actions/monitoring/check-monitoring-stack.sh"
chmod +x "$TMP/spectre/actions/monitoring/check-monitoring-stack.sh"

PORT=18091
python3 - "$PORT" <<'PY' >"$TMP/mock-prom.log" 2>&1 &
import http.server, sys
port=int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/prometheus/-/healthy','/prometheus/-/ready'):
            self.send_response(200); self.end_headers(); self.wfile.write(b'Prometheus Server is Healthy.')
        elif self.path == '/prometheus/api/v1/status/buildinfo':
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
            self.wfile.write(b'{"status":"success","data":{"version":"test"}}')
        elif self.path == '/-/healthy':
            self.send_response(404); self.end_headers(); self.wfile.write(b'404')
        else:
            self.send_response(404); self.end_headers()
    def log_message(self,*a): pass
http.server.HTTPServer(('127.0.0.1',port), H).serve_forever()
PY
SRV_PID=$!
sleep 0.4

set +e
OUT=$(PROMETHEUS_HOST_URL="http://127.0.0.1:$PORT" PROMETHEUS_ROUTE_PREFIX=/prometheus \
  SPECTRE_REPO_ROOT="$TMP" GRAFANA_ADMIN_PASSWORD='' \
  bash "$TMP/spectre/actions/monitoring/check-monitoring-stack.sh" 2>&1)
RC=$?
set -e
assert_contains "$OUT" "[PASS] Prometheus healthy" "healthy pass"
assert_contains "$OUT" "[PASS] Prometheus ready" "ready pass"
assert_contains "$OUT" "[PASS] Prometheus buildinfo reachable under route prefix" "buildinfo pass"
assert_contains "$OUT" "Provisioned Prometheus datasource includes route prefix" "provisioning pass"
assert_contains "$OUT" "fail=0" "no failures"
assert_eq "$RC" "0" "exit 0"

# Drift case: bad provisioning URL
cat > "$TMP/grafana-provisioning/datasources/prometheus.yml" <<'YML'
apiVersion: 1
datasources:
  - name: Prometheus
    url: http://prometheus:9090
YML
set +e
OUT2=$(PROMETHEUS_HOST_URL="http://127.0.0.1:$PORT" PROMETHEUS_ROUTE_PREFIX=/prometheus \
  SPECTRE_REPO_ROOT="$TMP" GRAFANA_ADMIN_PASSWORD='' \
  bash "$TMP/spectre/actions/monitoring/check-monitoring-stack.sh" 2>&1)
RC2=$?
set -e
assert_contains "$OUT2" "[FAIL] Provisioned Prometheus datasource missing expected route prefix" "detects provisioning drift"
assert_eq "$RC2" "1" "exit 1 on drift"

echo "== Summary: pass=$pass fail=$fail =="
if [ "$fail" -gt 0 ]; then exit 1; fi
exit 0
