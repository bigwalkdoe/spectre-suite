#!/usr/bin/env bash
# Read-only monitoring stack checks: Prometheus route-prefix reachability and
# Grafana->Prometheus datasource/connectivity drift (spectre-suite incident 2026-11-09).
# Formats: text (default) or prom (MONITORING_CHECK_FORMAT=prom / --format prom).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_REPO_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../" && pwd)}"
export SPECTRE_REPO_ROOT

FORMAT="${MONITORING_CHECK_FORMAT:-text}"
while [ $# -gt 0 ]; do
  case "$1" in
    --format) FORMAT="${2:-text}"; shift 2 ;;
    --format=*) FORMAT="${1#*=}"; shift ;;
    *) shift ;;
  esac
done

PROMETHEUS_HOST_URL="${PROMETHEUS_HOST_URL:-http://127.0.0.1:9090}"
PROMETHEUS_ROUTE_PREFIX="${PROMETHEUS_ROUTE_PREFIX:-/prometheus}"
GRAFANA_HOST_URL="${GRAFANA_HOST_URL:-http://127.0.0.1:3002}"
GRAFANA_SUBPATH="${GRAFANA_SUBPATH:-/grafana}"
EXPECTED_DS_URL="${EXPECTED_PROMETHEUS_DATASOURCE_URL:-http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}}"
TIMEOUT="${MONITORING_CHECK_TIMEOUT:-5}"

failures=0 warnings=0 passes=0
# -1 unknown, 0 bad, 1 ok
M_PROM_HEALTHY=-1 M_PROM_READY=-1 M_PROM_BUILDINFO=-1
M_GRAFANA_NET=-1 M_DS_PROV_OK=-1 M_DS_URL_MATCH=-1 M_DS_HEALTH=-1

is_text() { [ "$FORMAT" = "text" ]; }
ok()   { passes=$((passes+1)); is_text && echo "[PASS] $*" || true; }
warn() { warnings=$((warnings+1)); is_text && echo "[WARN] $*" || true; }
bad()  { failures=$((failures+1)); is_text && echo "[FAIL] $*" || true; }
info() { is_text && echo "[INFO] $*" || true; }

http_code() { curl -sS -m "$TIMEOUT" -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo "000"; }
http_body() { curl -sS -m "$TIMEOUT" "$1" 2>/dev/null || true; }

check_prometheus_host() {
  info "Prometheus host checks: ${PROMETHEUS_HOST_URL} prefix ${PROMETHEUS_ROUTE_PREFIX}"
  local base="${PROMETHEUS_HOST_URL%/}${PROMETHEUS_ROUTE_PREFIX}" code body
  code="$(http_code "${base}/-/healthy")"
  if [ "$code" = "200" ]; then ok "Prometheus healthy at ${base}/-/healthy (200)"; M_PROM_HEALTHY=1;
  else bad "Prometheus healthy endpoint ${base}/-/healthy returned ${code} (expected 200; check route-prefix/external-url)"; M_PROM_HEALTHY=0; fi

  code="$(http_code "${base}/-/ready")"
  if [ "$code" = "200" ]; then ok "Prometheus ready at ${base}/-/ready (200)"; M_PROM_READY=1;
  else bad "Prometheus ready endpoint ${base}/-/ready returned ${code}"; M_PROM_READY=0; fi

  body="$(http_body "${base}/api/v1/status/buildinfo")"
  if printf '%s' "$body" | grep -q '"status":"success"'; then ok "Prometheus buildinfo reachable under route prefix"; M_PROM_BUILDINFO=1;
  else warn "Prometheus buildinfo not successful at ${base}/api/v1/status/buildinfo (may be auth/network constrained)"; M_PROM_BUILDINFO=0; fi

  code="$(http_code "${PROMETHEUS_HOST_URL%/}/-/healthy")"
  if [ "$code" = "404" ] && [ "${PROMETHEUS_ROUTE_PREFIX}" != "" ] && [ "${PROMETHEUS_ROUTE_PREFIX}" != "/" ]; then
    info "Root /-/healthy returned 404 while route-prefix=${PROMETHEUS_ROUTE_PREFIX} (expected in this config)."
  fi
}

