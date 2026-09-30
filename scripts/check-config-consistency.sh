#!/bin/bash
# Checks that monitoring configuration refers to things that actually exist.
#
# The job this replaces ("Configuration Drift Detection") globbed the config
# files and echoed "OK" for each one it found. It could not fail, so a scrape
# target naming a service that no longer exists, or an nginx proxy pointing at a
# misspelled upstream, was only discovered at container start.
#
# The failure this exists to catch: a name in prometheus.yml or the dashboard's
# nginx proxy that is not a service in docker-compose.monitoring.yml. Those
# resolve to a permanently-down target, which looks like a Prometheus problem
# rather than a typo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
COMPOSE="$PROJECT_ROOT/docker-compose.monitoring.yml"
PROMETHEUS="$PROJECT_ROOT/prometheus/prometheus.yml"
NGINX_CONF="$PROJECT_ROOT/web-dashboard/nginx.conf"

# Hosts that are legitimately not compose service names.
ALLOWED_HOSTS="localhost 127.0.0.1 ::1 host.docker.internal"

fail=0

# Service names from the `services:` block only. A plain `^  name:$` match would
# also pick up the network and volume names further down the file, letting a
# typo that happens to collide with a volume name pass.
services=$(
    awk '
        /^services:/ { in_services = 1; next }
        /^[a-zA-Z]/   { in_services = 0 }
        in_services && /^  [a-zA-Z0-9._-]+:[[:space:]]*$/ {
            name = $0
            sub(/^  /, "", name)
            sub(/:[[:space:]]*$/, "", name)
            print name
        }
    ' "$COMPOSE" | sort -u
)

if [ -z "$services" ]; then
    echo "ERROR: could not read any service names from $COMPOSE" >&2
    exit 1
fi

# Host portion of every scrape target and of every relabel replacement.
referenced_hosts=$(
    grep -oE "(targets|replacement):[[:space:]]*(\[[^]]*\]|'[^']*')" "$PROMETHEUS" \
        | grep -oE "'[^']+'" | tr -d "'" | cut -d: -f1 | sort -u
)

check_host() {
    local host="$1" source="$2"
    for allowed in $ALLOWED_HOSTS; do
        [ "$host" = "$allowed" ] && return 0
    done
    if ! printf '%s\n' "$services" | grep -qx "$host"; then
        echo "ERROR: $source refers to '$host', which is not a service in $(basename "$COMPOSE")" >&2
        fail=1
    fi
}

for host in $referenced_hosts; do
    check_host "$host" "prometheus.yml"
done

# The dashboard reaches Prometheus through this proxy, so a misspelled upstream
# breaks every dashboard query while Prometheus itself looks healthy.
if [ -f "$NGINX_CONF" ]; then
    nginx_upstreams=$(
        grep -oE 'proxy_pass[[:space:]]+https?://[^/]+' "$NGINX_CONF" \
            | sed -E 's#.*https?://([^/:]+).*#\1#' | sort -u
    )
    for host in $nginx_upstreams; do
        check_host "$host" "web-dashboard/nginx.conf"
    done
fi

# Every service's memory limit, read with the same `services:`-scoped awk pass so
# that a block cannot be attributed to a network or volume.
#
# This check exists because a `deploy:` block placed *before* the service it
# documents is still valid YAML: at four-space indentation it silently attaches
# to the preceding service instead. All eleven limits in this file were shifted by
# one -- Grafana's 1 GiB was applied to Prometheus, cAdvisor's 256 MiB to
# node-exporter, and web-dashboard's limit ended up on the `monitoring` network.
# `docker compose config` reported the file as valid, so nothing caught it. The
# table below pins the intended limit per service; changing one on purpose means
# changing it here too.
expected_limits="prometheus:none
grafana:1g
alertmanager:512m
node-exporter:256m
cadvisor:256m
redis-exporter:512m
postgres-exporter:128m
redis:128m
postgres:512m
blackbox-exporter:1g
web-dashboard:128m"

actual_limits=$(
    awk '
        /^services:/ { in_services = 1; next }
        /^[a-zA-Z]/   { in_services = 0 }
        !in_services  { next }
        /^  [a-zA-Z0-9._-]+:[[:space:]]*$/ {
            if (name != "") printf "%s:%s\n", name, (limit == "" ? "none" : limit)
            name = $0
            sub(/^  /, "", name); sub(/:[[:space:]]*$/, "", name)
            limit = ""; in_deploy = 0
            next
        }
        /^    deploy:/ { in_deploy = 1; next }
        /^    [a-zA-Z]/ { in_deploy = 0 }
        in_deploy && /^ *memory:/ { limit = $2 }
        END { if (name != "") printf "%s:%s\n", name, (limit == "" ? "none" : limit) }
    ' "$COMPOSE"
)

if [ "$actual_limits" != "$expected_limits" ]; then
    echo "ERROR: memory limits do not match the intended per-service table." >&2
    echo "  A 'deploy:' block written before the service it documents attaches to" >&2
    echo "  the previous service instead. Diff (expected vs actual):" >&2
    diff <(printf '%s\n' "$expected_limits") <(printf '%s\n' "$actual_limits") >&2 || true
    fail=1
fi

# A resource limit under a network or volume is always wrong: those accept none,
# and Compose ignores the stray key without complaining. Only limit-bearing keys
# are flagged, since `driver` and `name` are legitimate there.
stray=$(awk '
    /^services:/ { in_services = 1; next }
    /^[a-zA-Z]/   { in_services = 0 }
    !in_services && /^  (monitoring|prometheus-data|grafana-data|alertmanager-data|postgres-data):/ { in_net = 1; next }
    in_net && /^    (deploy|mem_limit|cpus|mem_reservation):/ { print "  - " $1 " attached to a network or volume" }
' "$COMPOSE")
if [ -n "$stray" ]; then
    echo "ERROR: keys that cannot belong to a network or volume:" >&2
    printf '%s\n' "$stray" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "config consistency check FAILED" >&2
    exit 1
fi

echo "config consistency OK: $(printf '%s\n' "$referenced_hosts" | grep -c .) prometheus target host(s) and $(printf '%s\n' "${nginx_upstreams:-}" | grep -c . || echo 0) nginx upstream(s) all resolve to compose services; $(printf '%s\n' "$actual_limits" | grep -c .) service memory limit(s) on the intended service"
