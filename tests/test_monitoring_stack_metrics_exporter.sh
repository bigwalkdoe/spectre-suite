#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CHECK="$PROJECT_ROOT/spectre/actions/monitoring/check-monitoring-stack.sh"
EXPORTER="$PROJECT_ROOT/spectre/monitoring/exporters/monitoring-stack-metrics-exporter.sh"
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
pass=0; fail=0
assert_contains() { if printf '%s' "$1" | grep -Fq "$2"; then echo -e "${GREEN}PASS${NC} $3"; pass=$((pass+1)); else echo -e "${RED}FAIL${NC} $3 (missing $2)"; fail=$((fail+1)); fi; }

echo "== monitoring stack metrics exporter tests =="
bash -n "$CHECK" && bash -n "$EXPORTER" && echo -e "${GREEN}PASS${NC} syntax" && pass=$((pass+1)) || { echo -e "${RED}FAIL${NC} syntax"; fail=$((fail+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"; [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null || true' EXIT
mkdir -p "$TMP/grafana-provisioning/datasources" "$TMP/out"
cat > "$TMP/grafana-provisioning/datasources/prometheus.yml" <<'YML'
apiVersion: 1
datasources:
  - name: Prometheus
    url: http://prometheus:9090/prometheus
YML
PORT=18092
python3 - "$PORT" <<'PY' >/dev/null 2>&1 &
import http.server, sys
port=int(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/prometheus/-/healthy','/prometheus/-/ready'):
            self.send_response(200); self.end_headers(); self.wfile.write(b'Healthy')
        elif self.path == '/prometheus/api/v1/status/buildinfo':
            self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b'{"status":"success","data":{}}')
        else:
            self.send_response(404); self.end_headers()
    def log_message(self,*a): pass
http.server.HTTPServer(('127.0.0.1',port), H).serve_forever()
PY
SRV_PID=$!; sleep 0.3

OUT=$(PROMETHEUS_HOST_URL="http://127.0.0.1:$PORT" PROMETHEUS_ROUTE_PREFIX=/prometheus SPECTRE_REPO_ROOT="$TMP" GRAFANA_ADMIN_PASSWORD='' MONITORING_CHECK_FORMAT=prom bash "$CHECK" 2>&1) || true
assert_contains "$OUT" "spectre_monitoring_check_ok 1" "overall ok"
assert_contains "$OUT" "spectre_monitoring_prometheus_routeprefix_healthy 1" "routeprefix healthy"
assert_contains "$OUT" "spectre_monitoring_grafana_datasource_provisioning_ok 1" "provisioning ok"
assert_contains "$OUT" "spectre_monitoring_grafana_datasource_url_matches -1" "live url unknown without creds"

SPECTRE_REPO_ROOT="$TMP" PROMETHEUS_HOST_URL="http://127.0.0.1:$PORT" PROMETHEUS_ROUTE_PREFIX=/prometheus GRAFANA_ADMIN_PASSWORD='' "$EXPORTER" "$TMP/out" >/dev/null 2>&1
assert_contains "$(cat "$TMP/out/monitoring_stack_metrics.prom")" "spectre_monitoring_check_ok 1" "exporter writes file"

echo "== Summary: pass=$pass fail=$fail =="
[ "$fail" -eq 0 ]