check_grafana_container_network() {
  if ! command -v docker >/dev/null 2>&1; then warn "docker not available; skipping Grafana container network check"; M_GRAFANA_NET=-1; return; fi
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'grafana'; then warn "grafana container not running; skipping in-network check"; M_GRAFANA_NET=-1; return; fi
  local out
  out="$(docker exec grafana wget -qO- --timeout="$TIMEOUT" "http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}/-/healthy" 2>&1 || true)"
  if printf '%s' "$out" | grep -qi 'Prometheus .*Healthy\|is Healthy'; then
    ok "Grafana container can reach Prometheus at http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}/-/healthy"; M_GRAFANA_NET=1
  elif printf '%s' "$out" | grep -qi 'No route to host\|Host is unreachable\|timed out\|Connection refused'; then
    bad "Grafana container cannot reach Prometheus in-network: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-180)"; M_GRAFANA_NET=0
  else
    warn "Grafana container probe inconclusive: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-180)"; M_GRAFANA_NET=-1
  fi
}

load_grafana_creds() {
  GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-${GF_SECURITY_ADMIN_USER:-}}"
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-${GF_SECURITY_ADMIN_PASSWORD:-}}"
  if [ -n "${GRAFANA_ADMIN_USER:-}" ] && [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]; then return 0; fi
  local envf="$SPECTRE_REPO_ROOT/.env"
  [ -f "$envf" ] || return 1
  python3 - "$envf" <<'PY'
import shlex, sys
path=sys.argv[1]
for line in open(path):
    line=line.strip()
    if not line or line.startswith('#') or '=' not in line: continue
    k,v=line.split('=',1)
    if k in ('GRAFANA_ADMIN_USER','GRAFANA_ADMIN_PASSWORD','GF_SECURITY_ADMIN_USER','GF_SECURITY_ADMIN_PASSWORD'):
        v=v.strip().strip('"').strip("'")
        print(f"export {k}={shlex.quote(v)}")
PY
}

check_grafana_datasource() {
  local creds prov
  creds="$(load_grafana_creds 2>/dev/null || true)"
  if [ -n "$creds" ]; then eval "$creds"; fi
  GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-${GF_SECURITY_ADMIN_USER:-admin}}"
  GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-${GF_SECURITY_ADMIN_PASSWORD:-}}"
  prov="$SPECTRE_REPO_ROOT/grafana-provisioning/datasources/prometheus.yml"
  if [ -f "$prov" ]; then
    if grep -q "url: *http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}" "$prov"; then
      ok "Provisioned Prometheus datasource includes route prefix (${prov})"; M_DS_PROV_OK=1
    else
      bad "Provisioned Prometheus datasource missing expected route prefix ${PROMETHEUS_ROUTE_PREFIX} (${prov})"; M_DS_PROV_OK=0
    fi
  fi
  if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
    warn "Grafana admin credentials unavailable; skipping live datasource API/health check (set GRAFANA_ADMIN_PASSWORD or repo .env)"
    return
  fi
  local api="${GRAFANA_HOST_URL%/}${GRAFANA_SUBPATH}/api" resp code url uid h
  resp="$(curl -sS -m "$TIMEOUT" -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" -w '\n%{http_code}' "${api}/datasources/name/Prometheus" 2>/dev/null || true)"
  code="$(printf '%s' "$resp" | tail -n1)"
  resp="$(printf '%s' "$resp" | sed '$d')"
  if [ "$code" != "200" ]; then
    warn "Grafana datasource API check failed at ${api}/datasources/name/Prometheus (HTTP ${code}); check GRAFANA_SUBPATH/URL/credentials"
    M_DS_URL_MATCH=-1; M_DS_HEALTH=-1; return
  fi
  url="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("url",""))' 2>/dev/null || true)"
  uid="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("uid",""))' 2>/dev/null || true)"
  if [ "$url" = "$EXPECTED_DS_URL" ]; then
    ok "Grafana Prometheus datasource URL matches expected (${url})"; M_DS_URL_MATCH=1
  else
    bad "Grafana Prometheus datasource URL drift: live='${url}' expected='${EXPECTED_DS_URL}' uid='${uid}'"; M_DS_URL_MATCH=0
  fi
  h="$(curl -sS -m "$TIMEOUT" -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "${api}/datasources/uid/${uid}/health" 2>/dev/null || true)"
  if printf '%s' "$h" | grep -q '"status":"OK"\|Successfully queried'; then
    ok "Grafana Prometheus datasource health OK (uid=${uid})"; M_DS_HEALTH=1
  elif printf '%s' "$h" | grep -qi 'no route to host\|connection refused\|Host is unreachable'; then
    bad "Grafana Prometheus datasource health reports network reachability failure (uid=${uid})"; M_DS_HEALTH=0
  elif printf '%s' "$h" | grep -qi '404\|Not Found'; then
    bad "Grafana Prometheus datasource health reports 404 (likely missing route prefix; live url='${url}')"; M_DS_HEALTH=0
  else
    warn "Grafana Prometheus datasource health inconclusive (uid=${uid}): $(printf '%s' "$h" | tr '\n' ' ' | cut -c1-200)"; M_DS_HEALTH=-1
  fi
}

