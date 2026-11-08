#!/usr/bin/env bash
# Read-only monitoring stack checks: Prometheus route-prefix reachability and
# Grafana->Prometheus datasource/connectivity drift (spectre-suite incident 2026-11-09).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Resolve repo root (spectre/actions/monitoring -> repo root)
SPECTRE_REPO_ROOT="$(cd "$SCRIPT_DIR/../../../" && pwd)"
export SPECTRE_REPO_ROOT

PROMETHEUS_HOST_URL="${PROMETHEUS_HOST_URL:-http://127.0.0.1:9090}"
PROMETHEUS_ROUTE_PREFIX="${PROMETHEUS_ROUTE_PREFIX:-/prometheus}"
GRAFANA_HOST_URL="${GRAFANA_HOST_URL:-http://127.0.0.1:3002}"
GRAFANA_SUBPATH="${GRAFANA_SUBPATH:-/grafana}"
COMPOSE_FILE="${MONITORING_COMPOSE_FILE:-$SPECTRE_REPO_ROOT/docker-compose.monitoring.yml}"
EXPECTED_DS_URL="${EXPECTED_PROMETHEUS_DATASOURCE_URL:-http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}}"
TIMEOUT="${MONITORING_CHECK_TIMEOUT:-5}"

failures=0
warnings=0
passes=0

ok()   { echo "[PASS] $*"; passes=$((passes+1)); }
warn() { echo "[WARN] $*"; warnings=$((warnings+1)); }
bad()  { echo "[FAIL] $*"; failures=$((failures+1)); }
info() { echo "[INFO] $*"; }

http_code() {
  local url="$1"
  curl -sS -m "$TIMEOUT" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000"
}

http_body() {
  local url="$1"
  curl -sS -m "$TIMEOUT" "$url" 2>/dev/null || true
}

check_prometheus_host() {
  info "Prometheus host checks: ${PROMETHEUS_HOST_URL} prefix ${PROMETHEUS_ROUTE_PREFIX}"
  local base="${PROMETHEUS_HOST_URL%/}${PROMETHEUS_ROUTE_PREFIX}"
  local code body
  code="$(http_code "${base}/-/healthy")"
  if [ "$code" = "200" ]; then ok "Prometheus healthy at ${base}/-/healthy (200)";
  else bad "Prometheus healthy endpoint ${base}/-/healthy returned ${code} (expected 200; check route-prefix/external-url)"; fi

  code="$(http_code "${base}/-/ready")"
  if [ "$code" = "200" ]; then ok "Prometheus ready at ${base}/-/ready (200)";
  else bad "Prometheus ready endpoint ${base}/-/ready returned ${code}"; fi

  body="$(http_body "${base}/api/v1/status/buildinfo")"
  if printf '%s' "$body" | grep -q '"status":"success"'; then ok "Prometheus buildinfo reachable under route prefix";
  else warn "Prometheus buildinfo not successful at ${base}/api/v1/status/buildinfo (may be auth/network constrained)"; fi

  # Guard: root path often 404 when route-prefix is set; report explicitly.
  code="$(http_code "${PROMETHEUS_HOST_URL%/}/-/healthy")"
  if [ "$code" = "404" ] && [ "${PROMETHEUS_ROUTE_PREFIX}" != "" ] && [ "${PROMETHEUS_ROUTE_PREFIX}" != "/" ]; then
    info "Root /-/healthy returned 404 while route-prefix=${PROMETHEUS_ROUTE_PREFIX} (expected in this config)."
  fi
}

check_grafana_container_network() {
  if ! command -v docker >/dev/null 2>&1; then warn "docker not available; skipping Grafana container network check"; return; fi
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'grafana'; then warn "grafana container not running; skipping in-network check"; return; fi
  local out
  out="$(docker exec grafana wget -qO- --timeout="$TIMEOUT" "http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}/-/healthy" 2>&1 || true)"
  if printf '%s' "$out" | grep -qi 'Prometheus .*Healthy\|is Healthy'; then
    ok "Grafana container can reach Prometheus at http://prometheus:9090${PROMETHEUS_ROUTE_PREFIX}/-/healthy"
  elif printf '%s' "$out" | grep -qi 'No route to host\|Host is unreachable\|timed out\|Connection refused'; then
    bad "Grafana container cannot reach Prometheus in-network: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-180)"
  else
    warn "Grafana container probe inconclusive: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-180)"
  fi
}

load_grafana_creds() {
  # Never print secrets. Prefer explicit env; fall back to repo .env when present.
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
      ok "Provisioned Prometheus datasource includes route prefix (${prov})"
    else
      bad "Provisioned Prometheus datasource missing expected route prefix ${PROMETHEUS_ROUTE_PREFIX} (${prov})"
    fi
  fi
  if [ -z "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
    warn "Grafana admin credentials unavailable; skipping live datasource API/health check (set GRAFANA_ADMIN_PASSWORD or repo .env)"
    return
  fi
  local api="${GRAFANA_HOST_URL%/}${GRAFANA_SUBPATH}/api"
  local resp code
  resp="$(curl -sS -m "$TIMEOUT" -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" -w '\n%{http_code}' "${api}/datasources/name/Prometheus" 2>/dev/null || true)"
  code="$(printf '%s' "$resp" | tail -n1)"
  resp="$(printf '%s' "$resp" | sed '$d')"
  if [ "$code" != "200" ]; then
    warn "Grafana datasource API check failed at ${api}/datasources/name/Prometheus (HTTP ${code}); check GRAFANA_SUBPATH/URL/credentials"
    return
  fi
  local url uid
  url="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("url",""))' 2>/dev/null || true)"
  uid="$(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("uid",""))' 2>/dev/null || true)"
  if [ "$url" = "$EXPECTED_DS_URL" ]; then
    ok "Grafana Prometheus datasource URL matches expected (${url})"
  else
    bad "Grafana Prometheus datasource URL drift: live='${url}' expected='${EXPECTED_DS_URL}' uid='${uid}'"
  fi
  local h
  h="$(curl -sS -m "$TIMEOUT" -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" "${api}/datasources/uid/${uid}/health" 2>/dev/null || true)"
  if printf '%s' "$h" | grep -q '"status":"OK"\|Successfully queried'; then
    ok "Grafana Prometheus datasource health OK (uid=${uid})"
  elif printf '%s' "$h" | grep -qi 'no route to host\|connection refused\|Host is unreachable'; then
    bad "Grafana Prometheus datasource health reports network reachability failure (uid=${uid})"
  elif printf '%s' "$h" | grep -qi '404\|Not Found'; then
    bad "Grafana Prometheus datasource health reports 404 (likely missing route prefix; live url='${url}')"
  else
    warn "Grafana Prometheus datasource health inconclusive (uid=${uid}): $(printf '%s' "$h" | tr '\n' ' ' | cut -c1-200)"
  fi
}

main() {
  echo "== Spectre monitoring stack check =="
  echo "repo=$SPECTRE_REPO_ROOT"
  check_prometheus_host
  check_grafana_container_network
  check_grafana_datasource
  echo "== Summary =="
  echo "pass=$passes warn=$warnings fail=$failures"
  if [ "$failures" -gt 0 ]; then exit 1; fi
  exit 0
}

if [ "${BASH_SOURCE[0]-$0}" = "${0-}" ]; then main "$@"; fi