emit_prom() {
  local ts overall=1
  ts="$(date +%s)"
  if [ "$failures" -gt 0 ]; then overall=0; fi
  cat <<EOF
# HELP spectre_monitoring_check_timestamp_seconds Unix time this monitoring stack check ran
# TYPE spectre_monitoring_check_timestamp_seconds gauge
spectre_monitoring_check_timestamp_seconds $ts
# HELP spectre_monitoring_check_ok 1 if the monitoring stack check found no failures, 0 otherwise
# TYPE spectre_monitoring_check_ok gauge
spectre_monitoring_check_ok $overall
# HELP spectre_monitoring_prometheus_routeprefix_healthy 1 healthy under configured route prefix, 0 unhealthy, -1 unknown
# TYPE spectre_monitoring_prometheus_routeprefix_healthy gauge
spectre_monitoring_prometheus_routeprefix_healthy $M_PROM_HEALTHY
# HELP spectre_monitoring_prometheus_ready 1 ready under configured route prefix, 0 not ready, -1 unknown
# TYPE spectre_monitoring_prometheus_ready gauge
spectre_monitoring_prometheus_ready $M_PROM_READY
# HELP spectre_monitoring_grafana_to_prometheus_reachable 1 Grafana container can reach Prometheus in-network, 0 unreachable, -1 unknown/skipped
# TYPE spectre_monitoring_grafana_to_prometheus_reachable gauge
spectre_monitoring_grafana_to_prometheus_reachable $M_GRAFANA_NET
# HELP spectre_monitoring_grafana_datasource_provisioning_ok 1 provisioned Prometheus datasource URL includes expected route prefix, 0 drift, -1 unknown
# TYPE spectre_monitoring_grafana_datasource_provisioning_ok gauge
spectre_monitoring_grafana_datasource_provisioning_ok $M_DS_PROV_OK
# HELP spectre_monitoring_grafana_datasource_url_matches 1 live Grafana datasource URL matches expected, 0 drift, -1 unknown/skipped
# TYPE spectre_monitoring_grafana_datasource_url_matches gauge
spectre_monitoring_grafana_datasource_url_matches $M_DS_URL_MATCH
# HELP spectre_monitoring_grafana_datasource_healthy 1 Grafana reports Prometheus datasource healthy, 0 unhealthy, -1 unknown/skipped
# TYPE spectre_monitoring_grafana_datasource_healthy gauge
spectre_monitoring_grafana_datasource_healthy $M_DS_HEALTH
EOF
}

main() {
  check_prometheus_host
  check_grafana_container_network
  check_grafana_datasource
  if [ "$FORMAT" = "prom" ]; then
    emit_prom
  else
    echo "== Spectre monitoring stack check =="
    echo "repo=$SPECTRE_REPO_ROOT"
    # Text mode already printed pass/warn/fail/info lines as checks ran.
    echo "== Summary =="
    echo "pass=$passes warn=$warnings fail=$failures"
  fi
  if [ "$failures" -gt 0 ]; then exit 1; fi
  exit 0
}

if [ "${BASH_SOURCE[0]-$0}" = "${0-}" ]; then main "$@"; fi
